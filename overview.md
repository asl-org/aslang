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
  │              genericTypeIndex, ...). Two-pass shell/populate
  │              inside domain.nim breaks the ResolvedModule ↔
  │              ArgumentType cycle: pass A allocates an empty
  │              ResolvedModule shell for every parser Module so
  │              back-references resolve; pass B populates each
  │              shell with the resolved requires/data/functions.
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

`src/parser.nim` (barrel) + `src/parser/{combinators, identifiers,
literals, imports, argtypes, patterns, body, data, funcs, generics,
modules, decls, loader}.nim` + `src/parser/tokenizer/` (nested
tokenizer barrel + subfolder).

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

**Multi-file resolution** (`loader.nim`): BFS traversal of imports,
tokenize + parse each dependency, topological sort via DFS with
cycle detection. Parent-directory escape prevention
(`./sub/../../escape` caught by normalizing the resolved path). Both
graph algorithms live in `src/utils.nim` — `bfs[T, V]` is generic;
`topoSort` is currently string-typed.

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

`src/resolver/{domain, literals, patterns, imports, files, apps,
resolver}.nim`

Returns a `ResolvedApp` containing a `ResolvedFile` per source file,
which in turn holds resolved imports plus a `ResolvedDefinedType` for
each module/generic. Body-level name resolution is complete (variables,
getters, function calls, initializers, match/case patterns). The
resolver also enforces the structural requires-block constraints
(unique generics in requires, must pair with a struct, struct can't
carry generic fields when requires is present), runs the arity +
generic-constraint checks on every impl list (task 7 moved these here
from the analyzer), and stores the resolved receiver module directly
on `ResolvedStructRef` / `ResolvedUnionRef` (single-shape after task 8
— `resolvedImpls: seq[ResolvedArgumentType]`, empty for the bare
surface form, populated for the bracketed form). Scope:

- **File layout — one `domain.nim` for the mutually-recursive cycle.**
  Nim requires the cycle of `ref object` types rooted at
  `ResolvedArgumentType` (which reaches through Module / Function /
  Statement back to itself) to share a single `type:` block, so every
  type in the cycle plus its constructors, accessors, and `resolve*`
  procs lives in `src/resolver/domain.nim` (~1900 lines) grouped by
  concept via `# ==== …` section dividers. Standalone concepts stay
  in their own files: `ResolvedLiteralDef` in `literals.nim`,
  `ResolvedCasePattern` in `patterns.nim`, `ResolvedImport` in
  `imports.nim`, `ResolvedFile` in `files.nim`, `ResolvedApp` in
  `apps.nim`. Barrel `resolver.nim` re-exports.
- **Two-pass walk per app** (files come topo-sorted leaves-first
  from the loader, so imports are always resolved before use).
  - Pass A (declare, shell): allocate an empty `ResolvedModule`
    shell for every parser `Module` in the app via
    `newResolvedModuleShell`, keyed on parser identity in a
    `ResolvedModuleShells` table. This is the one-shot mechanism
    that breaks the `ResolvedModuleArgumentType.resolvedModule ↔
    ResolvedModule` cycle — every downstream reference resolves to
    a valid (though empty) shell even before its define pass runs.
    Per-file work in this pass also registers every defined-type
    name and every imported binding into a `FileScope`.
  - Pass B (define, populate): for each module, resolve its
    `requires(...)` clause (if any, declaring explicit type
    parameters), its data block (`LiteralDef` / `StructDef` /
    `UnionDef`), and each function signature. For each generic,
    resolve each function signature. Every `ArgumentType` root must
    look up in the scope; impls resolve recursively and are
    arity- + constraint-checked. When the module's define pass
    completes, `populateResolvedModule` fills in its shell.
- **Impl-list validation** — `resolveModuleArgumentType` calls
  `checkImplSatisfiesGeneric` on every impl inference path (explicit
  `requires(...)`, inferred struct fields, inferred union fields).
  The check verifies `(name, arity)` at the parser level; downstream
  `analyzeValueTypeAgainstDefinitionType` catches signature-parity
  mismatches at use sites.
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
  the init site. Generic-uniqueness inside an explicit
  `requires(...)` block is the one place that *is* checked.
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
  `FunctionScope` (HashSet[Identifier]) tracks the names of
  variables currently in scope; the type of each variable is the
  Analyzer's concern. The resolver collects candidate overloads but
  does not pick the unique one — that's the Analyzer.
- **Not the resolver's job**: overload selection (picking the unique
  candidate after matching concrete arg types) and body-level
  type-correctness checks. Those belong to the Analyzer phase.
- **No structural-size check** — all struct values are pointer-backed
  at runtime, so mutual struct containment does not create infinite
  types. Name cycles are the only cycles, and the shell-pass
  dissolves them.
- **Scope limit on `ResolvedGenericArgumentType.generic`** — task 6b
  only threaded the module edge through the shell/populate two-pass.
  `ResolvedGenericArgumentType.generic` remains a parser `Generic`
  reference; the same treatment for generics would follow the same
  pattern but is deferred (no downstream task needs it yet).

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
  parser.nim                       parser barrel (re-exports everything
                                   under parser/) — the public entry
                                   for the parser layer

  parser/                          parser internals (private to the
                                   barrel; consumers say `import parser`)
    combinators.nim                Spec[T] + Parser + all combinators.
                                   Primitives: oneOf / any / atLeastOne /
                                   optional / separatedBy / contained /
                                   map. Atoms (Tasks 14–15): prefixed /
                                   suffixed / pair / triple / separated /
                                   presence. Trivia: ws0 / ws1 /
                                   blankLines. Comment / ignorableLine
                                   / separator specs.
    identifiers.nim                Identifier / Space / Decorator
                                   + identifierSpec / keywordSpec /
                                   indentationSpec / indentedLine /
                                   decoratorLineSpec + blockSpec /
                                   decoratedBlockSpec.
    literals.nim                   Literal (lkString/lkInteger/lkFloat) +
                                   StringLiteral / IntegerLiteral (union
                                   over Signed/Unsigned) / FloatLiteral +
                                   LiteralDef + all leaf-literal specs.
    imports.nim                    ImportedType / Import (ikExplicit/
                                   ikShorthand) / ImportPath (ipkRelative/
                                   ipkVendor) / VendorRoots +
                                   parseImportPath + resolveImportPath.
    argtypes.nim                   ArgumentType / ArgumentDef /
                                   ArgumentDefList + their specs.
    patterns.nim                   UnionPatternField / UnionPattern /
                                   CasePattern (cpkInteger / cpkVariable /
                                   cpkUnion) + their specs.
    body.nim                       Getter / LiteralInitializer + StructRef
                                   + UnionRef (each a flat
                                   `module: Identifier + impls:
                                   seq[ArgumentType]` after task 8 —
                                   empty impls = bare surface form,
                                   non-empty = explicit-impls) + Setter
                                   (Statement variant after task 4) +
                                   body-level cluster (ArgumentList ↔
                                   FunctionCall ↔ KeywordArgument ↔
                                   Initializer ↔ Expression ↔ Match /
                                   CaseBlock ↔ Statement ↔
                                   StatementList / Assignment / Setter)
                                   + their specs.
    data.nim                       StructDef / VariantDef / UnionDef /
                                   DataDef (ddkStruct/ddkUnion/ddkLiteral)
                                   + their specs.
    funcs.nim                      FunctionDef + UserFunction /
                                   ExternFunction / Function (fkUser/
                                   fkExtern) / FunctionList + their
                                   specs (functionDefSpec /
                                   functionDefLineSpec /
                                   functionDefListSpec /
                                   userFunctionSpec / externFunctionSpec
                                   / functionSpec / functionListSpec).
    generics.nim                   Generic / Requires + their specs.
    modules.nim                    Module + moduleHeaderSpec /
                                   moduleBodySpec / moduleSpec.
    decls.nim                      Type (tkModule/tkGeneric) / File
                                   (fkAsl/fkAslr) / App + typeSpec /
                                   aslFileSpec / aslrFileSpec + the
                                   public `parse*` entry. File carries
                                   separate `typeIndex` (local defs) +
                                   `importedNameIndex` (imports) —
                                   the former `Type` umbrella retired.
                                   `findType(name)` returns a locally-
                                   defined `Type`;
                                   `findImportedName(name)` returns an
                                   `ImportedType`.
    loader.nim                     BFS multi-file resolution via
                                   `bfs[string, File]` from utils, then
                                   `topoSort` for dependency order.
                                   `importPaths(file)` helper feeds both
                                   passes.
    tokenizer.nim                  tokenizer barrel — re-exports Token /
                                   TokenKind / Location / tokenize.
    tokenizer/
      constants.nim                BidiCodepoints / ZeroWidthCodepoints /
                                   InvisibleCodepoints arrays +
                                   AsciiMaxValue / Punctuations / Space /
                                   Newline constants.
      location.nim                 Location type + accessors (newLocation,
                                   advance, $, hash, ==, <); re-exported
                                   through parser.nim (every AST node
                                   carries one).
      token.nim                    Token type + accessors.
      spec.nim                     Data-driven per-kind TokenSpec array
                                   + the tokenize loop's dispatcher.

  resolver/
    resolver.nim                   re-exports every component file
    literals.nim                   ResolvedLiteralDef + resolveLiteralDef
    patterns.nim                   ResolvedCasePattern + resolveCasePattern
    imports.nim                    ResolvedImportedType / ResolvedImport
    domain.nim                     Every mutually-recursive resolved
                                   type + its constructors, accessors,
                                   and resolve* procs, grouped by
                                   concept via `# ==== …` section
                                   dividers. ~1900 lines. Nim requires
                                   the ref-object cycle rooted at
                                   ResolvedArgumentType (Module ↔
                                   Function ↔ Statement ↔ ArgumentType)
                                   to share a single `type:` block, so
                                   the concepts stay grouped in one
                                   file rather than fractured across
                                   many. Cover:
                                     — Argument-type cluster:
                                       ResolvedArgumentType (flat
                                       tagged union over
                                       ResolvedModuleArgumentType |
                                       ResolvedGenericArgumentType,
                                       no ratkImported/ratkDefined
                                       intermediate) + FileScope +
                                       resolveArgumentType (module +
                                       generic context overloads) +
                                       checkImplSatisfiesGeneric
                                     — ResolvedModuleShells table +
                                       shell/populate mechanism that
                                       breaks the ResolvedModule ↔
                                       ArgumentType cycle
                                     — Function-def cluster:
                                       ResolvedArgumentDefinition /
                                       ResolvedFunctionDefinition /
                                       ResolvedExternFunction
                                     — Data cluster: ResolvedStructDef
                                       (with fieldIndex + findField +
                                       genericTypeIndex) /
                                       ResolvedVariant (with
                                       fieldIndex + findField) /
                                       ResolvedUnionDef (with
                                       variantIndex + findVariant +
                                       genericTypeIndex) /
                                       ResolvedData +
                                       accumulateGenericPosition
                                     — Body-level cluster:
                                       ResolvedGetter /
                                       ResolvedLiteralInitializer /
                                       ResolvedStructRef +
                                       ResolvedUnionRef (both flat
                                       objects with resolvedModule +
                                       resolvedImpls after task 8;
                                       empty resolvedImpls = bare
                                       surface form) /
                                       ResolvedStructInitializer /
                                       ResolvedUnionInitializer /
                                       ResolvedFunctionCall (each
                                       exposing resolvedImpls*
                                       accessors) /
                                       ResolvedInitializer /
                                       ResolvedAssignment /
                                       ResolvedSetter (Statement
                                       variant after task 4) /
                                       ResolvedCaseBlock /
                                       ResolvedMatchExpression /
                                       ResolvedExpression /
                                       ResolvedStatement +
                                       FunctionScope (HashSet of
                                       variable names in scope)
                                     — Function cluster:
                                       ResolvedUserFunction /
                                       ResolvedFunction
                                     — Module + Generic:
                                       ResolvedModule (with
                                       funcDefIndex +
                                       funcNameArityIndex +
                                       findFunctionDefs(name, arity,
                                       public)) / ResolvedGeneric
                                       (with funcNameArityIndex +
                                       findFunctionDefs) +
                                       newResolvedModuleShell +
                                       populate
                                     — ResolvedDefinedType (umbrella)
    imports.nim                    ResolvedImportedType / ResolvedImport
                                   + resolveImport
    files.nim                      ResolvedFile + resolveFile (declare
                                   pass — registers defined-type names
                                   and imported bindings into FileScope)
    apps.nim                       ResolvedApp + the public `resolve*`
                                   entry. Runs buildModuleShells first
                                   (declare pass: one shell per
                                   parser Module), then resolves each
                                   file (define pass: populates each
                                   shell as its module completes).

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
                                   the per-concept files in src/parser/)
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
`tests/all.nim`. **271 tests** covering positive paths, negative
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
unit suite at **271/271**. Recent parser + naming refactor (Tasks
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
  (`resolver/domain.nim`) — needs to walk into impls so a field
  typed `Box[u8, Sample]` contributes `Sample` to the parent's
  requires.
- **Type-correctness checks across statements** — assignment
  compatibility, match exhaustiveness, setter type equality.

After the analyzer:
- **IR generation** — lower the analyzed AST into an intermediate
  representation suitable for optimization and code generation.
- **Code generation** — emit target code (likely C or LLVM IR).
