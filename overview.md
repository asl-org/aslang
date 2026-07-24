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
- **Pattern matching**: `match` expressions with three `CaseDef`
  shapes — literal (`case 0`), variable binding (`case other`),
  and variant destructuring (`case Pro { credits: c }: ...`)
- **Imports**: cross-file module/generic imports with aliasing
  (`import { User as U } from "./user.asl"`)
- **Visibility**: `public` keyword on modules and functions to
  mark them as exported
- **Comments**: line comments starting with `#`

### Built-in Types

Fixed-width integers: `i8`, `i16`, `i32`, `i64`, `u8`, `u16`,
`u32`, `u64`. Floats: `f32`, `f64`. Text: `String`. Containers:
`Array`, `Bitset`. Fallibility: `Status[T]` + `Error`. System
interface: `System`.

## Domain grammar (source of truth)

The compiler's domain vocabulary — the type names and shapes that
parser / resolver / analyzer values conform to — is captured in
[`grammar.md`](grammar.md). Every layer's type module traces back
to it. When a domain concept is renamed, added, or restructured, it
lands there first; the code catches up. The DDD-refactor roadmap
(`tasks.md`) enumerates which renames/reshapings have been applied
so far — headline landings are `StructDef`/`UnionDef`/`LiteralDef`
data-block variant names, `Setter` moved to `Statement`,
`VariablePattern` as a first-class `CaseDef`, the flat
`ResolvedArgumentType: ResolvedModuleArgumentType |
ResolvedGenericArgumentType` split, retirement of the 12 def-level
analyzer wrappers, and collapse of the `StructRef`/`UnionRef`
default/impl arms into a single shape with an `impls` seq.

The user-facing surface language reference is
[`documentation.md`](documentation.md).

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
Resolver ──── Walks the parsed App and produces a ResolvedApp:
  │              name/shape resolution for every ArgumentType,
  │              body-level name resolution for user-function
  │              bodies, arity + generic-constraint checks on
  │              every impl list. Resolved* def-level types carry
  │              the accessors + indices the analyzer needs
  │              (findField, findVariant, findFunctionDefs,
  │              genericTypeIndex, ...). Single-pass: resolved
  │              argument types + struct/union refs hold the parser
  │              `Module` identifier (not a ResolvedModule back-ref),
  │              so no ref-object cycle forms. Downstream layers
  │              that need the resolved module do the lookup at
  │              their site via `ResolvedFile.findModule(name)`.
  ▼
Analyzer ──── Walks bodies. Consumes the enriched Resolved* types
  │              directly via accessors — there are no def-level
  │              analyzer wrappers. Produces an AnalyzedApp
  │              carrying a type-rich view of every value,
  │              expression, and statement in each function body.
  │              Overload selection at function-call sites is
  │              wired (each candidate funcDef is unified against
  │              the call's argument types via GenericImplMap +
  │              merge; uniqueness picks the survivor); funcDef
  │              return types and match-subject unions are
  │              concretized via the inferred impls. Union
  │              initializer parametric inference reads the
  │              flattened StructRef / UnionRef `analyzedImpls`
  │              seq — empty seq → accumulate from kwargs +
  │              leave-as-is uncovered positions; non-empty seq
  │              → substitute user-supplied impls into variant
  │              fields. Literal initializers, case patterns over
  │              all integer kinds + String, and per-arg-list
  │              literal validation share one analyzeLiteral
  │              helper. The equality-vs-unification gap
  │              (case-arm uniformity) and a handful of focused
  │              TODOs remain — see the "What's Next" section.
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

`analyze*` returns a structured `AnalyzedApp` — the `ResolvedApp`
back-reference plus a `seq[AnalyzedFile]`, where each `AnalyzedFile`
carries its `ResolvedFile` back-reference, analyzed import definitions,
and the analyzed modules parsed out of it. There is no separate
`AnalyzedAppDefinition` / `AnalyzedFileDefinition` layer today — after
task 6c retired the 12 def-level wrappers, the analyzer's def-level
view is just the enriched Resolved* types themselves. `AnalyzedApp` is
the handle downstream codegen will thread through.

There is no separate `Validator` phase. Every uniqueness / structural
rule the validator used to enforce (duplicate names, empty blocks,
import collisions, duplicate fields/variants) is now a precondition
inside an AST constructor (`newStruct`, `newUnion`, `newModule`,
`newFile`, etc.). Invalid AST nodes cannot be constructed, so no
separate validation pass is needed.

### Phase 1: Tokenization

`src/analyzer/resolver/parser/tokenizer.nim` (barrel) + `src/analyzer/resolver/parser/tokenizer/`

Single-character classifier. Intentionally simple — no keywords, no
multi-character tokens. All that complexity lives in the parser.
Produces `seq[Token]` where each token carries `kind` (punctuation,
space, newline, alphabet, digit, utf8), `value` (the character), and
`Location` (filepath:line:col).

Security: validates UTF-8 encoding and rejects bidirectional control
codepoints, zero-width characters, and invisible Unicode (Trojan
Source defense).

### Phase 2: Parsing

`src/analyzer/resolver/parser.nim` (barrel — hosts the combinator layer
plus shared leaf specs and the multi-file `parse*` entry point) +
`src/analyzer/resolver/parser/` (per-concept AST modules — see the
Project Structure table for the current listing) +
`src/analyzer/resolver/parser/tokenizer.nim` +
`src/analyzer/resolver/parser/tokenizer/` (nested tokenizer barrel +
subfolder).

The parser is a private sub-tree of the resolver: analyzer, cli, and
asl.nim consume the parser through the resolver's `import resolver`
barrel, which re-exports the parser AST + `parse*` entry point.
Parser combinators (`Spec[T]`, `oneOf` / `pair` / `prefixed` / …) live
directly on `parser.nim`; they're imported by every per-concept file
but stay parser-internal — the resolver barrel doesn't re-export
them, and no code outside `parser/` needs them.

Recursive descent via composable `Spec[T]` combinators. Two families:

**Primitives** — the historical layer:
- `oneOf` — ordered alternatives with backtracking
- `any` / `atLeastOne` — repetition (zero-or-more / one-or-more)
- `optional` — zero-or-one, returns `Option[T]`
- `separatedBy` — comma-separated lists
- `contained` — delimited containers (`(...)`, `[...]`, `{...}`)
- `map` — transform parse result

**Sequence-composition atoms** — landed via Tasks 14–15 to eliminate
the `let X = Spec[T](parseFn: ...)` scaffolding on ~20 hand-written
specs:
- `prefixed(prefix, inner)` — parse `prefix inner`, discard prefix
- `suffixed(inner, suffix)` — parse `inner suffix`, discard suffix
- `pair(a, b)` — sequence into `(A, B)` tuple; `.map` to lift
- `triple(a, b, c)` — three-spec sequence into `(A, B, C)`
- `separated(a, sep, b)` — `pair(a, prefixed(sep, b))` — the
  grammar-natural "X separator Y" shape (8 sites)
- `presence(spec) → Spec[bool]` — rollback-safe test, distinct from
  `optional`
- `indentedLine(inner)` — `prefixed(indent, suffixed(inner, eol))`;
  the block-body item shape (4 sites)
- `ws0` / `ws1` / `blankLines` — named trivia specs; drop-in
  replacements for `any(spaceSpec)` etc.
- `blockSpec` / `decoratedBlockSpec` — indented blocks with headers

Backtracking via checkpoint/restore on `parser.index`. Fatal errors
in block bodies bypass backtracking for precise diagnostics.
Forward-declared specs enable mutual recursion
(`expressionSpec ↔ argumentListSpec`).

**Multi-file resolution** (`parser.nim`'s `parse*(rootPath, …)`
entry): BFS traversal of imports,
tokenize + parse each dependency, topological sort via DFS with
cycle detection. Parent-directory escape prevention
(`./sub/../../escape` caught by normalizing the resolved path). Both
graph algorithms live in `src/utils.nim` — `bfs[T, V]` is generic;
`topoSort` is currently string-typed.

**Post-parse A-normal form expansion** (`statement.nim`, `expand(...)`
procs): every `StatementList` runs through a normalization pass
immediately after parsing (`statementListSpec.parseFn` invokes
`.expand()` on its result). The pass rewrites the AST so that:

- **Every value-position expression is a `Variable` or `Literal`**.
  Function-call arguments, keyword-argument values, and match
  subjects that would otherwise be nested `FunctionCall` /
  `Initializer` / `Getter` / `MatchExpression` values get lifted
  into preceding synthetic assignments `__asl_arg_N = <expr>`, and
  the original position is replaced with `Variable(__asl_arg_N)`.
- **Every top-level statement is an `Assignment` or `Setter`** —
  never a bare-expression. A bare `foo(x)` statement becomes
  `__asl_arg_N = foo(x)`. The tail statement of a function body
  carries the return value via the assignment's RHS type (see the
  analyzer's `analyzedStatements[^1].argType` check).
- **Sub-expressions inside nested scopes recurse.** Case block
  bodies are their own `StatementList`, so they get their own
  expansion.

Lift rules by expression kind:
- `ekLiteral`, `ekVariable` — never lifted. Literals must reach
  `analyzeBareLiteral` with their expected context intact for
  Approach C's concrete-adopt behavior; variables are already
  named bindings.
- `ekGetter` — lifted at value positions (`p.a` in `foo(p.a)`
  becomes `t = p.a; foo(t)`), passed through at assignment /
  setter RHS positions (`x = p.a` stays `x = p.a`).
- `ekFnCall`, `ekInitializer`, `ekMatch` — always recurse into
  their sub-expressions; the outer expression is lifted at value
  positions, passed through at RHS positions.

Synthetic identifiers use the `__asl_arg_N` prefix, which
`newIdentifier` reserves (rejects for user code). Compiler-internal
construction goes through `newGeneratedIdentifier` in
`identifiers.nim`, which bypasses the prefix check. A per-function
counter provides uniqueness within the function scope.

Downstream (resolver, analyzer) sees only the ANF-normalized AST —
they never need to reason about nested value-position expressions,
which simplifies type-flow analysis considerably.

### Phase 3: Parser-level indexing (absorbed)

The parser itself performs the uniqueness / structural checks that
used to live in a separate validator. The lookup indices it builds
during construction double as the validation mechanism (`Table`
insertion fails on duplicate key).

Indices on AST nodes:
- `File.typeIndex` — `Identifier -> int` into `File.types` (locally-
  defined `Type` = module or generic).
- `File.importedNameIndex` — `Identifier -> ImportedType` covering
  every explicit-import binding on `fkAsl` files. Duplicate detection
  at parse time checks both indexes so an imported name and a local
  definition sharing an identifier collide immediately.
- `Module.functionIndex` / `Generic.funcDefIndex` — allow function
  overloading by keying on `seq[int]`.
- `StructDef.fieldIndex`, `UnionDef.variantIndex`, `VariantDef.fieldIndex`,
  `ArgumentDefList.argDefIndex` — per-block duplicate detection.
- `App.fileIndex` — absolute path → file index.

The parser exposes two focused lookups instead of a union:
`findType(name): Type` (local defs only) and
`findImportedName(name): ImportedType`. The historical `Type` umbrella
(`tkImported | tkDefined`) was retired — every downstream caller
already unwrapped it, so the union was ceremony that leaked through
the public API.

### Phase 4: Resolution

`src/analyzer/resolver.nim` (facade — hosts the per-type `resolve*`
procs and cross-cluster scope lookups) + `src/analyzer/resolver/`
(per-type files; see the Project Structure table for the current
listing) + the nested `src/analyzer/resolver/parser/` subtree
(Phase 2).

Returns a `ResolvedApp` containing a `ResolvedFile` per source file,
which in turn holds resolved imports plus a `ResolvedType` for each
module/generic. Body-level name resolution is complete (variables,
getters, function calls, initializers, match/case patterns). The
resolver also enforces the structural `struct(...)`-header
constraints (unique generics in the header — enforced by
`validateRequiresNameConflict` inside `newStructDefHeader`; struct can't
carry generic fields when the header is present — enforced in
`resolveStructDef` around line 409), runs the arity +
generic-constraint checks on every impl list (task 7 moved these here
from the analyzer), and stores the parser Module identifier on
`ResolvedStructRef` / `ResolvedUnionRef` (single-shape after task 8 —
`impls: seq[ResolvedArgumentType]`, empty for the bare surface form,
populated for the bracketed form). Scope:

- **File layout — one file per resolved type, actor procs on the
  facade.** The per-type files hold only the type declaration, its
  constructor, and its accessors. Every cross-type `resolve*` proc
  (plus the scope-lookup helpers that need to cross cluster
  boundaries) lives on the facade `src/analyzer/resolver.nim`; per-type
  files never import each other transitively via the resolve chain.
  See the Project Structure table for the current file listing —
  `argdef` / `argtype` / `moduleargtype` / `genericargtype` /
  `filescope` / `functionscope` (argument-type cluster), `funcdef` /
  `externfunc` (function-def cluster), `structdef` / `variantdef` /
  `uniondef` / `datadef` (data-block cluster), `getter` /
  `literalinit` / `structref` / `unionref` / `statement` / `funcs`
  (body cluster), `module` / `generic` / `types` (top-level cluster),
  `imports` / `files` / `apps` (file / import / app layer).

  The facade `src/analyzer/resolver.nim` re-exports every per-type
  file plus the nested parser layer (`src/analyzer/resolver/parser.nim`)
  so consumers say `import resolver` once. The facade also owns the
  cross-cluster helpers (`findType`, `findModule`, `findGeneric`,
  `findRequiredImpls*`, `checkImplSatisfiesGeneric`,
  `validateRequiresConstraints`) and every `resolve*` proc from
  `resolveArgumentType` through `resolveApp`.
- **Single-pass walk per app** (files come topo-sorted leaves-first
  from the parser's multi-file `parse*` entry, so imports are always
  resolved before use). For
  each file: build the `FileScope` (locally-defined names +
  imported bindings). Then for each defined type resolve requires
  (if any), the data block, and each function signature/body.
  Argument types along the way carry parser Module identifiers, so
  every `ResolvedModuleArgumentType` is well-formed at construction
  without any forward-reference dance. The historical shell /
  populate two-pass has been retired.
- **Impl-list validation** — `resolveModuleArgumentType` calls
  `checkImplSatisfiesGeneric` on every impl inference path (explicit
  `struct(...)` header, inferred struct fields, inferred union
  fields). The check verifies `(name, arity)` at the parser level;
  downstream `analyzeValueTypeAgainstDefinitionType` catches
  signature-parity mismatches at use sites.
- **Generic param-list accumulation** — `accumulateGenericPosition`
  walks each field and assigns the next position to any generic
  seen for the first time; repeated occurrences keep the position
  they already have. The result lives as `genericTypeIndex:
  Table[ResolvedGenericArgumentType, int]` on `ResolvedStructDef` /
  `ResolvedUnionDef` and drives the position-preserving `requires*`
  accessor plus the analyzer's substitution walk. No uniqueness
  rule is enforced at resolution time — the same generic name
  appearing in multiple fields is fine, since the analyzer's
  `GenericImplMap` binds one generic to one concrete type per
  construction and surfaces any mismatch as a `merge()` error at
  the init site. Generic-uniqueness inside the explicit
  `struct(...)` header is the one place that *is* checked.
- **Generic signature rule** — inside a generic block, a fn
  argument/return type root may only resolve to the current generic
  itself (self-reference) or a module. Other generics are rejected
  at resolve time, keeping each generic's type world bounded.
- **Enriched Resolved* def-level types** — `ResolvedStructDef` /
  `ResolvedVariant` / `ResolvedUnionDef` / `ResolvedModule` /
  `ResolvedGeneric` carry every accessor the analyzer's retired
  phase-A wrappers used to add: `findField`, `findVariant`,
  `findFunctionDefs(name, arity, public)`, `funcNameArityIndex`,
  `funcDefIndex`. The analyzer reads these directly rather than
  rebuilding a parallel def-level view.
- **Body-level name resolution** — the resolver walks user-function
  bodies: each statement is dispatched, each expression is resolved,
  and every function call is matched against candidate function
  definitions by `(name, arity)` against the target type. A
  `FunctionScope` (Table[Identifier, Location]) tracks the names of
  variables currently in scope; the value stores the declaration site
  so duplicate-declaration errors can point at the prior source
  location. Variable types remain the Analyzer's concern. The
  resolver collects candidate overloads but does not pick the unique
  one — that's the Analyzer.
- **Not the resolver's job**: overload selection (picking the unique
  candidate after matching concrete arg types) and body-level
  type-correctness checks. Those belong to the Analyzer phase.
- **No structural-size check** — all struct values are pointer-backed
  at runtime, so mutual struct containment does not create infinite
  types. Name cycles are the only cycles, and holding parser
  identifiers (not resolved back-refs) inside the argument-type
  cluster dissolves them.
- **`ResolvedGenericArgumentType.generic` is a parser `Generic`.**
  Same rule as `ResolvedModuleArgumentType.module: Module` — no
  resolved back-refs inside the argument-type cluster. Downstream
  layers do the resolved-side lookup at their site.

### Phase 5: Analysis

`src/analyzer/{argtypes, body, funcrefs, funcs, imports, patterns,
appdefs, analyzer}.nim` — 8 files, ~1900 lines.

Takes a `ResolvedApp` and returns an `AnalyzedApp` — a type-rich view
of every value, expression, and statement in each function body. The
analyzer walks **bodies only**; def-level metadata (fields, variants,
funcDef indices, generic type indices, constraint checks) is read
directly off the enriched `Resolved*` types via their accessors. Body-
level analyzed types mirror their resolver counterparts via
`resolved: Resolved*` back-references. Scope:

- **Overload selection** — at each function-call site, every
  candidate funcDef is unified against the call's argument types
  via `GenericImplMap` + `merge`. The unique survivor is picked;
  ambiguity is rejected.
- **Concretization** — funcDef return types and match-subject
  unions are rewritten through `concrete()` using the inferred
  impls so downstream sites see substituted types. `concrete()`
  has a resolver-keyed overload
  `(argType, impls, genericTypeIndex: Table[ResolvedGenericArgumentType, int])`
  since the union/struct genericTypeIndex is read directly off the
  resolver's data types.
- **Union-initializer parametric inference** — reads
  `AnalyzedUnionRef.analyzedImpls` (single-shape after task 8).
  Empty seq: the initializer walks kwargs accumulating a
  `GenericImplMap` against variant fields and builds the result
  argType with bound concretes at covered positions + free
  generics at uncovered positions (leave-as-is). Non-empty seq:
  the user-supplied impls are substituted into variant fields via
  `concrete()` before per-kwarg type-check. The `GenericImplMap`
  seed loop runs unconditionally — bounded `if position <
  analyzedImpls.len` gates each per-position seed, so an empty
  seq is a no-op.
- **Literal type inference + validation** — the `analyzeLiteral`
  helper at the top of `analyzer/body.nim` dispatches on
  `ResolvedLiteralType` and validates the literal text against all
  integer kinds plus String. `analyzeArgumentList`,
  `analyzeKeywordArgument`, and `analyzeLiteralInitializer` all
  route through it.
- **Bare-literal contextual defaulting** — bare literals (`x = 10`,
  `f(1)`, `Struct { field: "data" }`) parse as `ekLiteral`
  expressions and reach the analyzer typeless. `analyzeExpression`
  takes an `expected: Option[AnalyzedArgumentType]` from every
  caller; the `rekLiteral` arm dispatches through `analyzeBareLiteral`,
  which picks a concrete type by rule: `some(module w/ literal data
  def)` → adopt (concrete adapt); `some(generic)` or `none` →
  default to `i32` / `f32` / `String`. The value is then fit-checked
  and wrapped as an `AnalyzedLiteralInitializer` under `aekInitializer`,
  so no downstream site sees an untyped bare literal. Defaults must
  be in scope — `@std` auto-injection handles this for every `.asl`
  file. Concrete positions thread `expected` from the callee's
  declared arg types (per-candidate for overloads), the struct/
  union kwarg's field type (post-implMap concretization for unions),
  and the setter RHS's getter type.
- **Case-pattern duplicate detection** — `checkDuplicate[T: SomeInteger]`
  handles all eight integer kinds in `analyzer/patterns.nim`.
- **Body-level constructs** — getter (struct-shaped property read),
  variable case patterns (`VariablePattern` is a first-class
  `CaseDef` variant alongside `LiteralPattern` and `UnionPattern`),
  setters, assignments, match expressions with case-arm bindings,
  struct + union initializers, literal initializers.
- **Pattern-side bindings** — `AnalyzedUnionPattern.fields` is now
  a seq of `AnalyzedBinding = tuple[name: Identifier, argType:
  AnalyzedArgumentType]` — the body-level replacement for the
  retired def-level `AnalyzedArgumentDefinition` wrapper.
- **Scope table** — `ResolvedFileScope` (was
  `AnalyzedDefinedTypeScope` pre-6c) is the analyzer's single
  fileScope table, populated by `analyzeFile` in `appdefs.nim`
  and threaded through every body walker for name lookups.

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
  utils.nim                        generic bfs[T, V] + topoSort with
                                   cycle detection
  nim.cfg                          per-component module search paths
  analyzer/resolver.nim            resolver facade — the public entry
                                   for the resolver layer. Re-exports
                                   every per-type file PLUS the nested
                                   parser (its AST types, `parse*`
                                   entry point, and Location). Also
                                   owns every cross-cluster `resolve*`
                                   proc and the cross-cluster scope
                                   lookups (`findType`, `findModule`,
                                   `findGeneric`, `findRequiredImpls*`,
                                   `checkImplSatisfiesGeneric`,
                                   `validateRequiresConstraints`).
                                   `import resolver` gives consumers
                                   everything they need to build,
                                   traverse, or diagnose ASL programs.

  analyzer/resolver/               resolver internals — one file per
                                   resolved type. Each file holds the
                                   type declaration, constructor, and
                                   accessors only; the cross-type
                                   `resolve*` procs live on the facade.
    literaldef.nim                 ResolvedLiteralDef + newResolvedLiteralDef
    patterns.nim                   ResolvedCasePattern + resolveCasePattern
    imports.nim                    ResolvedImportedType / ResolvedImport
    filescope.nim                  FileScope (Identifier ->
                                   ResolvedType) — populated by
                                   resolveFile from imports + local
                                   defs; keyed by binding so aliased
                                   imports resolve correctly.
    functionscope.nim              FunctionScope
                                   (Table[Identifier, Location]) —
                                   names of variables currently in
                                   scope, keyed by identifier with
                                   the declaration Location as value
                                   for duplicate-declaration error
                                   pointers. Types are the analyzer's
                                   concern. Constructor
                                   newFunctionScope seeds from a
                                   resolved function's args;
                                   `update` extends with a
                                   statement's introduced variable
                                   or a case pattern's bindings.
    argtype.nim                    ResolvedArgumentType (flat tagged
                                   union over ratkModule / ratkGeneric).
    moduleargtype.nim              ResolvedModuleArgumentType — carries
                                   the *parser* Module plus the impls
                                   seq (empty for bare use, populated
                                   for the bracketed form). Never a
                                   resolved back-ref, so no ref-object
                                   cycle forms in the argument-type
                                   cluster.
    genericargtype.nim             ResolvedGenericArgumentType — carries
                                   the *parser* Generic. Same
                                   no-back-ref rule as
                                   moduleargtype.
    argdef.nim                     ResolvedArgumentDef (arg name + its
                                   resolved argument type).
    funcdef.nim                    ResolvedFunctionDef — args + return
                                   type + a back-ref to the parser
                                   FunctionDef.
    externfunc.nim                 ResolvedExternFunction — extern
                                   symbol + its ResolvedFunctionDef.
    structdef.nim                  ResolvedStructDef (fieldIndex +
                                   findField + genericTypeIndex +
                                   requires accessor).
    variantdef.nim                 ResolvedVariant (fieldIndex +
                                   findField).
    uniondef.nim                   ResolvedUnionDef (variantIndex +
                                   findVariant + genericTypeIndex +
                                   requires accessor).
    datadef.nim                    ResolvedData (ddkLiteral / ddkStruct
                                   / ddkUnion) + accumulateGenericPosition
                                   helper for the shared generic-position
                                   table.
    getter.nim                     ResolvedGetter.
    literalinit.nim                ResolvedLiteralInitializer.
    structref.nim                  ResolvedStructRef — parser
                                   StructRef back-ref + resolved
                                   receiver Module + impls seq (empty
                                   for the bare surface form,
                                   populated for the bracketed form).
    unionref.nim                   ResolvedUnionRef — parser UnionRef
                                   back-ref + resolved receiver Module
                                   + impls seq (same shape as
                                   structref).
    statement.nim                  Body-cluster mutually-recursive
                                   types: ResolvedKeywordArgument /
                                   ResolvedStructInitializer /
                                   ResolvedUnionInitializer /
                                   ResolvedFunctionCall /
                                   ResolvedInitializer /
                                   ResolvedExpression / ResolvedMatch /
                                   ResolvedCaseBlock /
                                   ResolvedAssignment / ResolvedSetter /
                                   ResolvedStatement. Type-only file —
                                   the corresponding resolve* procs
                                   live on the facade.
    function.nim                   ResolvedUserFunction + tagged
                                   ResolvedFunction (fkUser / fkExtern)
                                   + its accessors.
    module.nim                     ResolvedModule (funcDefIndex +
                                   funcNameArityIndex +
                                   findFunctionDefs(name, arity,
                                   public)).
    generic.nim                    ResolvedGeneric (same funcDef
                                   accessors as ResolvedModule).
    types.nim                      Tagged ResolvedType (rdtkModule /
                                   rdtkGeneric) — one-of over module
                                   and generic.
    files.nim                      ResolvedFile + typeIndex +
                                   findType / findModule /
                                   findGeneric (per-file lookups over
                                   locally-defined resolved types).
    app.nim                        ResolvedApp — the top-level handle;
                                   the actor `resolve*` proc lives on
                                   the facade.

    parser.nim                     parser layer — combinator machinery
                                   (Spec[T], Parser, oneOf / any /
                                   atLeastOne / optional / separatedBy
                                   / contained / map / prefixed /
                                   suffixed / pair / triple / separated
                                   / presence / indentedLine / ws0 /
                                   ws1 / blankLines / block helpers) +
                                   shared leaf specs (string / integer
                                   / float literals, argumentType /
                                   argumentDef, casePattern /
                                   unionPattern, initializer / getter /
                                   kwarg / expression / statement
                                   forward-decls, import-line /
                                   import-path helpers, function /
                                   struct / union / generic / module
                                   headers and bodies, file specs) +
                                   the public multi-file `parse*`
                                   entry (BFS + topoSort). Re-exports
                                   every per-type file below plus
                                   Location. Combinators + Spec are
                                   parser-internal — no consumer
                                   outside `parser/` imports them.

    parser/                        parser internals — one file per
                                   parser concept (private to the
                                   parser barrel; nested inside the
                                   resolver folder because the parser
                                   is always a resolver dependency).
                                   Each file holds one AST type's
                                   declaration, constructor, and
                                   accessors; the corresponding
                                   grammar spec lives on parser.nim.
      identifiers.nim              Identifier / Space (indentation
                                   marker).
      literals.nim                 Literal (lkString / lkInteger /
                                   lkFloat) + StringLiteral /
                                   IntegerLiteral (union over Signed /
                                   Unsigned) / FloatLiteral +
                                   LiteralDef + StringContent.
      imports.nim                  ImportedType / Import (ikExplicit /
                                   ikShorthand) / ImportPath
                                   (ipkRelative / ipkVendor) /
                                   VendorRoots + toImportPath +
                                   toAbsPath (relative resolution
                                   with parent-escape check + vendor
                                   dispatch).
      argtype.nim                  ArgumentType (root Identifier +
                                   impls: seq[ArgumentType], with the
                                   trailing-bang Status[] sugar
                                   collapsed at parse time).
      argdef.nim                   ArgumentDef / ArgumentDefList
                                   (identifier ":" argumentType).
      structref.nim                StructRef — module Identifier +
                                   impls: seq[ArgumentType] (empty =
                                   bare surface form; populated =
                                   explicit-impls).
      unionref.nim                 UnionRef — same shape as StructRef,
                                   used by unionInitializerSpec to
                                   carry the impls seq through to the
                                   Initializer.
      structdef.nim                StructDef (requires: seq[Identifier]
                                   from the `struct(...)` header —
                                   phantom-type parameters when
                                   present; fields + fieldIndex +
                                   findField / findFieldId). Parsed
                                   inline by `parseStructHeader` /
                                   `parseStructRequires` in
                                   `parser.nim`.
      variantdef.nim               VariantDef (name + fields +
                                   fieldIndex + findField /
                                   findFieldId). Zero-field variants
                                   must be written `Timeout { }` on
                                   the surface — bare `Timeout` is
                                   rejected to keep the case-pattern
                                   side visually consistent.
      uniondef.nim                 UnionDef (variants + variantIndex
                                   + findVariant).
      datadef.nim                  DataDef (ddkLiteral / ddkStruct /
                                   ddkUnion) — the one-of wrapper
                                   around a module's data block.
      funcdef.nim                  FunctionDef (public flag + name +
                                   arg list + return type).
      externfunc.nim               ExternFunction (`@extern("symbol")`
                                   + FunctionDef, no body).
      userfunc.nim                 UserFunction (decorators + def +
                                   StatementList).
      function.nim                 Function (fkUser / fkExtern) +
                                   FunctionList + per-kind accessors
                                   dispatching on the tag.
      getter.nim                   Getter — struct field access
                                   (`source.property`).
      literalinit.nim              LiteralInitializer — typed literal
                                   in initializer position
                                   (`u8 42`).
      patterns.nim                 UnionPatternField / UnionPattern /
                                   CasePattern (cpkInteger /
                                   cpkVariable / cpkUnion) + binding
                                   accessors.
      statement.nim                Body-cluster mutually-recursive
                                   AST types + the post-parse ANF
                                   expander (`expand(...)` procs run
                                   during statementListSpec): every
                                   value-position expression becomes a
                                   Variable or Literal; every
                                   top-level statement becomes an
                                   Assignment or Setter. Types:
                                   Expression / MatchExpression /
                                   CaseBlock / FunctionCall /
                                   ArgumentList / KeywordArgument /
                                   KeywordArgumentList /
                                   StructInitializer /
                                   UnionInitializer / Initializer /
                                   Statement / StatementList /
                                   Assignment / Setter.
      generics.nim                 Generic (funcDefs + funcDefIndex +
                                   findFunctionDefs).
      modules.nim                  Module (data? + functions +
                                   funcNameArityIndex +
                                   findFunctionDefs). Generic
                                   parameters live inside the data
                                   block (`struct(...)` header or
                                   inferred variant fields), not on
                                   the Module itself.
      types.nim                    Type (tkModule / tkGeneric) —
                                   one-of over module and generic
                                   entries in a File's types list.
      files.nim                    File (fkAsl / fkAslr) + typeIndex
                                   + importedNameIndex + findType
                                   (locally-defined) /
                                   findImportedType / findExportedType
                                   / publicTypes / importPaths.
      app.nim                      App — top-level handle over the
                                   topo-sorted seq[File] + file index.
      decorator.nim                Decorator (`@name` on module /
                                   function).
      error.nim                    ParserError (msg + loc + fatal
                                   flag) + newParserError + max
                                   ordering (deepest error wins).
      utils.nim                    Small parser-helper procs shared
                                   across specs.
      tokenizer.nim                tokenizer barrel — re-exports
                                   Token / TokenKind / Location /
                                   tokenize.
      tokenizer/
        constants.nim              BidiCodepoints / ZeroWidthCodepoints
                                   / InvisibleCodepoints arrays +
                                   AsciiMaxValue / Punctuations /
                                   Space / Newline constants.
        location.nim               Location type + accessors
                                   (newLocation, advance, $, hash,
                                   ==, <); re-exported through
                                   parser.nim (every AST node carries
                                   one).
        token.nim                  Token type + accessors.
        spec.nim                   Data-driven per-kind TokenSpec
                                   array + the tokenize loop's
                                   dispatcher.

  analyzer/                        8 files, ~1900 lines. No def-level
                                   wrappers — the 12 that used to live
                                   here (AnalyzedStructDef,
                                   AnalyzedUnionDef, AnalyzedVariant,
                                   AnalyzedLiteralDef, AnalyzedData,
                                   AnalyzedModuleDefinition,
                                   AnalyzedGeneric,
                                   AnalyzedDefinedType,
                                   AnalyzedFileDefinition,
                                   AnalyzedAppDefinition,
                                   AnalyzedFunctionDefinition,
                                   AnalyzedArgumentDefinition) were
                                   retired in task 6c; the analyzer
                                   reads the enriched Resolved* types
                                   directly.
    analyzer.nim                   re-exports every component file
    imports.nim                    AnalyzedImportedType /
                                   AnalyzedImportDefinition +
                                   analyzeImportedType /
                                   analyzeImportDefinition
    argtypes.nim                   AnalyzedGenericArgumentType /
                                   AnalyzedModuleArgumentType /
                                   AnalyzedArgumentType (flat tagged
                                   union mirroring the resolver's
                                   shape after task 5) + dual-context
                                   (module ctx / generic ctx)
                                   analyze* overloads — both take
                                   fileScope so the generic-context
                                   path can resolve imported types
                                   via the same
                                   findArgTypeModule /
                                   findArgTypeGeneric helpers (file-
                                   local first, then fileScope
                                   fallback) + GenericImplMap
                                   (Table[ResolvedGeneric,
                                   AnalyzedArgumentType]) with merge
                                   (conflict-on-different-binding) +
                                   concrete* overloads (implMap-keyed
                                   and positional impls +
                                   genericTypeIndex — the latter
                                   read off the resolver's data
                                   types after task 6c)
    funcrefs.nim                   ResolvedFileScope (Identifier ->
                                   ResolvedDefinedType, spans local
                                   + imported types; the analyzer's
                                   single fileScope table, populated
                                   by analyzeFile in appdefs.nim.
                                   Was AnalyzedDefinedTypeScope
                                   pre-task-6c) + findDefinedType /
                                   findModuleDef (by argType or by
                                   name) / extractDataBlock /
                                   extractStructFor / extractUnionFor
                                   lookup helpers /
                                   AnalyzedFunctionScope + clone.
                                   Function-call funcDef lookup is
                                   inlined into analyzeFunctionCall
                                   in body.nim.
    patterns.nim                   generic parseInteger[T: SomeInteger]
                                   helper (parseutils + scanf with
                                   compile-time signed/unsigned
                                   dispatch + bounds check against
                                   T.high/low) /
                                   AnalyzedUnionPatternScope + update
                                   + hasUncoveredCases /
                                   AnalyzedLiteralPatternScope
                                   (tagged union over the eight
                                   integer kinds; whole-domain
                                   exhaustiveness currently requires
                                   a variable case binding) /
                                   AnalyzedUnionPattern (carrying
                                   `bindings: seq[AnalyzedBinding]`
                                   where AnalyzedBinding is
                                   `tuple[name: Identifier, argType:
                                   AnalyzedArgumentType]` — the
                                   post-6c replacement for the
                                   retired def-level
                                   AnalyzedArgumentDefinition
                                   wrapper) + analyzeUnionCasePattern
                                   / AnalyzedCasePattern
                                   (acpkUnion / acpkInteger /
                                   acpkVariable — mirrors the
                                   grammar's CaseDef: UnionPattern |
                                   LiteralPattern | VariablePattern)
                                   + analyzeCasePattern (overloaded
                                   for union vs literal context)
    body.nim                       AnalyzedVariable + analyzeVariable
                                   / AnalyzedLiteralInitializer +
                                   analyzeLiteralInitializer /
                                   AnalyzedGetter (struct-shaped
                                   module property lookup; carries
                                   `source` — the source variable's
                                   AnalyzedArgumentType — and
                                   `property` — the resolved field
                                   def) + analyzeGetter + body-level
                                   mutually-recursive type cluster:
                                     — AnalyzedFunctionCall
                                     — AnalyzedKeywordArgument
                                     — AnalyzedStructRef +
                                       AnalyzedUnionRef (each a flat
                                       `resolved + analyzedImpls:
                                       seq[AnalyzedArgumentType]`
                                       after task 8 — no default/impl
                                       arms; empty analyzedImpls
                                       means the initializer walks
                                       kwargs to accumulate impls,
                                       non-empty means substitute
                                       user-supplied impls into
                                       variant fields)
                                     — AnalyzedStructInitializer /
                                       AnalyzedUnionInitializer
                                       (each carries the analyzer-
                                       built argType; on the empty-
                                       impls path it may still
                                       carry free generics)
                                     — AnalyzedInitializer /
                                       AnalyzedCaseBlock /
                                       AnalyzedMatchExpression
                                     — AnalyzedAssignment /
                                       AnalyzedSetter (Statement
                                       variant after task 4 —
                                       previously AnalyzedMutation
                                       when it lived in Expression)
                                     — AnalyzedExpression /
                                       AnalyzedStatement
                                   Analyze procs:
                                     analyzeValueTypeAgainstDefinitionType
                                     (overload set — takes explicit
                                     `loc: Location` so type-mismatch
                                     errors point at the use site) /
                                     analyzeArgumentList (per-funcDef
                                     arity + overload-resolution
                                     variants) / analyzeFunctionCall
                                     (public-only filter dispatched
                                     on receiver kind — modules
                                     apply the "external call needs
                                     public" rule; generics allow
                                     any funcDef. Concretizes the
                                     matched funcDef's return type
                                     via the inferred
                                     GenericImplMap.) /
                                     analyzeCaseBlock (union +
                                     literal ctx; both extend
                                     caseScope with statement-level
                                     bindings) /
                                     verifyUniformReturnType /
                                     analyzeCases (shared
                                     uniform-return check) /
                                     analyzeMatchExpression (runs
                                     concrete() on the subject
                                     union so case-arm bindings
                                     see substituted field types) /
                                     analyzeKeywordArgument (uses
                                     analyzeLiteral for literal-
                                     typed kwarg values) /
                                     analyzeUnionInitializer (single
                                     code path over analyzedImpls
                                     — bounded seed loop over
                                     `if position <
                                     analyzedImpls.len`) /
                                     analyzeStructInitializer /
                                     analyzeInitializer /
                                     analyzeExpression /
                                     analyzeAssignment (extends
                                     funcScope with the new binding)
                                     / analyzeSetter (LHS getter +
                                     RHS expression — type equality
                                     not yet checked) /
                                     analyzeStatement. The shared
                                     analyzeLiteral helper at the
                                     top of body.nim dispatches on
                                     ResolvedLiteralDef and calls
                                     analyzeIntegerLiteral[T]
                                     (generic over target
                                     width/signedness) or
                                     analyzeStringLiteral. F32/F64/
                                     Pointer literal positions
                                     still return todo; struct/
                                     union-typed positions return
                                     a "needs initializer"
                                     diagnostic.
    funcs.nim                      AnalyzedUserFunction (holds
                                   ResolvedFunctionDefinition +
                                   statements) +
                                   AnalyzedExternFunction /
                                   AnalyzedFunction tagged union /
                                   AnalyzedModule (holds a
                                   ResolvedModule back-reference +
                                   AnalyzedFunction list — no
                                   AnalyzedModuleDefinition wrapper
                                   after task 6c) +
                                   analyzeUserFunction (enforces
                                   last-statement return-type
                                   match) + analyzeModule
    appdefs.nim                    AnalyzedFile (ResolvedFile
                                   back-reference + imports +
                                   analyzed modules) + AnalyzedApp
                                   (ResolvedApp back-reference +
                                   per-file analyzed views) + the
                                   public `analyze*` entry
                                   (returns `Result[AnalyzedApp,
                                   string]`). Post-6c there is no
                                   AnalyzedFileDefinition /
                                   AnalyzedAppDefinition split —
                                   the analyzed value is just the
                                   files list plus its resolver
                                   back-reference.

examples/
  base.asl                         standard library definition (extern functions)
  *.asl                            positive test fixtures
  errors/*.asl                     negative test fixtures (each documented)

tests/
  config.nims                      adds src/{,tokenizer,parser,resolver,
                                   analyzer} to the search path
  tutils.nim                       shared helpers (tokenize/parse/
                                   resolve/analyze over in-memory
                                   strings + temp dirs)
  all.nim                          aggregator that imports test_*.nim
  test_tokenizer.nim               tokenizer unit tests
  test_combinators.nim             Spec / combinator unit tests
  test_ast.nim                     AST constructor invariants (covers
                                   the per-concept files in
                                   src/analyzer/resolver/parser/)
  test_grammar.nim                 single-file parse tests across all
                                   per-concept grammar specs
  test_loader.nim                  BFS / topo / parent-escape tests
  test_resolver.nim                end-to-end resolver tests
  test_analyzer.nim                end-to-end analyzer tests
  test_cli.nim                     CLI parsing tests (--vendor flag,
                                   etc.)

test.sh                            regression runner (exit-code based)
grammar.md                         source-of-truth domain grammar
                                   (see "Domain grammar" section)
tasks.md                           DDD refactor roadmap
bugs.md                            issue tracker (open + resolved)
lessons.md                         design retrospective
documentation.md                   user-facing language reference
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

**Tagged unions** — `Expression`, `Statement`, `DataDef`,
`Initializer`, `CasePattern`, `Function`, `Type`, `File`,
`ImportPath` all use `case kind:` discriminators with exhaustive
matching. Naming normalized: every "definition" concept uses the
`Def` suffix (`ArgumentDef`, `FunctionDef`, `VariantDef`, `StructDef`,
`UnionDef`, `LiteralDef`, `DataDef`) so the union umbrella and its
arms all rhyme.

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
combinators, AST constructors, grammar, loader, resolver, analyzer,
CLI, utils) has its own `test_*.nim` file aggregated by
`tests/all.nim`. **289 tests** covering positive paths, negative
paths, edge cases, Trojan Source defenses in the tokenizer, direct
rollback / composition tests for every combinator atom, and the
generic graph algorithms in `src/utils.nim`.

`./test.sh` — integration suite that drives the binary against
every `examples/*.asl` fixture and asserts exit codes:

- **Positive** (`examples/*.asl`): must exit 0
- **Negative** (`examples/errors/*.asl`): must exit non-zero

Each fixture has a leading `#` comment documenting what feature or
error condition it exercises. 35 fixtures total (20 positive + 15
negative; two of the error fixtures are dependency files skipped by
the runner).

## What's Next

The **Analyzer phase is functionally complete** — `analyze*` walks
the `ResolvedApp` end-to-end and returns an `AnalyzedApp` that
holds a type-rich representation of every value, expression, and
statement in each function body. Integration suite at **33/35**;
unit suite at **289/289**. Recent parser + naming refactor (Tasks
11–15 + follow-ups): data-driven combinator atoms, spec-name
normalization, `Type` umbrella retired in favour of split
`typeIndex` / `importedNameIndex` on `File`, `DefinedType` renamed
to `Type` across parser/resolver/analyzer, `Definition` normalized
to `Def` everywhere. See tasks.md for the full trail.

What the analyzer does today (all wired):

- Overload selection at function-call sites — each candidate funcDef
  is unified against the call's argument types via `GenericImplMap`
  + `merge`, and uniqueness picks the survivor (ambiguity rejected).
- Impl-list arity + generic constraint satisfaction — task 7 moved
  these checks into `resolveModuleArgumentType` via
  `checkImplSatisfiesGeneric`; the analyzer trusts the resolver's
  result and only runs use-site signature-parity checks via
  `analyzeValueTypeAgainstDefinitionType`.
- Concretization — the matched funcDef's return type and the
  match-subject's union are rewritten through `concrete()` with the
  inferred impls so downstream sites see substituted types.
- Union initializer parametric inference — reads
  `AnalyzedUnionRef.analyzedImpls` (single-shape after task 8).
  Non-empty seq: user-supplied impls are substituted into variant
  fields via `concrete()` before type-check. Empty seq: the
  initializer walks kwargs accumulating a `GenericImplMap` and
  emits a result type with bound concretes where the variant
  touched the generic and free generics where it didn't
  (leave-as-is). Single code path — bounded seed loop over
  `analyzedImpls.len` handles both cases.
- Literal type inference — the `analyzeLiteral` helper dispatches on
  `ResolvedLiteralDef` and validates every integer kind
  (U8/U16/U32/U64/I8/I16/I32/I64) plus String against the expected
  target. `analyzeArgumentList`, `analyzeKeywordArgument`, and
  `analyzeLiteralInitializer` all route through it.
- Case-pattern duplicate detection — `checkDuplicate[T: SomeInteger]`
  handles all eight integer kinds uniformly.
- Body-level constructs — getter (struct-shaped property read),
  variable case patterns (`VariablePattern` is a first-class
  `CaseDef` variant), setters, assignments, match expressions with
  case-arm bindings, struct + union initializers, literal
  initializers.

Focused TODOs still open:

- **Equality vs unification for analyzed types**
  (`analyzer/argtypes.nim`, the `==` on `AnalyzedArgumentType`).
  Assignability against an expected type that carries free
  generics (post leave-as-is) needs unification, not hash equality.
  Surfaces as the case-arm uniformity check failing on a handful
  of fixtures that flow free-generic values through
  `verifyUniformReturnType`. Fix is to route every assignability
  check through `analyzeValueTypeAgainstDefinitionType` + `merge`,
  with eager chain-collapsing in `merge`.
- **Substitution chains in `concrete()`** — `Sample → K, K → u8`
  should collapse to `Sample → u8`; today `concrete()` does a
  single `getOrDefault`. Pairs with the equality fix above.
- **F32 / F64 / Pointer literal kinds** — `analyzeLiteral` returns
  a todo for these three.
- **Impl-map update from literal positions** — when a literal arg
  flows into a generic position (e.g., `f(K=…)` with literal
  inferable type), the resulting binding isn't yet recorded.
- **`findRequiredImplsForFields` nested-impl walk**
  (`analyzer/resolver.nim`) — needs to walk into impls so a field
  typed `Box[u8, Sample]` contributes `Sample` to the parent's
  requires.
- **Type-correctness checks across statements** — assignment
  compatibility, match exhaustiveness, setter type equality.

After the analyzer:
- **IR generation** — lower the analyzed AST into an intermediate
  representation suitable for optimization and code generation.
- **Code generation** — emit target code (likely C or LLVM IR).
