# ASL Compiler Overview

## What is ASL?

ASL (a Software Language) is a statically-typed systems programming
language for mission-critical software. The syntax is
indentation-based with modules as the primary unit of organization.

```asl
import { User } from "./user.asl"

generic Eq:
  func eq(a: Eq, b: Eq): u8

public module App:
  struct:
    name: String
    age: u32

  public func start(sys: System): u8
    user = User { name: "Alice", age: 30 }
    result = match user.age:
      case 0:
        System.println("newborn")
      case other:
        System.println("older")
    u8 0
```

### Language Features

- **Modules**: top-level blocks containing an optional data block
  (struct or union) and functions
- **Structs**: product types with named fields (`struct: name: String`)
- **Unions**: sum types with named variants, each optionally carrying
  fields (`union: Free { usage: u32 }; Pro { credits: u32 }`)
- **Functions**: typed, overloadable by parameter signature. Method
  call syntax via `Type.method(args)`. Two kinds: user functions
  (with a body) and extern functions (`@extern("symbol")` linking
  to an external implementation)
- **Generics**: type-parameterized function signature blocks
  (`generic Eq: func eq(a: Eq, b: Eq): u8`)
- **Pattern matching**: `match` expressions with integer literals,
  variable bindings, and variant destructuring
  (`case Pro { credits: c }: ...`)
- **Imports**: cross-file module/generic imports with aliasing
  (`import { User as U } from "./user.asl"`)
- **Visibility**: `public` keyword on modules and functions to
  mark them as exported
- **Comments**: line comments starting with `#`

### Built-in Types

Fixed-width integers: `i8`, `i16`, `i32`, `i64`, `u8`, `u16`,
`u32`, `u64`. Floats: `f32`, `f64`. Pointer: `ptr`. Containers:
`String`, `List`, `Map`, `Array`, `Status`. System interface:
`System`.

## Compiler Pipeline

```
Source text
  │
  ▼
Tokenizer ─── seq[Token]
  │
  ▼
Parser ────── App           (raw AST + uniqueness/structural checks
  │                          enforced in constructors, BFS multi-file
  │                          resolution, topo-sorted leaves-first,
  │                          per-file typeIndex covering both imports
  │                          and defined types)
  ▼
Resolver ──── (WIP rewrite) Name/shape resolution only. For each
  │                          file, validates that every ArgumentType
  │                          inside data blocks and function
  │                          signatures refers to something in scope.
  │                          Function bodies are NOT resolved here —
  │                          that belongs to the Analyzer.
  ▼
Analyzer ──── Walks the ResolvedApp end-to-end and produces an
  │              AnalyzedAppDefinition carrying a type-rich view of
  │              every value, expression, and statement in the
  │              program. Each layer of the analyzer mirrors its
  │              resolver counterpart via a `resolved: Resolved*`
  │              back-reference. Overload selection at function-call
  │              sites is wired (each candidate funcDef is unified
  │              against the call's argument types via GenericImplMap
  │              + merge; uniqueness picks the survivor); funcDef
  │              return types and match-subject unions are
  │              concretized via the inferred impls. Union
  │              initializer parametric inference is wired (urkImpl
  │              substitutes user-supplied impls, urkDefault uses
  │              leave-as-is over the position-indexed param list).
  │              Literal initializers, case patterns over all integer
  │              kinds + String, and the per-arg-list literal
  │              validation share one analyzeLiteral helper. The
  │              equality-vs-unification gap (case-arm uniformity)
  │              and a handful of focused TODOs remain — see the
  │              "What's Next" section.
  ▼
(future)
  Codegen   ── target emission (C or LLVM IR).
```

Orchestrated by `src/asl.nim`:
```nim
let app = ? parse(filepath, opts.indentWidth, opts.dumpTokens, opts.vendorRoots)
let resolvedApp = ? resolve(app)
let analyzedApp = ? analyze(resolvedApp)
```

`analyze*` now returns a structured `AnalyzedApp` (wrapping the
`AnalyzedAppDefinition` plus a `seq[AnalyzedFile]` where each
`AnalyzedFile` pairs an `AnalyzedFileDefinition` with the analyzed
modules parsed out of it) rather than the void result it used to.
The type itself is not exported today; the return value is the
handle downstream codegen will thread through.

There is no separate `Validator` phase. Every uniqueness / structural
rule the validator used to enforce (duplicate names, empty blocks,
import collisions, duplicate fields/variants) is now a precondition
inside an AST constructor (`newStruct`, `newUnion`, `newModule`,
`newFile`, etc.). Invalid AST nodes cannot be constructed, so no
separate validation pass is needed.

### Phase 1: Tokenization

`src/tokenizer/tokenizer.nim`

Single-character classifier. Intentionally simple — no keywords, no
multi-character tokens. All that complexity lives in the parser.
Produces `seq[Token]` where each token carries `kind` (punctuation,
space, newline, alphabet, digit, utf8), `value` (the character), and
`Location` (filepath:line:col).

Security: validates UTF-8 encoding and rejects bidirectional control
codepoints, zero-width characters, and invisible Unicode (Trojan
Source defense).

### Phase 2: Parsing

`src/parser/{combinators, helpers, identifiers, strings, numbers,
literals, imports, argtypes, funcdefs, patterns, body, data, funcs,
generics, modules, decls, loader, parser}.nim`

Recursive descent via composable `Spec[T]` combinators:

- `oneOf` — ordered alternatives with backtracking
- `any` / `atLeastOne` — repetition (zero-or-more / one-or-more)
- `optional` — zero-or-one
- `separatedBy` — comma-separated lists
- `contained` — delimited containers (`(...)`, `[...]`, `{...}`)
- `map` — transform parse result
- `blockSpec` / `decoratedBlockSpec` — indented blocks with headers

Backtracking via checkpoint/restore on `parser.index`. Fatal errors
in block bodies bypass backtracking for precise diagnostics.
Forward-declared specs enable mutual recursion
(`expressionSpec ↔ argumentListSpec`).

**Multi-file resolution** (`loader.nim`): BFS traversal of imports,
tokenize + parse each dependency, topological sort via DFS with
cycle detection. Parent-directory escape prevention
(`./sub/../../escape` caught by normalizing the resolved path).

### Phase 3: Parser-level indexing (absorbed)

The parser itself performs the uniqueness / structural checks that
used to live in a separate validator. The lookup indices it builds
during construction double as the validation mechanism (`Table`
insertion fails on duplicate key).

Indices on AST nodes:
- `File.typeIndex` — `Identifier -> int` covering **both** imported
  types and defined types (modules + generics) in one namespace.
- `Module.functionIndex` / `Generic.funcDefIndex` — allow function
  overloading by keying on `seq[int]`.
- `Struct.fieldIndex`, `Union.variantIndex`, `VariantDefinition.fieldIndex`,
  `ArgumentDefinitionList.argDefIndex` — per-block duplicate detection.
- `App.fileIndex` — absolute path → file index.

Every `Type` in a file (imported or defined) is wrapped in a common
`Type` umbrella (`tkImported | tkDefined`) so a single `typeIndex`
lookup serves the resolver.

### Phase 4: Resolution

`src/resolver/{literals, imports, argtypes, funcdefs, funcrefs, body,
data, funcs, modules, definedTypes, files, apps, resolver}.nim`

Returns a `ResolvedApp` containing a `ResolvedFile` per source file,
which in turn holds resolved imports plus a `ResolvedDefinedType` for
each module/generic. Body-level name resolution is complete (variables,
getters, function calls, initializers, match/case patterns). The
resolver also enforces the structural requires-block constraints
(unique generics in requires, must pair with a struct, struct can't
carry generic fields when requires is present) and now stores the
resolved receiver module directly on the default arm of
`ResolvedStructRef` / `ResolvedUnionRef`. Open resolver stubs are
narrow: a few decorator cases and the generic-context
`resolveModuleArgumentType` for explicit `requires(...)` /
`dbkStruct`. Scope:

- **Two-pass walk per file** (files come topo-sorted leaves-first
  from the loader, so imports are always resolved before use).
  - Pass A (declare): register every defined-type name and every
    imported-binding into a `FileScope` as `ResolvedRef`s (file id
    + module/generic kind + index within file).
  - Pass B (define): for each module, resolve its `requires(...)`
    clause (if any, declaring explicit type parameters), its data
    block (struct/union/literal), and each function signature. For
    each generic, resolve each function signature. Every
    `ArgumentType` root must look up in the scope; impls resolve
    recursively. When a module has no explicit `requires` but its
    struct/union fields reference a generic, that generic is treated
    as an inferred type parameter at use sites.
- **Generic param-list accumulation** — `accumulateGenericPosition`
  in `src/resolver/data.nim` walks each field and assigns the next
  position to any generic seen for the first time; repeated
  occurrences keep the position they already have. The result lives
  as `genericTypeIndex: Table[ResolvedGenericArgumentType, int]` on
  `ResolvedStruct` / `ResolvedUnion` and drives the
  position-preserving `requires*` accessor; the analyzer mirrors the
  same index on `AnalyzedStruct` / `AnalyzedUnion` for substitution.
  No uniqueness rule is enforced at resolution time — the same
  generic name appearing in multiple fields (within a struct, within
  a variant, or across variants of one union) is fine, since the
  analyzer's `GenericImplMap` binds one generic to one concrete type
  per construction and surfaces any mismatch as a `merge()` error at
  the init site. Generic-uniqueness inside an explicit `requires(...)`
  block is the one place that *is* checked — see
  `validateRequiresConstraints` in `src/resolver/modules.nim`.
- **Generic signature rule** — inside a generic block, a fn
  argument/return type root may only resolve to the current generic
  itself (self-reference) or a module. Other generics are rejected
  at resolve time, keeping each generic's type world bounded.
- **Body-level name resolution** — the resolver also walks user-
  function bodies: each statement is dispatched, each expression is
  resolved, and every function call is matched against candidate
  function definitions by `(name, arity)` against the target type.
  A `FunctionScope` (HashSet[Identifier]) tracks the names of
  variables currently in scope; the type of each variable is the
  Analyzer's concern. The resolver collects candidate overloads but
  does not pick the unique one — that's the Analyzer.
- **Not the resolver's job**: overload selection (picking the unique
  candidate after matching arg types), generic constraint
  satisfaction (does an impl actually implement the generic), and
  type-correctness checks. Those belong to the Analyzer phase.
- **No structural-size check** — all struct values are pointer-backed
  at runtime, so mutual struct containment does not create infinite
  types. Name cycles are the only cycles, and Pass A dissolves them.

### Phase 5: Analysis

`src/analyzer/{literals, imports, argtypes, funcdefs, funcrefs, body,
data, funcs, modules, patterns, filedefs, appdefs, analyzer}.nim`

Takes a `ResolvedApp` and returns an `AnalyzedAppDefinition` — a
type-rich view of every value, expression, and statement in the
program. Each analyzer type mirrors its resolver counterpart via
`resolved: Resolved*` back-references and derives metadata through
accessors rather than duplicating it. Scope:

- **Overload selection** — at each function-call site, every
  candidate funcDef is unified against the call's argument types
  via `GenericImplMap` + `merge`. The unique survivor is picked;
  ambiguity is rejected.
- **Generic constraint satisfaction** — after unification binds a
  type parameter, the bound type is checked against every function
  signature the generic requires.
- **Concretization** — funcDef return types and match-subject
  unions are rewritten through `concrete()` using the inferred
  impls so downstream sites see substituted types.
- **Union-initializer parametric inference** — the impl arm of
  `UnionRef` substitutes user-supplied impls into variant fields
  before type-check; the default arm walks kwargs accumulating a
  `GenericImplMap` and emits a result type with bound concretes
  where the variant touched a generic and free generics elsewhere
  (leave-as-is).
- **Literal type inference + validation** — the `analyzeLiteral`
  helper at the top of `analyzer/body.nim` dispatches on
  `ResolvedLiteralType` and validates the literal text against all
  integer kinds plus String. `analyzeArgumentList`,
  `analyzeKeywordArgument`, and `analyzeLiteralInitializer` all
  route through it.
- **Case-pattern duplicate detection** — `checkDuplicate[T: SomeInteger]`
  handles all eight integer kinds in `analyzer/patterns.nim`.
- **Body-level constructs** — getter (struct-shaped property read),
  variable case patterns, mutations, assignments, match expressions
  with case-arm bindings, struct + union initializers (default and
  impl), literal initializers.

The remaining gaps are listed in **What's Next**. The headline ones
are the equality-vs-unification trap for free-generic types and the
substitution-chain handling in `concrete()` — both are flagged in
`analyzer/argtypes.nim` and surface as case-arm uniformity check
failures on a handful of fixtures that flow leave-as-is values
through `verifyUniformReturnType`.

## Project Structure

```
src/
  asl.nim                          entry point
  cli.nim                          CLI parsing via argparse
  utils.nim                        topological sort + cycle detection
  nim.cfg                          per-component module search paths

  tokenizer/
    tokenizer.nim                  token types + tokenize() (index-based
                                   rune loop for lookahead)
    location.nim                   Location type + accessors (newLocation,
                                   advance, $, hash, ==, <); re-exported
                                   through tokenizer.nim
    constants.nim                  BidiCodepoints / ZeroWidthCodepoints /
                                   InvisibleCodepoints arrays +
                                   AsciiMaxValue / Punctuations / Space /
                                   Newline constants

  parser/
    parser.nim                     re-exports every component file
    combinators.nim                Spec[T] + combinator procs
    helpers.nim                    shared low-level specs (token kinds,
                                   punctuation, comment, ignorableLine,
                                   separators)
    identifiers.nim                Identifier / Space / Decorator
                                   + identifierSpec / keywordSpec /
                                   indentationSpec / decoratorLineSpec
                                   + blockSpec / decoratedBlockSpec helpers
    strings.nim                    StringContent / StringLiteral +
                                   escapedSpec helpers + stringLiteralSpec
    numbers.nim                    UnsignedIntegerLiteral /
                                   SignedIntegerLiteral / IntegerLiteral /
                                   FloatLiteral + their specs
    literals.nim                   Literal umbrella + LiteralType +
                                   literalSpec / literalTypeSpec
    imports.nim                    ImportedType / Import + their specs
                                   + resolveImportPath
    argtypes.nim                   ArgumentType / ArgumentDefinition /
                                   ArgumentDefinitionList + their specs
    funcdefs.nim                   FunctionDefinition + functionDefinition
                                   line / list specs
    patterns.nim                   VariantPatternField / VariantPattern /
                                   CasePattern + their specs
    body.nim                       Getter / LiteralInitializer +
                                   StructRef + UnionRef (each a tagged
                                   union over default {module} and
                                   impl {argType}, driving initializer
                                   inference vs explicit-impls at the
                                   analyzer) + body-level mutually-
                                   recursive cluster (ArgumentList ↔
                                   FunctionCall ↔ KeywordArgument ↔
                                   Initializer ↔ Expression ↔ Match /
                                   CaseBlock ↔ Statement ↔
                                   StatementList / Assignment /
                                   Mutation) + their specs
                                   (unionInitializerSpec parses via
                                   argumentTypeSpec for symmetry with
                                   structInitializerSpec)
    data.nim                       Struct / VariantDefinition / Union /
                                   DataBlock + their specs
    funcs.nim                      UserFunction / ExternFunction /
                                   Function / FunctionList + their specs
    generics.nim                   Generic / Requires + their specs
    modules.nim                    Module + moduleHeader / moduleBody /
                                   moduleSpec
    decls.nim                      DefinedType / Type / File / App +
                                   typeSpec / definedTypeBlockSpec /
                                   fileSpec + the public single-file
                                   `parse*` entry
    loader.nim                     BFS multi-file resolution + parse*()

  resolver/
    resolver.nim                   re-exports every component file
    literals.nim                   ResolvedLiteralType + resolveLiteralType
    imports.nim                    ResolvedImportedType / ResolvedImport
    argtypes.nim                   FileScope + argument-type cluster
                                   (Argument / Defined / Module)
                                   + resolveDataType post-resolution guard
    funcdefs.nim                   ResolvedArgumentDefinition /
                                   ResolvedFunctionDefinition /
                                   ResolvedExternFunction
    funcrefs.nim                   FunctionScope (variable name set
                                   used by the body walker). Function-
                                   call name resolution is inlined into
                                   resolveFunctionCall in body.nim
                                   since FunctionCall now carries just
                                   an Identifier root (no impls).
    patterns.nim                   ResolvedCasePattern + resolveCasePattern
    body.nim                       Getter / LiteralInitializer +
                                   ResolvedStructRef / ResolvedUnionRef
                                   (each tagged over default / impl;
                                   default arm now carries `module:
                                   Module` — the resolved receiver
                                   module looked up via findModule,
                                   which handles local + imported via
                                   the file's typeIndex; impl arm
                                   carries the resolved ArgumentType,
                                   with the receiver Module reachable
                                   via argType.definedType.module.
                                   module) + body-level cluster
                                   (Initializer ↔ FunctionCall ↔
                                   Expression ↔ Match / CaseBlock ↔
                                   Statement ↔ Assignment / Mutation /
                                   KeywordArgument). resolveStructRef
                                   + resolveUnionRef each do the
                                   findModule themselves and stash
                                   the result on the default arm; the
                                   initializer wrappers stop redoing
                                   the lookup. Impl arm runs
                                   resolveArgumentType which reuses
                                   the existing impl-list arity check
                                   from findRequiredImplsForUnion /
                                   findRequiredImplsForStruct.
    data.nim                       ResolvedStruct / ResolvedVariant /
                                   ResolvedUnion / ResolvedData +
                                   accumulateGenericPosition helper
                                   (assigns the next position to each
                                   new generic; repeats keep their
                                   first position — no uniqueness
                                   rejection, the analyzer's merge()
                                   catches actual conflicts at init)
                                   + position-preserving requires*
                                   derivation on Struct/Union + their
                                   resolveX procs (resolveVariant
                                   threads the union's mutable
                                   genericTypeIndex across variants
                                   so positions accumulate in
                                   declaration order)
    funcs.nim                      ResolvedUserFunction / ResolvedFunction
                                   + resolveUserFunction / resolveFunction
    modules.nim                    ResolvedModule / ResolvedGeneric +
                                   resolveModule / resolveGeneric
    definedTypes.nim               ResolvedDefinedType +
                                   resolveDefinedType
    files.nim                      ResolvedFile + resolveFile
    apps.nim                       ResolvedApp + the public `resolve*`
                                   entry

  analyzer/
    analyzer.nim                   re-exports every component file
    literals.nim                   AnalyzedLiteralBlock
    imports.nim                    AnalyzedImportedType /
                                   AnalyzedImportDefinition +
                                   analyzeImportedType,
                                   analyzeImportDefinition
    argtypes.nim                   ResolvedFileScope + argument-type
                                   cluster (Argument / Defined / Module /
                                   Generic) + dual-context (module ctx /
                                   generic ctx) analyze* overloads —
                                   both now take fileScope so the
                                   generic-context path can resolve
                                   imported types via the same
                                   findArgTypeModule / findArgTypeGeneric
                                   helpers (which try file-local lookup
                                   first, then fall back to fileScope) +
                                   GenericImplMap (Table[ResolvedGeneric,
                                   AnalyzedArgumentType]) with merge
                                   (conflict-on-different-binding) +
                                   concrete* overloads (implMap-keyed and
                                   positional impls + genericTypeIndex)
    funcdefs.nim                   AnalyzedArgumentDefinition /
                                   AnalyzedFunctionDefinition + dual-
                                   context analyze* overloads +
                                   concrete* (implMap-driven and
                                   index+impls-driven) so funcDef return
                                   types substitute through to inferred
                                   impls at the call site
    data.nim                       AnalyzedStruct (with fieldIndex +
                                   findField + genericTypeIndex) /
                                   AnalyzedVariant / AnalyzedUnion
                                   (with genericTypeIndex) /
                                   AnalyzedData + concrete* on each
                                   (positional impls drive field-type
                                   substitution via the stored index) +
                                   accumulateGenericPosition (mirror of
                                   the resolver-side accumulator) +
                                   their analyzeX procs (analyzeVariant
                                   threads the union's mutable
                                   genericTypeIndex)
    modules.nim                    AnalyzedModuleDefinition (+ funcDef
                                   indices and findFunctionDef[s]
                                   lookups) / AnalyzedGeneric (also has
                                   funcDef indices + findFunctionDefs;
                                   generic funcDefs need no public
                                   filter) / AnalyzedDefinedType
                                   (umbrella over module + generic;
                                   module/generic accessors assert kind
                                   first) + analyzeModuleDefinition /
                                   analyzeGeneric / analyzeDefinedType
    funcrefs.nim                   AnalyzedDefinedTypeScope
                                   (Identifier -> AnalyzedDefinedType,
                                   indexes both modules and generics)
                                   with findDefinedType (by name) /
                                   findModuleDef (by argType or by
                                   name) / extractDataBlock /
                                   extractStructFor / extractUnionFor
                                   lookup helpers / AnalyzedFunctionScope
                                   + clone. Function-call funcDef
                                   lookup is inlined into
                                   analyzeFunctionCall in body.nim
                                   (AnalyzedFunctionRef removed).
    patterns.nim                   generic parseInteger[T: SomeInteger]
                                   helper (parseutils + scanf with
                                   compile-time signed/unsigned
                                   dispatch + bounds check against
                                   T.high/low) / AnalyzedVariantPatternScope
                                   + update + hasUncoveredCases /
                                   AnalyzedLiteralPatternScope —
                                   tagged union over the eight integer
                                   kinds, exhaustiveness currently
                                   requires a variable case binding
                                   since whole-domain coverage is not
                                   yet computed (literal-pattern
                                   duplicate detection is implemented
                                   for u8 / i8 only — the other six
                                   integer kinds still return todo) /
                                   AnalyzedVariantPattern +
                                   analyzeVariantCasePattern /
                                   AnalyzedCasePattern (acpkVariant /
                                   acpkInteger / acpkVariable) +
                                   analyzeCasePattern (overloaded for
                                   union vs literal context)
    body.nim                       AnalyzedVariable + analyzeVariable
                                   / AnalyzedLiteralInitializer +
                                   analyzeLiteralInitializer (runs
                                   analyzeArgumentType, extracts the
                                   data block, validates via the
                                   shared analyzeLiteral helper) /
                                   AnalyzedGetter (struct-shaped
                                   module property lookup; carries
                                   `source` — the source variable's
                                   AnalyzedArgumentType — and
                                   `property` — the resolved field
                                   def. `argType*()` derives from
                                   `property.argType`, so a getter
                                   expression types as the property
                                   field, not as the source object) +
                                   analyzeGetter / body-level
                                   mutually-recursive type cluster
                                   (AnalyzedFunctionCall /
                                   AnalyzedKeywordArgument /
                                   AnalyzedStructRef + AnalyzedUnionRef
                                   (each tagged default / impl;
                                   default arm carries `module:
                                   AnalyzedModuleDefinition` looked up
                                   via defScope.findModuleDef — defScope
                                   spans local + imported types,
                                   populated by analyzeFile in
                                   appdefs.nim — and the wrapper
                                   initializer procs read it directly
                                   instead of redoing the lookup. Impl
                                   arm carries the analyzed
                                   ArgumentType used to seed
                                   substitution; impl-arm callers
                                   that still need the receiver moduleDef
                                   call defScope.findModuleDef with the
                                   parser-level name) /
                                   AnalyzedUnionInitializer (carries
                                   unionRef + the analyzer-built
                                   argType, which is fully bound on
                                   the impl arm and may carry free
                                   generics on the default arm) /
                                   AnalyzedStructInitializer /
                                   AnalyzedInitializer /
                                   AnalyzedCaseBlock /
                                   AnalyzedMatchExpression /
                                   AnalyzedAssignment /
                                   AnalyzedMutation /
                                   AnalyzedExpression /
                                   AnalyzedStatement) + analyze procs
                                   (analyzeValueTypeAgainstDefinitionType
                                   (overload set) / analyzeArgumentList
                                   (overloaded; the per-funcDef arity
                                   check + the overload-resolution
                                   helper share the name) +
                                   analyzeFunctionCall
                                   / analyzeCaseBlock (overloaded; union
                                   ctx + literal ctx; both extend
                                   caseScope with statement-level
                                   bindings) / verifyUniformReturnType
                                   helper / analyzeCases (overloaded;
                                   shared uniform-return check) /
                                   analyzeMatchExpression /
                                   analyzeKeywordArgument (pre-resolved
                                   field so struct + union initializers
                                   share it; partial literal-typed
                                   kwarg inference — i32 and string
                                   arms wired, other integer / float /
                                   pointer kinds return todo) /
                                   analyzeUnionInitializer (dispatches
                                   on AnalyzedUnionRef kind: aurkImpl
                                   substitutes the user-supplied impls
                                   into the variant's field types via
                                   concrete() and type-checks each
                                   kwarg; aurkDefault accumulates a
                                   GenericImplMap from kwarg value
                                   types against variant fields and
                                   builds the result argType with
                                   bound concretes at covered
                                   positions + free generics at
                                   uncovered ones — leave-as-is) /
                                   analyzeStructInitializer /
                                   analyzeInitializer /
                                   analyzeExpression /
                                   analyzeAssignment (extends
                                   funcScope with the new binding) /
                                   analyzeMutation / analyzeStatement)
                                   — variable case-pattern arm wired
                                   for literal-subject matches (binds
                                   the variable to the subject's
                                   argType); mutation statement wired
                                   (LHS getter + RHS expression —
                                   type equality not yet checked);
                                   literal initializer arm wired via
                                   AnalyzedLiteralInitializer +
                                   analyzeLiteralInitializer — runs
                                   analyzeArgumentType for the
                                   declared type, extracts the data
                                   block, errors if the receiver is
                                   struct/union (rejects "you wrote
                                   a literal where the type expects
                                   an initializer block"), validates
                                   the literal value against the
                                   ResolvedLiteralType via the same
                                   analyzeLiteral helper used by
                                   arg-list and kwarg paths;
                                   argument-list handles
                                   typed (non-literal) args fully and
                                   has uniform literal-arg validation
                                   wired against all integer kinds
                                   (U8/U16/U32/U64/I8/I16/I32/I64) +
                                   String via the analyzeLiteral
                                   helper at the top of body.nim,
                                   which dispatches on
                                   ResolvedLiteralType and calls
                                   analyzeIntegerLiteral[T] (generic
                                   over the target width/signedness)
                                   or analyzeStringLiteral. F32/F64/
                                   Pointer literal positions still
                                   return todo; struct/union-typed
                                   positions return a "needs
                                   initializer" diagnostic.
                                   analyzeKeywordArgument uses the
                                   same analyzeLiteral helper, so
                                   literal-typed field values are
                                   validated by the same code path.
                                   analyzeValueTypeAgainstDefinitionType
                                   takes an explicit `loc: Location`
                                   so type-mismatch errors point at
                                   the use site (the offending kwarg
                                   or call arg) rather than at
                                   wherever the value's argType
                                   carries its own loc.
                                   analyzeFunctionCall concretizes
                                   the matched funcDef's return type
                                   via the inferred GenericImplMap;
                                   the public-only filter on
                                   findFunctionDefs is now dispatched
                                   on receiver kind — modules apply
                                   the "external call needs public"
                                   rule, generics allow any funcDef
                                   (their funcDefs aren't required to
                                   be explicitly marked public).
                                   analyzeMatchExpression extracts the
                                   subject's impls and runs the union
                                   through concrete() so case-arm
                                   bindings see the substituted field
                                   types
    funcs.nim                      AnalyzedUserFunction + AnalyzedExternFunction
                                   / AnalyzedFunction tagged union /
                                   AnalyzedModule + analyzeUserFunction
                                   (enforces last-statement return-type
                                   match) + analyzeModule (returns
                                   AnalyzedModule with
                                   AnalyzedFunction[Extern|User]
                                   wrappers)
    filedefs.nim                   AnalyzedFileDefinition (with
                                   imports + definedTypes + modules) +
                                   analyzeFileDefinition
    appdefs.nim                    AnalyzedAppDefinition +
                                   AnalyzedFile (analyzed file
                                   def + its analyzed modules) +
                                   AnalyzedApp (app def + per-file
                                   analyzed views) + the public
                                   `analyze*` entry (returns
                                   `Result[AnalyzedApp, string]`)

examples/
  base.asl                         standard library definition (extern functions)
  *.asl                            positive test fixtures
  errors/*.asl                     negative test fixtures (each documented)

tests/
  config.nims                      adds src/{,tokenizer,parser,resolver}
                                   to the search path
  tutils.nim                       shared helpers (tokenize/parse/resolve
                                   over in-memory strings + temp dirs)
  all.nim                          aggregator that imports test_*.nim
  test_tokenizer.nim               tokenizer unit tests
  test_combinators.nim             Spec / combinator unit tests
  test_ast.nim                     AST constructor invariants (covers
                                   the per-concept files in src/parser/)
  test_grammar.nim                 single-file parse tests across all
                                   per-concept grammar specs
  test_loader.nim                  BFS / topo / parent-escape tests
  test_resolver.nim                end-to-end resolver tests

test.sh                            regression runner (exit-code based)
bugs.md                            issue tracker (open + resolved)
lessons.md                         design retrospective
overview.md                        this file
```

Cross-component imports use bare names (`import tokenizer`,
`import parser`). `nim.cfg` adds each component directory to the
Nim compiler's module search path. No `../` parent imports anywhere.

## Design Patterns

**Result[T, E] error handling** — all fallible operations return
`Result`. Chained with `?` for early return. Error messages carry
`file:line:col`. The `[ERROR] -` prefix is added only at the
display boundary (`asl.nim`), not in library code.

**Private fields + readonly accessors** — types are `ref object`
with unexported fields. Public accessor procs (`proc name*(m): T`)
provide readonly access. Variant-field accessors assert the kind
before returning (`assert db.kind == dbkStruct`).

**Tagged unions** — `Expression`, `Statement`, `DataBlock`,
`Initializer`, `CasePattern`, `Function`, `DefinedType`, `Type` all
use `case kind:` discriminators with exhaustive matching.

**Uniqueness via indexed construction** — the parser builds
`Table[Identifier, int]` lookup tables inside every constructor that
takes a list of named children (fields, variants, function args,
file-level types, ...). Duplicate insertion errors immediately, so
the same index that speeds up downstream lookups also enforces
uniqueness. No separate validation pass.

**Reverse construction** — compute children first into local vars,
then construct the parent once at the end via a `newX()` factory.
No mutation after construction.

**Identifier everywhere** — every name-bearing field in the AST
stores an `Identifier` (value + Location) rather than a bare
string, so error messages always have exact source positions.

## Testing

Two suites, both runnable from the repo root:

`nimble test` — unit suite under `tests/`. Each component (tokenizer,
combinators, AST constructors, grammar, loader, resolver, analyzer)
has its own `test_*.nim` file aggregated by `tests/all.nim`. 187 tests
covering positive paths, negative paths, edge cases, and Trojan Source
defenses in the tokenizer.

`./test.sh` — integration suite that drives the binary against
every `examples/*.asl` fixture and asserts exit codes:

- **Positive** (`examples/*.asl`): must exit 0
- **Negative** (`examples/errors/*.asl`): must exit non-zero

Each fixture has a leading `#` comment documenting what feature or
error condition it exercises. 35 fixtures total.

## What's Next

The **Analyzer phase is functionally complete** — `analyze*` walks
the `ResolvedApp` end-to-end and returns an `AnalyzedAppDefinition`
that holds a type-rich representation of every value, expression,
and statement in the program. Integration suite at **31/35**; unit
suite at **196/196**.

What the analyzer does today (all wired):

- Overload selection at function-call sites — each candidate funcDef
  is unified against the call's argument types via `GenericImplMap`
  + `merge`, and uniqueness picks the survivor (ambiguity rejected).
- Generic constraint satisfaction — once unification binds a type
  parameter, the bound type is checked against every function
  signature the generic requires.
- Concretization — the matched funcDef's return type and the
  match-subject's union are rewritten through `concrete()` with the
  inferred impls so downstream sites see substituted types.
- Union initializer parametric inference — `UnionRef` (mirror of
  `StructRef`) carries default vs impl; the impl arm substitutes
  user-supplied impls into variant fields via `concrete()` before
  type-check, the default arm walks kwargs accumulating a
  `GenericImplMap` and emits a result type with bound concretes
  where the variant touched the generic and free generics where it
  didn't (leave-as-is).
- Literal type inference — the `analyzeLiteral` helper dispatches on
  `ResolvedLiteralType` and validates every integer kind
  (U8/U16/U32/U64/I8/I16/I32/I64) plus String against the expected
  target. `analyzeArgumentList`, `analyzeKeywordArgument`, and
  `analyzeLiteralInitializer` all route through it.
- Case-pattern duplicate detection — `checkDuplicate[T: SomeInteger]`
  handles all eight integer kinds uniformly.
- Body-level constructs — getter (struct-shaped property read),
  variable case patterns, mutations, assignments, match expressions
  with case-arm bindings, struct + union initializers (default and
  impl), literal initializers.

Focused TODOs still open:

- **Equality vs unification for analyzed types** (`analyzer/argtypes.nim:194`).
  `AnalyzedArgumentType.==` is hash equality; assignability against
  an expected type that carries free generics (post leave-as-is)
  needs unification. Surfaces as the case-arm uniformity check
  failing on a handful of fixtures that flow free-generic values
  through `verifyUniformReturnType`. Fix is to route every
  assignability check through `analyzeValueTypeAgainstDefinitionType`
  + `merge`, with eager chain-collapsing in `merge`.
- **Substitution chains in `concrete()`** — `Sample → K, K → u8`
  should collapse to `Sample → u8`; today `concrete()` does a
  single `getOrDefault`. Pairs with the equality fix above.
- **F32 / F64 / Pointer literal kinds** — `analyzeLiteral` returns
  a todo for these three.
- **Impl-map update from literal positions** — when a literal arg
  flows into a generic position (e.g., `f(K=…)` with literal
  inferable type), the resulting binding isn't yet recorded.
- **`findRequiredImplsForFields` nested-impl walk**
  (`resolver/argtypes.nim:117`) — needs to walk into impls so a
  field typed `Box[u8, Sample]` contributes `Sample` to the parent's
  requires.
- **Type-correctness checks across statements** — assignment
  compatibility, match exhaustiveness, mutation type equality.

After the analyzer:
- **IR generation** — lower the analyzed AST into an intermediate
  representation suitable for optimization and code generation.
- **Code generation** — emit target code (likely C or LLVM IR).
