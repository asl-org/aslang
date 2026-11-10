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
    name: string
    age: u32

  public func start(): u8
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
  (struct, union, or — for built-in scalars — `literal: "uint8"` etc.)
  and functions
- **Structs**: product types with named fields (`struct: name: string`)
- **Unions**: sum types with named variants, each optionally carrying
  fields (`union: Free { usage: u32 }; Pro { credits: u32 }`)
- **Functions**: typed, overloadable by parameter signature. Method
  call syntax via `Type.method(args)`. Two authored kinds: user
  functions (with a body) and extern functions (`@extern("symbol")`
  linking to an external implementation); a third, generated kind is
  the `public func byte_size(): u64` that `newModule` injects into
  every module with a data block
- **Generics**: type-parameterized function signature blocks
  (`generic Eq: func eq(a: Eq, b: Eq): u8`)
- **Pattern matching**: `match` expressions whose `CasePattern` has
  three kinds — integer (`cpkInteger`, `case 0`), variable binding
  (`cpkVariable`, `case other`), and variant destructuring
  (`cpkUnion` over a `UnionPattern`, `case Pro { credits: c }: ...`)
- **Error propagation**: `try f(...)` unwraps the `Ok` value of a call
  returning `Status[Value, Error]` and propagates its `Err`; the
  enclosing function must return a `Status` with the same error type
- **Imports**: cross-file module/generic imports with aliasing
  (`import { User as U } from "./user.asl"`)
- **Visibility**: `public` keyword on modules and functions to
  mark them as exported. A non-public function is module-internal:
  callable and able to satisfy a generic constraint only from inside
  the module that defines it; every other context (another module,
  any generic block) sees public functions only
- **Comments**: line comments starting with `#`

### Built-in Types

Fixed-width integers: `i8`, `i16`, `i32`, `i64`, `u8`, `u16`,
`u32`, `u64`. Floats: `f32`, `f64`. Text: `string`. Containers:
`Array`, `Bitset`. Fallibility: the union `Status[Value, Error]`
(`Ok { value: Any }` / `Err { error: Failure }`), with `T!` as parse-time
sugar for `Status[T, Error]` and `T!E` for `Status[T, E]`; `Failure` is
the error-contract generic and `Error` the built-in struct module that
satisfies it. Generic contract: `Any` (`byte_size`). System
namespace: `System` — a function-only module. All of these live in
`examples/base.aslr`, the default `@std` vendor. Modules without a
data block are pure namespaces: their functions are callable
(`System.println(...)`) but the module itself is not a value and
cannot appear as an argument or return type.

## Domain grammar (source of truth)

The compiler's domain vocabulary — the type names and shapes that
parser / resolver / analyzer values conform to — is captured in
[`grammar.md`](grammar.md). Every layer's type module traces back
to it. When a domain concept is renamed, added, or restructured, it
lands there first; the code catches up. Headline reshapings so far:
`StructDef`/`UnionDef`/`LiteralDef` data-block variant names, the
former assignment / setter / bare-expression forms collapsed into a
single `Statement` node (kinds none / variable / getter: `skNone` /
`skVariable` / `skGetter` in the parser, `rskNone` / `rskVariable` /
`rskGetter` downstream) at every layer, value positions typed
`InlineExpression`, the variable binding as a first-class
`CasePattern` kind, the flat `ResolvedArgumentType:
ResolvedModuleArgumentType | ResolvedGenericArgumentType` split, and
`StructRef`/`UnionRef` as a single shape carrying an `ArgumentType`
whose (possibly empty) impls seq distinguishes `Module { ... }` from
`Module[Impl] { ... }`.

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
  │                          enforced in constructors; one depth-first
  │                          walk loads every imported file, detects
  │                          cycles, and emits files leaves-first;
  │                          per-file typeIndex over locally-defined
  │                          types + importedNameIndex over
  │                          explicit-import bindings)
  ▼
Resolver ──── Walks the parsed App and produces a ResolvedApp:
  │              name/shape resolution for every ArgumentType,
  │              body-level name resolution for user-function
  │              bodies. Impl-list arity + generic-constraint
  │              checks are the def analyzer's job. Resolved*
  │              def-level types carry the accessors + indices
  │              later phases need (findField, findVariant,
  │              findFunctionDefs, genericTypeIndex, ...) plus a
  │              (fileId, typeId, functionId) identity path.
  │              Single-pass: resolved argument types + struct/union
  │              refs hold the parser `Module` identifier (not a
  │              ResolvedModule back-ref), so no ref-object cycle
  │              forms. Downstream layers that need the resolved
  │              module do an identity-keyed lookup at their site
  │              (`fileCtx.findModule(module)` on the phase-A /
  │              phase-B contexts, `ResolvedFile.findLocalType` —
  │              assert-backed direct returns; keys hash by source
  │              location, so aliased imports can never miss).
  ▼
Defanalyzer ─ Phase A (analyzeDefApp) — walks every file, every
  │              module + generic, every struct/union/literal, every
  │              funcDef AND every user-function statement across the
  │              whole app. Produces AnalyzedDefApp bundling per-file
  │              AnalyzedDefFile + per-module AnalyzedDefModule +
  │              per-def AnalyzedFunctionDef (args + return type
  │              fully analyzed) + per-function AnalyzedDefStatement
  │              trees (every def-level fact in a body — literal
  │              defaults, call receivers, struct/union refs —
  │              re-bound to its resolved def). Impl counts and
  │              generic-constraint satisfaction are checked here.
  │              Any def-site error surfaces before any body walker
  │              runs — the guarantee that phase A gives.
  ▼
Analyzer ──── Phase B — walks function bodies through the context
  │              ladder AnalyzedFileContext → AnalyzedModuleContext →
  │              AnalyzedUserFunctionContext. analyzeFunctionCall
  │              reads its overload candidates off the phase-A twin
  │              (`funcCtx.findType(fncall.typ).findFunctionDefs(
  │              name, arity, access)`) — no re-analysis at the call
  │              site; only the generic-impl substitution (`concrete`)
  │              runs per call. Struct/union initializers merge the
  │              AnalyzedImplMap each kwarg contributes; `try` calls
  │              unwrap Status; bare literals adopt or default their
  │              type; matches check exhaustiveness and duplicate
  │              integer patterns.
  ▼
  Monomorphize ── specialize generics demand-first from `start` into a
  │               per-instance node IR, returned as a MonoApp (landed;
  │               src/monomorphize.nim, plans/plan_monomorphizer.md)
  ▼
(planned — plans/plan_monomorphization.md)
  Lifetime ────── ownership / in-place-vs-copy on the concrete IR
  Codegen ─────── C now; Verilog/VHDL later
```

Orchestrated by `src/asl.nim`:
```nim
let app = ? parse(filepath, opts.indentWidth, opts.dumpTokens, opts.vendorRoots)
let resolvedApp = ? resolve(app)
let analyzedApp = ? analyze(resolvedApp)
discard ? monomorphize(analyzedApp)
ok("[SUCCESS]")
```

`compile` now runs through `monomorphize` and returns `[SUCCESS]`; the
returned `MonoApp` is discarded — there is no code generation on main yet. `analyze*` (on the analyzer barrel) runs
`analyzeDefApp` first and then walks its bundle; it returns a structured
`AnalyzedApp` — the `AnalyzedDefApp` back-reference plus a
`seq[AnalyzedFile]`, where each `AnalyzedFile` carries its
`AnalyzedDefFile` back-reference (the phase-A output that produced it)
and the analyzed modules parsed out of it. Imports have no analyzed
form of their own: an imported type's analyzed twin is fetched from its
source file's def bundle and folded into the file context.
`AnalyzedApp` also exposes `entry` (the single public `start` function
of the root file) and `findModule`; it is the handle the planned
monomorphization pass will consume.

Phase-A output (`AnalyzedDefApp` + per-file `AnalyzedDefFile` +
per-module `AnalyzedDefModule` + `AnalyzedGeneric` +
`AnalyzedFunctionDef` + the data-block wrappers `AnalyzedStructDef` /
`AnalyzedVariantDef` / `AnalyzedUnionDef` / `AnalyzedLiteralDef` /
`AnalyzedDataDef`) is consumed by the phase-B body walkers through the
context ladder in `analyzer/context.nim`, so overload resolution reads
pre-analyzed funcDef signatures — no re-analysis of arg types or return
types at call sites.

There is no separate `Validator` phase. Every uniqueness / structural
rule the validator used to enforce (duplicate names, empty blocks,
import collisions, duplicate fields/variants) is now a precondition
inside an AST constructor (`newStructDef`, `newUnionDef`, `newModule`,
`newAslFile`, etc.). Invalid AST nodes cannot be constructed, so no
separate validation pass is needed. `validations.md` catalogues the
rules by pipeline phase, each pinned to the test that asserts it.

### Phase 1: Tokenization

`src/tokenizer/main.nim` (barrel + `tokenize` driver) + `src/tokenizer/`

Whole-lexeme classifier driven by an ordered list of token specs.
Produces `seq[Token]` where each token carries `kind`
(`tkPunctuation`, `tkSpace`, `tkNewline`, `tkIdentifier`, `tkInteger`,
`tkFloat`, `tkString`, `tkComment`), `value` (the full lexeme string),
and `Location` (filepath:line:col). `tkSpace` / `tkNewline` batch runs
of their rune; identifiers, integers, floats, strings, and comments are
matched greedily into one token each. The special float values
`nan` / `inf` / `+inf` / `-inf` lex as single `tkFloat` tokens and are
reserved — `inf` / `nan` can never be identifiers.

Security: validates UTF-8 encoding and rejects bidirectional control
codepoints, zero-width characters, and invisible Unicode (Trojan
Source defense).

A synthetic trailing newline token is appended to every token stream,
so parsers can rely on "statement ends with a newline" holding for
the last line of a file with no terminating newline.

### Phase 2: Parsing

`src/parser/main.nim` (barrel — re-exports every per-concept module and
hosts the file-level grammar plus the multi-file `parse*` entry point)
+ `src/parser/` (per-concept AST modules — see the Project Structure
table for the current listing). The combinator layer and `ParserError`
live in `src/parser/parser.nim`. The tokenizer is a separate sibling
package (`src/tokenizer/`); `parser.nim` imports it via
`import ../tokenizer/main as tokenizer` and re-exports it, so every
parser submodule (and every `import ../parser/main` consumer) gets
`Location` / `Token` without a separate import.

The parser is a sibling package, not a sub-tree of the resolver:
defanalyzer, analyzer, lsp, cli, and asl.nim that need parser types
import `../parser/main as parser` directly. The barrel re-exports
`parser.nim` too, so the parser tests can drive the combinator
machinery through `parser/main`; downstream layers use only the AST
types and `parse*`.

Recursive descent via composable `Spec[T]` combinators. A `Spec[T]` is
a named, typed tagged union (`skDefault` wraps a consumer proc,
`skToken` a single-token matcher); `newSpec` builds either. The
exported combinators:
- `expect` — run a spec (or a literal token value) against the parser
- `oneOf` — ordered alternatives with backtracking
- `any` / `atLeastOne` — repetition (zero-or-more / one-or-more)
- `optional` — zero-or-one, returns `Option[T]`
- `map` — transform the parse result (plain or `Result`-returning mapper)
- `parenthesisList` / `squareBracketList` / `curlyBracketList` —
  comma-separated lists wrapped in `(...)` / `[...]` / `{...}`
- `indentedLine` — indentation + item + trailing newline(s); the
  block-body item shape
- `indentedBody` / `indentedBlock` — run a body one indent level
  deeper (optionally after a header line)
- `done` / `loc` / `newParser` / `newParserError` — parser state and
  error helpers

Shared leaf specs (`SPACE`, `NEWLINE`, `indentationSpec`) also live in
`parser.nim`. Backtracking via checkpoint/restore of `parser.index` and
`parser.level` inside `expect`. A body failure under `indentedBody` is
marked fatal: once a header has committed a block, `oneOf` / `optional`
/ repetition no longer backtrack out of it, which keeps diagnostics
precise. Forward-declared `var` specs (`inlineExpressionSpec`,
`statementListSpec` in `parser/statement.nim`) resolve the body
cluster's mutual recursion.

**Multi-file resolution** (`parser/main.nim`'s `parse*(rootPath, …)`
entry): a single depth-first walk tokenizes + parses the root and every
file it transitively imports, emitting files in dependency order
(leaves first, root last). A `visiting` stack doubles as cycle detection
(reported as the offending chain); a `visited` set loads a diamond
dependency once. Parent-directory escape prevention
(`./sub/../../escape` caught by normalizing the resolved path) happens
when the import path is resolved inside the import-line spec.
A second `parse*` overload takes `overlays: Table[string, string]`
(absolute path → source text): an overlay shadows that file on disk
and passes the same size / UTF-8 checks. `asl lsp` uses it to compile
unsaved editor buffers; the 4-argument form passes no overlays.

**A-normal form expansion** (`parser/expansion.nim`, `expand(...)`
procs). Currently NOT wired in — no module imports `expansion.nim`
(`statementListSpec` builds the `StatementList` without expanding), and
the file still targets the pre-collapse assignment / setter shapes. It
is kept as reference for a post-analysis expander
(`TODO(post-analysis-expander)`, plans/plan_post_analysis_expansion.md).
The value positions it lifts are already narrowed to
`InlineExpression` in the grammar. When re-enabled, every
`StatementList` runs through this normalization pass so that:

- **Every value-position expression is a `Variable` or `Literal`**.
  Function-call arguments, keyword-argument values, and match
  subjects that would otherwise be nested `FunctionCall` /
  `Initializer` / `Getter` / `MatchExpression` values get lifted
  into preceding synthetic assignments `__asl_arg_N = <expr>`, and
  the original position is replaced with `Variable(__asl_arg_N)`.
- **After expansion, every top-level statement has a target.** A
  statement is one `Statement` node — a variable assignment (`x = e`),
  a getter assignment (`x.y = e`), or a bare expression — and this pass
  wraps the bare-expression form: `foo(x)` becomes `__asl_arg_N = foo(x)`.
  The tail statement of a function body carries the return value via the
  statement's RHS type (see the `statements[^1].argType` check in
  `analyzeUserFunction`).
- **Sub-expressions inside nested scopes recurse.** Case block
  bodies are their own `StatementList`, so they get their own
  expansion.

Lift rules by expression kind (`InlineExpressionKind`, plus `ekMatch`
on `Expression`):
- `iekLiteral`, `iekVariable` — never lifted. Literals must reach
  `analyzeBareLiteral` with their expected context intact for
  Approach C's concrete-adopt behavior; variables are already
  named bindings.
- `iekGetter` — lifted at value positions (`p.a` in `foo(p.a)`
  becomes `t = p.a; foo(t)`), passed through at assignment /
  getter-assignment RHS positions (`x = p.a` stays `x = p.a`).
- `iekFnCall`, `iekInitializer`, `ekMatch` — always recurse into
  their sub-expressions; the outer expression is lifted at value
  positions, passed through at RHS positions.

Synthetic identifiers use the `__asl_arg_N` form; `newIdentifier`
rejects any user identifier starting with `__asl`. Compiler-internal
construction goes through `newGeneratedIdentifier` in
`identifiers.nim`, which bypasses the prefix check. A per-function
counter provides uniqueness within the function scope.

Once wired, downstream layers would see only the ANF-normalized AST and
never need to reason about nested value-position expressions.

### Phase 3: Parser-level indexing (absorbed)

The parser itself performs the uniqueness / structural checks that
used to live in a separate validator. The lookup indices it builds
during construction double as the validation mechanism (`Table`
insertion fails on duplicate key).

Indices on AST nodes:
- `File.typeIndex` — `Identifier -> int` into `File.types` (locally-
  defined `LocalType` = module or generic).
- `File.importedNameIndex` — `Identifier -> ImportedType` covering
  every explicit-import binding on `fkAsl` files. Duplicate detection
  at parse time checks both indexes so an imported name and a local
  definition sharing an identifier collide immediately.
- `Module.functionIndex` / `Generic.funcDefArityIndex` — name → arity
  → positions, which is what allows overloading.
- `StructDef.fieldIndex`, `UnionDef.variantIndex`, `VariantDef.fieldIndex`,
  `ArgumentDefList.argNameIndex` — per-block duplicate detection.
- `App.fileIndex` — absolute path → file index.

The parser exposes focused lookups on `File` instead of a union:
`findType(name): LocalType` (local defs only), `findImportedType(name):
ImportedType` (explicit-import bindings), and `findExportedType(name)`
(a local def that must also be public). There is no parser-level
imported-or-defined umbrella type.

### Phase 4: Resolution

`src/resolver/main.nim` (facade — hosts every `resolve*` proc) +
`src/resolver/` (per-cluster files; see the Project Structure table for
the current listing). The parser it builds on is a sibling package
(`src/parser/`, Phase 2), imported directly via
`import ../parser/main as parser`.

Entry: `resolve*(app: App): Result[ResolvedApp, string]`. Returns a
`ResolvedApp` containing a `ResolvedFile` per source file, which in turn
holds resolved imports plus a `ResolvedLocalType` for each
module/generic. Every `ResolvedFile`, `ResolvedModule`,
`ResolvedGeneric` and `ResolvedFunctionDef` records a fully-qualified
identity path — `fileId` (the file's index in the app), `typeId` (the
type's index in its file), `id` (the function's index in its
module/generic) — groundwork for referring to resolved entities by id;
the ids are not part of any hash. Body-level name resolution is
complete (variables, getters, function calls, initializers, match/case
patterns). The resolver unions a struct's explicit `struct(...)`-header
generics (whose uniqueness the parser already enforced via
`validateRequiresNameConflict` inside `newStructDefHeader`) with those
collected recursively from the field types, populates each module argument
type's impl slots (leaving impl-count + generic-constraint validation
to the def analyzer), resolves struct/union refs into provably valid
shapes at ref-resolve time (`ResolvedStructRef` carries the
receiver's `ResolvedModuleArgumentType` + its `StructDef`;
`ResolvedUnionRef` the receiver plus the referenced `VariantDef` —
wrong-kind receivers and unknown variants rejected on the spot),
field-maps initializer kwargs (`resolveKeywordArguments` resolves the
expressions in source order; unknown/duplicate fields, undersupply, and
canonical field ordering are owned by the initializer constructors — one
shared shape for struct and union), and binds every bare literal's
default module against the FileContext (`ResolvedLiteral.default` —
same resolve-time binding as `ResolvedFunctionCall.typ`). Scope:

- **File layout — resolved types grouped by cluster, actor procs on
  the facade.** The per-cluster files (`argtype`, `datadef`,
  `function`, `functioncontext`, `refs`, `statement`, `types`,
  `imports`, `app`, `indexing`) hold the type declarations, their
  constructors, and their accessors. Every `resolve*` proc lives on the
  facade `src/resolver/main.nim`, from `resolveArgumentType` through
  `resolveFile` and the public `resolve*`.

  The facade re-exports its own submodules — but NOT the parser layer
  beneath it — so `import ../resolver/main` gives every resolved-side
  type. Consumers that also need parser or tokenizer types import those
  packages directly. Impl-count and generic-constraint checks are not
  done here — the resolver only populates a module argument type's
  impls; both live one phase up in the def analyzer
  (`analyzeDefModuleArgumentType`), for the cyclic-dependency reason in
  the comment block above `resolveModuleArgumentType`. Every resolution
  site carries `ctxType`, the enclosing definition as a parser
  `LocalType` (module | generic); `LocalType.access(context)` derives
  the `FunctionAccess` from it — `faAll` for a module's own functions,
  `faPublic` everywhere else — and `findFunctionDefs` filters by it at
  every layer. Scope lookups live with their owning type: name-keyed
  `findType` / `findModule` / `findGeneric` on `FileContext`
  (`resolver/app.nim`, the name→parser `LocalType` bridge: local defs
  first, then import bindings), identity-keyed `findLocalType` plus the
  scope-spanning `findGenericInScope` on `ResolvedFile`, and path-keyed
  `findFile` on `ResolvedApp` (the resolve-time result-and-accumulator
  whose assert enforces that an import was resolved before its
  importer).
- **Single-pass walk per app** (files arrive in dependency order,
  leaves first, from the parser's multi-file `parse*` entry, so imports
  are always resolved before use). For each file: build the
  `FileContext` (the parsed file + imported bindings, added import by
  import with duplicate-binding rejection). Then for each defined type
  resolve the data block and each function signature/body.
  Argument types along the way carry parser Module identifiers, so
  every `ResolvedModuleArgumentType` is well-formed at construction
  without any forward-reference dance.
- **Impl population, not validation** — `resolveModuleArgumentType`
  only resolves a module argument type's impls in slot order; it does
  NOT derive the module's require slots, count the impls, or check
  constraint satisfaction. All of that is the def analyzer's
  `analyzeDefModuleArgumentType`, which reads the require slots off the
  module's data block (uniformly for local and imported modules),
  raises "expects N impls but found M" on a count mismatch, and probes
  each impl by identity (`findImplDef`, finding the contract through
  the imported module's source file via `findGenericInScope`);
  `analyzeValueTypeAgainstDefType` still guards use sites. Deferring is
  forced by ASL's in-file cyclic module dependencies — see the comment
  above `resolveModuleArgumentType`.
- **Generic param-list ownership** — each data-block type derives
  its own order-preserving `generics` seq at construction:
  `ResolvedVariantDef` from its generic-typed fields,
  `ResolvedUnionDef` by merging variant requires (first-seen order
  across variants — one union scope, Rust-style shared params),
  `ResolvedStructDef` from the union of its explicit `struct(...)`
  header generics and the generics collected recursively from its field
  types (a field typed `Array[K]` contributes `K`; the constructed def
  carries no kind — nothing downstream needs to know which path
  produced it). A public module whose require slots name a non-public
  generic is rejected in `newResolvedModule`.
  `genericTypeIndex` is an on-demand projection of that seq; the
  `requires*` accessors read it directly. Use-sites never re-derive
  this list: the def analyzer reads it off the module's data block
  (`module.dataDef.requires`). No uniqueness
  rule is enforced at resolution time — the same generic name
  appearing in multiple fields is fine, since the analyzer's
  `AnalyzedImplMap` binds one generic to one concrete type per
  construction and surfaces any mismatch as a `merge()` error at
  the init site. Generic-uniqueness inside the explicit
  `struct(...)` header is the one place that *is* checked.
- **Generic signature rule** — inside a generic block, a fn
  argument/return type root may only resolve to the current generic
  itself (self-reference) or a module. Other generics are rejected
  at resolve time, keeping each generic's type world bounded.
- **Enriched Resolved* def-level types** — `ResolvedStructDef` /
  `ResolvedVariantDef` / `ResolvedUnionDef` / `ResolvedModule` /
  `ResolvedGeneric` carry the accessors later phases need:
  `findField`, `findVariant`, `findFunctionDefs(name, arity, access)`,
  `findImplDef`, plus the `funcNameArityIndex` / `funcDefIndex` behind
  them. Constructors own the module/generic invariants
  (input-signature uniqueness: a `ResolvedFunctionDef` hashes by name +
  input types, return type deliberately excluded).
- **Body-level name resolution** — the resolver walks user-function
  bodies: each statement is dispatched, each expression is resolved,
  and every function call's root (the user-typed receiver name) is
  resolved against the FileContext to a `parser.LocalType` carried on
  `ResolvedFunctionCall.typ` — so the analyzer never resolves a
  user-typed name; it does identity lookups on what the resolver
  already bound. A `FunctionContext` (`Table[Identifier, Location]`,
  `resolver/functioncontext.nim`) tracks the names of variables
  currently in scope; the value stores the declaration site so
  duplicate-declaration errors can point at the prior source
  location. Variable types remain the Analyzer's concern. The
  resolver checks that a call target exists for the name, arity and
  access, but does not pick among overloads — that's the Analyzer.
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

Two barrels split along the phase boundary. The five layers are flat
sibling packages under `src/` (pipeline order tokenizer → parser →
resolver → defanalyzer → analyzer), each with a `main.nim` barrel;
no package is physically nested inside another:

- `src/defanalyzer/main.nim` — definition-analysis barrel.
  Hosts the phase-A analyze* procs (analyzeDefGenericArgumentType →
  analyzeDefApp) and re-exports its own def-level submodules. It does
  NOT re-export the resolver layer beneath it; code here imports
  `../resolver/main as resolver` (and `../parser/main` for parser
  types) directly. `src/defanalyzer/` holds the def-level per-type
  files plus `context.nim` (the phase-A contexts).
- `src/analyzer/main.nim` — body-analysis barrel and top of the stack.
  Hosts the phase-B body walkers and the public two-pass `analyze*`
  entry; it re-exports its own body-level submodules only (the
  context ladder in `context.nim` is imported, not re-exported).
  `import ../analyzer/main` does NOT transitively reach the lower
  layers — consumers import each layer whose types they use directly.

Takes a `ResolvedApp` and returns an `AnalyzedApp` — a type-rich view
of every value, expression, and statement in each function body.
**Two passes** (see plans/plan_analyzer_two_pass.md):

**Pass A — definitions** (`analyzeDefApp`). Walks every file →
every module + generic → every struct/union/literal block → every
funcDef signature → every user-function statement across the whole
app, producing an `AnalyzedDefApp`: per-file `AnalyzedDefFile`
(analyzed imports (`AnalyzedDefImport`) + defined types + the
identity-keyed `ResolvedFileContext` as its `scope`), per-def
`AnalyzedDefModule` (whose `functions` are tagged `AnalyzedDefFunction`s
— extern / user / generated, each carrying its pre-analyzed
`AnalyzedFunctionDef`; user functions additionally carry their
`AnalyzedDefStatement` tree) / `AnalyzedGeneric` (bare
`AnalyzedFunctionDef`s — generics have no extern/user split) and the
data-block wrappers (`AnalyzedStructDef` / `AnalyzedVariantDef` /
`AnalyzedUnionDef` / `AnalyzedLiteralDef` / `AnalyzedDataDef`). The
statement walk mirrors the resolver's statement cluster 1:1
(`AnalyzedDefLiteral` → kwargs → fncalls → initializers → match →
expression → statement, hosted in `defanalyzer/statement.nim` with the
`AnalyzedStructRef` / `AnalyzedUnionRef` wrappers in
`defanalyzer/refs.nim`), re-binding each def-level fact (literal
default module + LiteralDef, call receiver, struct/union defs behind
refs) from the file scope. The app walk accumulates file defs in a
`ResolvedAppContext` (`defanalyzer/app.nim`, wrapping the
`ResolvedApp`); the result `AnalyzedDefApp` is just the fileDefs + a
path-keyed `fileDefIndex` behind `findFileDef` — all type lookup state
lives on the per-file scopes. Any def-site error fires here before any
body walker touches the AST.

Three phase-A invariants worth naming:

- **One context value, no twins.** Phase-A walkers carry a single
  `ResolvedTypeContext` (enclosing resolved module | resolved
  generic, `defanalyzer/context.nim` — the resolved-rung counterpart
  of the resolver's `ctxType: LocalType`), consumed for exactly one decision:
  function visibility during constraint satisfaction. Everything
  else context-sensitive (e.g. the generic self-reference rule) was
  already enforced at resolve time, so there are no module/generic
  proc twins — one context value, one proc.
- **Deep constraint satisfaction** (`analyzeDefImpl`, called by
  `analyzeDefModuleArgumentType` AND by the phase-B generic value
  check — one shared routine). For each impl↔require pair, the
  require-slot generic's funcDefs are concretized at DEFINITION
  level — self-references become the impl's self shape (`A[B, C]`
  built from its own require slots via the deep `concrete`, not the
  site-bound impls, which the recursive argtype walk validates
  separately) — and each concretized def is probed by IDENTITY
  against the impl's funcDefIndex through
  `ResolvedTypeContext.findImplDef`, which owns the visibility
  decision (module impl → `access(module)`: `faAll` only from inside
  that module; generic impl → `faAll`). Hash = name + input types
  (input-signature uniqueness rule; return type and access are checked
  explicitly on the hit). Satisfaction is a binding-independent
  property of the module, decided by one index probe per required def
  — an impl with a mismatched signature is rejected at its declaration
  even if the function is never called. Phase B's
  `analyzeValueTypeAgainstDefType` generic arm runs this same check, so
  the value-position check is visibility-aware too.
- **Identity lookups assert, never err — on the types themselves.**
  Every identity-keyed lookup (`findType` / `findModule` /
  `findGeneric` on `ResolvedFileContext`, `ResolvedFile.findLocalType`,
  `ResolvedFile.findGenericInScope`, `ResolvedApp.findFile`,
  `AnalyzedDefFile.findType`, `AnalyzedDefApp.findFileDef`,
  `AnalyzedDefModule.findFunctionDef`) returns its value directly
  with an `assert "[BUG] - ..."` inside: by construction callers can
  only ask about identities the layer below bound, so a miss is a
  compiler bug and no caller consumes an error path. The split is
  principled — name-keyed lookups (resolve time, `findVariant`,
  `findFunctionDefs`, `findImplDef`) keep `Result` because user
  errors genuinely surface there; constraint-check failures are the
  def analyzer's own user errors. The exported walker surface is
  deliberately narrow: `analyzeDefApp` (the pass entry),
  `analyzeDefArgumentType`, and `analyzeDefImpl` (reused by phase B's
  generic value check); every other walker is private to the barrel.

**Pass B — bodies.** Phase B threads one context value per walker,
a nested ladder in `analyzer/context.nim`:

    AnalyzedFileContext  ←  AnalyzedModuleContext  ←  AnalyzedUserFunctionContext

`analyzeFile` builds the `AnalyzedFileContext` from the `AnalyzedDefApp`
+ this file's `AnalyzedDefFile`: imported types map to their analyzed
twin from the SOURCE file (`appDef.importedTypes(imp)`), local types go
through the file's own def bundle (`fileDef.findType`).
`analyzeModule` wraps it in an `AnalyzedModuleContext` (+ the enclosing
`AnalyzedDefModule`), and `analyzeUserFunction` in an
`AnalyzedUserFunctionContext`, which adds the variable scope
(`Table[Identifier, AnalyzedBinding]`, seeded from the function's
args), `returns` (the declared return type, which a `try` call checks
its error type against), `update` (extend the scope with a statement's
or case pattern's bindings) and `branch` (a child scope per case arm,
so arm bindings don't leak). Each rung delegates `findType` /
`findModule` down. Call sites read pre-analyzed funcDef signatures via
`funcCtx.findType(fncall.typ).findFunctionDefs(name, arity, access)` —
no re-analysis of arg types or return types per call site. Body-level
analyzed types back-reference the phase-A defs that produced them
(`AnalyzedFile.def` / `AnalyzedModule.def` / `AnalyzedStatement.def`;
extern functions carry their `AnalyzedExternFunction`). Scope:

- **Identity-based lookups only** — the analyzer never resolves a
  user-typed name. Every reference reaching it already carries the
  identity the layer below bound: function-call roots are resolved
  to a `parser.LocalType` at resolve time (`ResolvedFunctionCall.typ`);
  argument types carry their parser Module/Generic. Each layer's
  per-file scope answers "given what the layer below handed me,
  find my enrichment of it" (the resolver rung is name-keyed; the two
  identity rungs hash by source location):

      resolver     FileContext           Identifier   → parser.LocalType
      defanalyzer  ResolvedFileContext   parser.LocalType  → ResolvedLocalType
      analyzer     AnalyzedFileContext   ResolvedLocalType → AnalyzedLocalType

  Aliased imports (`import { u8 as Byte }`) can never miss.
  Bare-literal defaults are bound at resolve time too
  (`resolveLiteral` looks up `Literal.defaultType` — "i32"/"f32"/
  "string" — against the FileContext and stores the parser.Module on
  `ResolvedLiteral.default`); phase A carries the resolved default as
  an `AnalyzedModuleArgumentType` on `AnalyzedDefLiteral.default`,
  which phase B's `analyzeBareLiteral` reads directly (module-argtype
  throughout — no re-wrapping). See
  plans/plan_identity_based_lookups.md and
  plans/plan_alias_lookup_cleanup.md.
- **One context per walker, minimal params** — phase A threads
  `(fileCtx: ResolvedFileContext, typeCtx: ResolvedTypeContext, ...)`
  and stores the file context on `AnalyzedDefFile.scope`; phase-B body
  walkers take a single `funcCtx: AnalyzedUserFunctionContext` (module
  and file walkers the rung above it). Wider contexts stay off the
  signatures: the app appears only in the file walks, where it is the
  subject (`analyzeDefApp` / `analyzeDefFile` / `analyzeDefImport` via
  `ResolvedAppContext`; `analyze*` / `analyzeFile` via
  `AnalyzedDefApp`). `AnalyzedDefFile.findType` stays local-only by
  design — an imported type's analyzed twin is fetched through the
  SOURCE file's fileDef, so the name must be DEFINED there, not merely
  visible.

- **Overload selection** — `analyzeArgumentList` analyzes the call's
  arguments against each candidate funcDef (the candidate's declared
  arg types are the `expected` context), then matches each argument
  type against its declared type via `analyzeValueTypeAgainstDefType`,
  accumulating an `AnalyzedImplMap` with `merge`. The unique survivor
  is picked; no match or more than one is rejected with every
  candidate's error listed.
- **Value-vs-def matching** — `analyzeValueTypeAgainstDefType` walks a
  value type and a declared type in lockstep and PRODUCES the generic
  bindings: module vs module must be the same module, recursing into
  each impl slot; a def-side generic binds `generic → valType` (after
  the `analyzeDefImpl` constraint check); a def-side module against a
  value-side generic is rejected. `merge` enforces one concrete type per
  generic per construction.
- **The impl map is the type's impls** — an
  `AnalyzedModuleArgumentType`'s `impls` IS its `AnalyzedImplMap`
  (`OrderedTable[ResolvedGeneric, AnalyzedImpl]`, `AnalyzedImpl` = the
  bound argtype + the concretized contract defs), built once in
  `analyzeDefModuleArgumentType` and kept in slot order, so consumers
  (a match subject, a `try` call's `Status` slots) read bindings
  straight off the type. `concrete(argType, implMap)` (in
  `defanalyzer/argtype.nim`) rewrites funcDef return types and
  variant-field types through it — single-pass and deliberately not
  chained, so independent generics stay independent.
- **Initializer parametric inference** — struct and union initializers
  seed the map with the ref's explicit impls (`Pair[u8] { ... }`), walk
  their kwargs (`analyzeKeywordArgument` checks each value against its
  field type and carries the bindings it contributes), and `merge`
  them across fields, so kwargs binding the same generic must agree.
  A union initializer then rebuilds the map over the union's full
  require slots: covered slots bound, uncovered ones left as the free
  generic (leave-as-is).
- **`try` calls** — `analyzeFunctionCall`'s `fckTry` arm requires the
  callee to return `Status`, reads its `(Value, Error)` slots
  (`statusSlots`), requires the enclosing function to return a
  `Status` with the same error type, and evaluates to `Value`
  (`newAnalyzedTryFunctionCall`, kind `afckTry`).
- **Literal validation** — literal text is parsed eagerly at parse
  time; `ResolvedLiteralDef.validate` (`resolver/datadef.nim`) fits a
  value against its target via `validateInteger` / `validateFloat` /
  `validateString` (`parser/literals.nim`), covering all eight integer
  kinds, `f32` / `f64`, and `string`. `analyzeBareLiteral` and
  `analyzeLiteralInitializer` route through it.
- **Bare-literal contextual defaulting** — bare literals (`x = 10`,
  `f(1)`, `Struct { field: "data" }`) parse as `iekLiteral` inline
  expressions and reach the analyzer typeless. `analyzeExpression`
  takes an `expected: Option[AnalyzedArgumentType]` from every
  caller; the `adekLiteral` arm dispatches through `analyzeBareLiteral`,
  which picks a concrete type by rule: `some(module)` → adopt (an error
  if that module is a struct/union); `some(generic)` or `none` →
  default to `i32` / `f32` / `string`. The value is then fit-checked
  and wrapped as an `AnalyzedLiteralInitializer` under `aekInitializer`,
  so no downstream site sees an untyped bare literal. Defaults must
  be in scope — `@std` auto-injection handles this for every `.asl`
  file. Concrete positions thread `expected` from the callee's
  declared arg types (per-candidate for overloads), the struct/
  union kwarg's field type, and the getter-assignment RHS's field type.
- **Match checking** (`analyzer/pattern.nim`) — a variable pattern is
  allowed only in the last case. Union matches reject duplicate
  variants and must cover every variant unless that trailing variable
  pattern catches the rest (`hasUncoveredCases`; the catch-all is itself
  rejected when the variants are already covered). Integer matches
  require the trailing variable pattern, and
  `checkDuplicate[T: SomeInteger]` rejects duplicate integer patterns
  across all eight integer kinds. Float / string subjects are rejected.
  Every case arm must yield the same type (`verifyUniformReturnType`).
- **Body-level constructs** — getter (struct-shaped property read),
  case patterns (`AnalyzedCasePattern`: `acpkUnion` / `acpkInteger` /
  `acpkVariable`), statements (none / variable / getter targets; a
  getter statement's RHS adopts and must match the field type), match
  expressions with case-arm bindings, struct + union initializers,
  literal initializers, `try` calls. A function body's last statement
  must have the declared return type.
- **Pattern-side bindings** — `AnalyzedBinding` is a tagged union
  (`abkVariable` over an `AnalyzedVariable`, `abkVariantField` over an
  `AnalyzedVariantField` whose type is concretized through the
  subject's impl map); `AnalyzedUnionPattern.bindings` and the
  function scope both hold it.
- **Scope tables** — `ResolvedFileContext` (`defanalyzer/context.nim`,
  a `Table[parser.LocalType, ResolvedType]` whose entries are
  local | imported) and `AnalyzedFileContext` (`analyzer/context.nim`)
  both span imports + local defined types; the same type imported under
  two bindings lands on one key, so construction only rejects a
  genuinely different entry under an existing key. The variable scope
  on `AnalyzedUserFunctionContext` is keyed by `Identifier` —
  variables have no identity beyond their name, so name keying is
  correct there.

The remaining gaps are listed in **What's Next**.

### Phase 6: Monomorphization

`src/monomorphize.nim` — the first pass past the front end: consumes
`AnalyzedApp`, specializes every generic into concrete copies driven
demand-first from the fully-concrete entry (`app.entry`, so a *built*
program must expose a `public func start(): i32`), and returns a
`MonoApp`. Key pieces:

- **Two `distinct int` id spaces** — `FunctionId` (one function copy,
  program-global) and `ValueId` (a value inside one copy, from zero).
  They never cross.
- **`FunctionRef = (module, concrete function, impls)`**, a tagged union
  over `frkUser | frkExtern | frkGenerated`, names one copy
  call-site-independently, so a recursive call's ref repeats and the memo
  (`visiting` / `visited`) closes the cycle — equal refs build once.
- **Per-copy node IR** — a body lowers to a `seq[Node]` (`nkCall` /
  `nkMatch` / `nkTry` / `nkLiteral` / `nkUnion` / `nkStruct` /
  `nkVariantField` / `nkStructField` / `nkStructSetter`); a variable is
  not a node (resolves through the scope's `argMap`). Match arms own
  their body nodes via a `branch` scope, so pattern bindings and
  field projections only evaluate when the arm is taken; a field setter
  is a functional update that rebinds the source variable.
- **Generic-target calls** (`Shape.sides(x)` through a bare generic)
  resolve to the concrete impl: look the generic up in the call's
  combined impls, translate the funcDef through each `AnalyzedImpl.defs`
  index (chaining when one generic satisfies another), then dispatch the
  concrete call. So no generic survives to codegen.
- **`MonoApp = { instances: Table[FunctionId, MonoInstance], entry }`** —
  every copy keyed by id; a `MonoInstance` is a user body
  (`MonoUserFunction`: params + nodes + result id) or an extern
  declaration (`MonoExternFunction`: decl + impls). No dangling callees.
- **Termination** — a 128-deep stopgap rejects type-growing recursion
  (`grow[T] → grow[Array[T]] → …`) before it overruns the stack;
  `TODO(growth-check)` tracks the precise subterm occurs-check.
  `afkGenerated` is a `[BUG]` assert (unreachable until the `try`→`match`
  expansion exists); `TODO(extern-generic-wrapper)` is the codegen-side
  kind-tagged wrapper for a generic extern.

`compile` runs this pass but discards the `MonoApp` (no codegen yet).
Design + decisions: `plans/plan_monomorphizer.md`,
`plans/plan_monomorphization.md`, `plans/plan_execution_model.md`.

## Project Structure

```
src/
  asl.nim              entry point — the `build` command pipeline; `lsp`
                       hands off to lsp/main.nim
  cli.nim              CLI parsing via argparse (`build` / `lsp`,
                       --vendor, --indent-width, …)

  lsp/                 `asl lsp` — language server over stdio (plans/plan_lsp.md).
    main.nim           barrel + stdio loop (read frame → decode → handle → write)
    server.nim         LspServer state + pure `handle`; compiles each open
                       document as a root with open buffers as overlays
    message.nim        LspMessage tagged union decoded from JSON-RPC
    diagnostic.nim     compiler error string → Diagnostic (ordered shapes)
    jsonrpc.nim        Content-Length framing + response/notification builders
    documenturi.nim    file:// URI ↔ absolute path

  # Five flat sibling packages — the compiler pipeline, in order. Each
  # is a package with a `main.nim` barrel that re-exports its OWN
  # submodules; the only cross-layer re-export is the parser's re-export
  # of the tokenizer. A consumer imports each layer whose types it uses.

  tokenizer/           Phase 1 — lexing.
    main.nim           `tokenize` driver: ordered token specs → seq[Token];
                       Trojan-Source defense; synthetic trailing newline
    spec.nim           TokenSpec / TokenSpecMatcher + the ordered
                       TOKEN_SPECS matchers
    constants.nim      Punctuations, lexeme constants, Trojan-Source
                       codepoint tables (bidi / zero-width / invisible)
    token.nim          Token + TokenKind (tkPunctuation, tkSpace, tkNewline,
                       tkIdentifier, tkInteger, tkFloat, tkString, tkComment)
    location.nim       Location (filepath:line:col) + advance

  parser/              Phase 2 — recursive-descent parse into the AST.
    main.nim           barrel: re-exports every module below; file-level
                       grammar (.asl / .aslr) and the multi-file `parse*`
                       entry point (DFS walk, cycle detection, overlays)
    parser.nim         Parser, ParserError, Spec[T] + combinators, leaf
                       specs; re-exports the tokenizer
    identifiers.nim scalars.nim literals.nim getter.nim importpath.nim
    imports.nim argtype.nim refs.nim datadef.nim pattern.nim
    statement.nim function.nim generic.nim module.nim types.nim app.nim
                       per-concept AST modules (type + constructor +
                       accessors + grammar specs); constructors enforce
                       invariants
    decorator.nim      decorator sugar
    expansion.nim      ANF expand procs (reference only, not imported)

  resolver/            Phase 4 — name resolution → ResolvedApp.
    main.nim           facade: every `resolve*` proc; re-exports its own
                       submodules (NOT the parser layer)
    argtype.nim datadef.nim function.nim refs.nim statement.nim
    types.nim imports.nim indexing.nim
                       resolved-side types by cluster
    app.nim            FileContext (name-keyed scope), ResolvedFile,
                       ResolvedApp
    functioncontext.nim  FunctionContext (variable names in scope)

  defanalyzer/         Phase 5A — definition analysis.
    main.nim           phase-A analyze* procs (analyzeDefGenericArgumentType
                       → analyzeDefApp); re-exports its own submodules
    argtype.nim datadef.nim function.nim statement.nim types.nim
    refs.nim importdef.nim
                       def-level analyzed types (+ AnalyzedImplMap,
                       merge / concrete in argtype.nim)
    context.nim        ResolvedFileContext + ResolvedTypeContext
    app.nim            AnalyzedDefFile, AnalyzedDefApp, ResolvedAppContext

  analyzer/            Phase 5B — body analysis, top of the stack.
    main.nim           phase-B body walkers + public two-pass `analyze*`
    pattern.nim statement.nim function.nim module.nim app.nim
                       body-level analyzed types (AnalyzedApp in app.nim)
    context.nim        AnalyzedFileContext → AnalyzedModuleContext →
                       AnalyzedUserFunctionContext

examples/
  base.aslr            standard library (extern fns) — default `std` vendor
  *.asl                positive test fixtures
  errors/*.asl         negative test fixtures (each documented)
  actor.c allocator.c  hand-written reference C (actor runtime, allocator)

tests/
  config.nims          sets the search path to `$projectDir/../src`
  tutils.nim           shared helpers (tokenize / parse / resolve / analyze
                       over in-memory strings + temp dirs)
  all.nim              aggregator that imports test_*.nim
  test_tokenizer.nim   tokenizer unit tests
  test_combinators.nim Spec / combinator unit tests
  test_ast.nim         AST constructor invariants (covers src/parser/)
  test_grammar.nim     single-file parse tests across the grammar specs
  test_loader.nim      multi-file load order, cycles, import-path
                       fallbacks, parent escape, vendor injection, overlays
  test_resolver.nim    end-to-end resolver tests
  test_analyzer.nim    end-to-end analyzer tests
  test_monomorphize.nim  monomorphizer: lowering paths, generic dispatch,
                       occurs-check, extern instances
  test_cli.nim         CLI parsing tests (--vendor flag, lsp command, etc.)
  test_lsp.nim         LSP error mapping, URI/message decoding, `handle`

tooling/vscode-asl/    VSCode extension: TextMate grammar + `asl lsp` client
.vscode/tasks.json     Cmd+Shift+B `asl build` task with problem matchers

test.sh                regression runner (exit-code based)
plans/                 design plans (plan_*.md) + DAG-IR step sketches
                       (dag_ir_core.nim, phase_*.nim; plan_dag_ir.md)
grammar.md             source-of-truth domain grammar
documentation.md       user-facing language reference
validations.md         catalogue of enforced validations, by phase
lessons.md             design retrospective
overview.md            this file
```

Cross-layer imports are relative-path with the barrel — e.g.
`import ../parser/main as parser`, `import ../resolver/main as
resolver`. Each barrel re-exports its own submodules; the one
cross-layer re-export is `parser/parser.nim` re-exporting the
tokenizer (so `import ../parser/main` also brings `Location` /
`Token`). Beyond that a consumer imports every layer whose types it
uses directly (there is no single "import the top and get everything"
barrel). There is no `nim.cfg`; the tests set their search path via
`tests/config.nims`.

## Design Patterns

**Result[T, E] error handling** — all fallible operations return
`Result`. Chained with `?` for early return. Error messages carry
`file:line:col`. The `[ERROR] -` prefix is added only at the
display boundary (`asl.nim`), not in library code.

**Private fields + readonly accessors** — types are `ref object`
with unexported fields. Public accessor procs (`proc name*(m): T`)
provide readonly access. Variant-field accessors assert the kind
before returning (`assert(db.kind == ddkStruct, ...)` in
`DataDef.struct`).

**Tagged unions** — `InlineExpression`, `Expression`, `Statement`,
`DataDef`, `Initializer`, `CasePattern`, `FunctionCall`, `Function`,
`LocalType`, `File`, `Import`, `ImportPath` (and their resolved /
analyzed twins) all use `case kind:` discriminators with exhaustive
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
monomorphize, CLI, LSP) has its own `test_*.nim` file aggregated by
`tests/all.nim`. **405 tests** covering positive paths, negative
paths, edge cases, Trojan Source defenses in the tokenizer, direct
rollback / composition tests for the combinators, multi-file loading
(cycles, diamonds, source overlays), and the language server's error
mapping and message handling.

`./test.sh` — integration suite that builds the binary and runs
`asl build` against every fixture, asserting exit codes:

- **Positive** (`examples/*.asl`): must exit 0
- **Negative** (`examples/errors/*.asl`): must exit non-zero

Each fixture has a leading `#` comment documenting what feature or
error condition it exercises. `test.sh` drives 36 fixtures (21 positive
+ 15 negative; `dep.asl` and `cycle_b.asl` in `examples/errors/` are
dependency files the runner skips). Current result: **35/36** —
`mini_actor6.asl` now fails because `compile` runs `monomorphize`, which
drives from `app.entry` and so requires a `public func start(): i32`
that this fixture (an actor-library example) does not declare. Wiring
monomorphize into the build regressed this one positive fixture; the fix
is either to give it an entry or to exclude it from the built set.

## What's Next

**Front end green; monomorphizer landed.** tokenizer → parser →
resolver → defanalyzer → analyzer → monomorphize runs end to end, and
`compile` returns `[SUCCESS]` once monomorphization does. Unit suite
**405/405**; integration **35/36** (the one failure is `mini_actor6.asl`
— see Testing). Recent structural work: the collapse of the assignment /
setter / bare-expression forms into one `Statement` at every layer with
value positions typed `InlineExpression`; the phase-B context ladder
(`analyzer/context.nim`) replacing the separate import and app contexts
of phase B; the (fileId, typeId, functionId) identity path on resolved
entities; two-parameter `Status[Value, Error]` with `T!` sugar and the
`try` operator; the single-DFS multi-file walk in `parse*`; and the
removal of the dead WIP codegen and lifetime skeleton from `src/`.
Earlier arcs are recorded in plans/plan_analyzer_two_pass.md,
plans/plan_identity_based_lookups.md,
plans/plan_alias_lookup_cleanup.md and plans/plan_filescope_threading.md.

**Current arc — lifetime → codegen** (monomorphize has landed;
plans/plan_monomorphization.md):

    analyze (AnalyzedApp)
      → monomorphize          specialize generics into a MonoApp (landed)
      → lifetime / ownership  on the concrete IR; in-place vs copy
      → codegen               C now; Verilog/VHDL later

Monomorphization runs after analysis (concrete argtypes and each impl's
concrete contract defs are available) and is driven demand-first from
the fully concrete `start`, so no generics survive to codegen — a hard
requirement of the hardware target. Build order (each step ships
correct; later steps only remove copies):

1. **Monomorphize** — **landed** (`src/monomorphize.nim`): memoized by
   `FunctionRef`, every expression/statement kind lowered, generic-target
   calls resolved to concrete impls, user + extern copies in the
   `MonoApp`. The strictly-growing guard is currently the depth-cap
   seatbelt (128); the precise subterm occurs-check is
   `TODO(growth-check)`.
2. **Conservative memory** — always shallow-copy structs, always
   persistent Array/Map; no ownership analysis yet.
3. **Struct in-place** (optional) — mutate unique structs instead of
   copying, or keep structs always-copy.
4. **Transient marking** for Array/Map — the must-be-unique analysis on
   the value graph flips provably-unique ops to in-place.
5. **Formal obligations** (`@requires unique`) once the ACSL layer
   exists.

Open decisions in the plan: whether structs get an in-place path at
all; type vs. code-only monomorphization (structs/unions are
pointer-backed, so only size/clone/dispatch code may need duplicating);
the collection capacity model for HDL; and the boundary serialization
format. The value-graph / DAG-IR design downstream of this is
plans/plan_dag_ir.md.

**Editor tooling.** `asl lsp` (phase 0, live diagnostics) and the
VSCode client are in; the roadmap and open items are in
plans/plan_lsp.md, tagged at their code sites as `TODO(parser-errors)`
(report the furthest parse failure, not the last alternative tried),
`TODO(structured-errors)` (structured location + message errors across
all layers, retiring the string parsing), `TODO(lsp-error-shapes)` and
`TODO(lsp-stale-edits)`.

Focused TODOs still open:

- **Equality vs unification for analyzed types**
  (`defanalyzer/argtype.nim`, the hash-based `==` on
  `AnalyzedArgumentType`). Several assignability checks still compare
  with `==` / `!=` rather than unifying: `verifyUniformReturnType`
  (case-arm uniformity), the last-statement return check in
  `analyzeUserFunction`, the getter-statement field check in
  `analyzeStatement`, and `merge`'s same-key conflict check. A
  still-free generic (e.g. an uncovered union slot left as-is) then
  compares unequal to the concrete type it should unify with. No
  current fixture trips it. Fix is to route every assignability check
  through `analyzeValueTypeAgainstDefType` + a unifying `merge`. Owned
  by plans/plan_deferred_typing.md.

  Independent generics are deliberately NOT collapsed into each other:
  a map like `{Sample → K, K → u8}` is correct as-is — `Box[Sample, K]`
  concretizes to `Box[K, u8]`, keeping `Sample` bound to `K`. (An
  earlier draft flagged a "substitution chain" bug here; that was a
  misdiagnosis — flattening the chain would wrongly couple two
  independent parameters.)
- **Two generic-substitution engines (resolver vs analyzer).** The
  "instantiate generics into a parameterized type" operation exists
  twice, over two type universes:
  - resolver: `concrete(argType, subst: ResolvedImplMap)`
    (`resolver/argtype.nim`, a `Table[Generic, ResolvedArgumentType]`),
    reached via `ResolvedGeneric.concrete` with a one-entry map. Used
    at DEFINITION time to ground contract funcDefs before the
    `findImplDef` identity probe.
  - analyzer: `concrete(argType, implMap: AnalyzedImplMap)`
    (`defanalyzer/argtype.nim`), keyed by `ResolvedGeneric`. Used at
    USE time (call returns, initializer results, match fields).
  Both are map-based and single-pass (deliberately not chained), but
  they are maintained separately and must keep agreeing on
  substitution semantics; full consolidation is hard (different type
  universes), and the fork is a latent-soundness liability worth
  naming.
- **Inconsistent absence contract across the `find*` family.** The
  intended rule (user error → `Result`, compiler invariant → `assert`)
  is real but spelled unevenly: `findFunctionDefs` → `Result`,
  `findFunctionDef` → assert-returning bare value; `ResolvedUnionDef`
  has BOTH a `Result` `findVariant` (by name) and an assert-returning
  one (by `VariantDef`) under one name; `findType` is `Result` on the
  resolver's `FileContext` and asserting on `ResolvedFileContext` /
  `AnalyzedDefFile`. A reader can't predict a `find*`'s failure mode
  from its signature. Low risk, but a legibility debt; worth a naming
  convention (e.g. `tryFind*` returns, `find*` asserts).
- **Fabricated sentinel locations.** `newLocation()` (a 1:1 sentinel
  with an empty filepath) is minted at 5 sites: the auto-injected
  `@std` import in `parser/app.nim` (2), `ResolvedModule.self` in
  `resolver/types.nim` (2), and `AnalyzedGenericArgumentType.self` in
  `defanalyzer/argtype.nim`. Any diagnostic built from a reconstructed
  self-type points nowhere. No current consumer renders these locs;
  fix when one does — the self shape should carry the use site's loc.
  (`resolver/imports.nim` has a related `TODO` on
  `newResolvedImportedType`'s locations.)
- **`AnalyzedDefImportedType` stores the twin twice** — `typ` and
  `resolved.localType` are the same object arriving via two
  different derivations (`analyzeDefImportedType`'s
  `impFile.findLocalType` re-lookup vs the resolve-time capture on
  `ResolvedImportedType`), with no assert tying them. Either derive
  `typ` from the binding or assert the tie in the constructor.
- **Diagnostics polish.** The case-arm mismatch in
  `verifyUniformReturnType` still returns a `todo:` placeholder
  message; the uncovered-cases errors in `analyzer/pattern.nim` don't
  name the missing variants (two `TODO`s); `MatchExpression.kind` is
  set at parse time but never read (`TODO` in `parser/statement.nim`);
  and float-literal precision warnings go straight to stderr
  (`TODO(diagnostics)` in `parser/scalars.nim`).
- **Redundant constraint re-checking — PERFORMANCE, revisit after
  codegen.** The def-time constraint check in
  `analyzeDefModuleArgumentType` runs at every occurrence of a
  parameterized argument type: every field, every funcDef
  arg/return, every ref/initializer in the statement walk. Because the
  check compares at DEFINITION level, its verdict is a constant per
  `(impl root, contract generic, access)` triple — a file writing
  `Array[u8]` fifty times derives the same fact fifty times. The
  natural fix is a per-app memo keyed on that triple (access has
  only two values); it needs a home that respects the pure-proc
  discipline, which is why it is deliberately deferred rather than
  bolted on. The same theme runs through the analyzer — phase B
  re-concretizes per call — so this line item stands in for a
  dedicated caching pass over the whole pipeline.
  Priority order is settled: memory-safe C code generation first,
  then the performance pass.
