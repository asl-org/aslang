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
  mark them as exported. A non-public function is module-internal:
  callable and able to satisfy a generic constraint only from inside
  the module that defines it; every other context (another module,
  any generic block) sees public functions only
- **Comments**: line comments starting with `#`

### Built-in Types

Fixed-width integers: `i8`, `i16`, `i32`, `i64`, `u8`, `u16`,
`u32`, `u64`. Floats: `f32`, `f64`. Text: `String`. Containers:
`Array`, `Bitset`. Fallibility: `Status[T]` + `Error`. System
namespace: `System` — a function-only module. Modules without a
data block are pure namespaces: their functions are callable
(`System.println(...)`) but the module itself is not a value and
cannot appear as an argument or return type.

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
  │                          per-file typeIndex over locally-defined
  │                          types + importedNameIndex over
  │                          explicit-import bindings)
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
  │              that need the resolved module do an identity-keyed
  │              lookup at their site (`fileCtx.findModule(module)`
  │              on either FileContext rung, or
  │              `ResolvedFile.findModule` — assert-backed direct
  │              returns; keys hash by source location, so aliased
  │              imports can never miss).
  ▼
Analyzer ──── Two-pass over the resolved app.
  │
  │              Pass A (analyzeDefApp) — walks every file,
  │              every module + generic, every struct/union/literal,
  │              every funcDef AND every user-function statement
  │              across the whole app. Produces AnalyzedDefApp
  │              bundling per-file AnalyzedDefFile + per-module
  │              AnalyzedDefModule + per-def
  │              AnalyzedFunctionDef (args + return type
  │              fully analyzed) + per-function AnalyzedDefStatement
  │              trees (every def-level fact in a body — literal
  │              defaults, call receivers, struct/union refs —
  │              re-bound to its resolved def). Any def-site error
  │              surfaces here before any body walker runs — the
  │              guarantee that phase A gives.
  │
  │              Pass B — walks function bodies. Consumes phase-A
  │              results: analyzeFunctionCall looks up its overload
  │              candidates via the per-file AnalyzedFileContext
  │              (`fileCtx.findType(typ).findFunctionDefs(name,
  │              arity, public)`) returning
  │              seq[AnalyzedFunctionDef] — no re-analysis
  │              at the call site. Return types come pre-analyzed
  │              from matchingFuncDef.returns; only the
  │              generic-impl substitution (.concrete) runs per
  │              call. Union initializer parametric inference reads
  │              the flattened StructRef / UnionRef analyzedImpls
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
carries its `AnalyzedDefFile` back-reference (the phase-A
output that produced it), analyzed import definitions, and the
analyzed modules parsed out of it.

Phase-A output (`AnalyzedDefApp` + per-file
`AnalyzedDefFile` + per-module `AnalyzedDefModule` +
`AnalyzedGeneric` + `AnalyzedFunctionDef` + the data-block
wrappers `AnalyzedStructDef` / `AnalyzedVariantDef` / `AnalyzedUnionDef` /
`AnalyzedLiteralDef` / `AnalyzedDataDef`) is threaded through the
body walker chain as `(appDef, fileDef, fileCtx)` — the
`AnalyzedFileContext` built at `analyzeFile` entry spans imports +
local types, so phase-B overload resolution reads pre-analyzed
funcDef signatures via `fileCtx.findType(typ).findFunctionDefs(...)`
— no re-analysis of arg types or return types at call sites.
`AnalyzedApp` is the handle downstream codegen will thread through.

There is no separate `Validator` phase. Every uniqueness / structural
rule the validator used to enforce (duplicate names, empty blocks,
import collisions, duplicate fields/variants) is now a precondition
inside an AST constructor (`newStruct`, `newUnion`, `newModule`,
`newFile`, etc.). Invalid AST nodes cannot be constructed, so no
separate validation pass is needed.

### Phase 1: Tokenization

`src/analyzer/defanalyzer/resolver/parser/tokenizer.nim` (barrel) + `src/analyzer/defanalyzer/resolver/parser/tokenizer/`

Single-character classifier. Intentionally simple — no keywords, no
multi-character tokens. All that complexity lives in the parser.
Produces `seq[Token]` where each token carries `kind` (punctuation,
space, newline, alphabet, digit, utf8), `value` (the character), and
`Location` (filepath:line:col).

Security: validates UTF-8 encoding and rejects bidirectional control
codepoints, zero-width characters, and invisible Unicode (Trojan
Source defense).

A synthetic trailing newline token is appended to every token stream,
so parsers can rely on "statement ends with a newline" holding for
the last line of a file with no terminating newline.

### Phase 2: Parsing

`src/analyzer/defanalyzer/resolver/parser.nim` (barrel — hosts the combinator layer
plus shared leaf specs and the multi-file `parse*` entry point) +
`src/analyzer/defanalyzer/resolver/parser/` (per-concept AST modules — see the
Project Structure table for the current listing) +
`src/analyzer/defanalyzer/resolver/parser/tokenizer.nim` +
`src/analyzer/defanalyzer/resolver/parser/tokenizer/` (nested tokenizer barrel +
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
  defined `LocalType` = module or generic).
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
`findType(name): LocalType` (local defs only) and
`findImportedName(name): ImportedType`. The historical `Type` umbrella
(`tkImported | tkDefined`) was retired — every downstream caller
already unwrapped it, so the union was ceremony that leaked through
the public API.

### Phase 4: Resolution

`src/analyzer/defanalyzer/resolver.nim` (facade — hosts the per-type `resolve*`
procs and cross-cluster scope lookups) + `src/analyzer/defanalyzer/resolver/`
(per-type files; see the Project Structure table for the current
listing) + the nested `src/analyzer/defanalyzer/resolver/parser/` subtree
(Phase 2).

Returns a `ResolvedApp` containing a `ResolvedFile` per source file,
which in turn holds resolved imports plus a `ResolvedLocalType` for each
module/generic. Body-level name resolution is complete (variables,
getters, function calls, initializers, match/case patterns). The
resolver also enforces the structural `struct(...)`-header
constraints (unique generics in the header — enforced by
`validateRequiresNameConflict` inside `newStructDefHeader`; struct can't
carry generic fields when the header is present — enforced in
`resolveStructDef` around line 409), runs the arity +
generic-constraint checks on every impl list (task 7 moved these here
from the analyzer), resolves struct/union refs into provably valid
shapes at ref-resolve time (`ResolvedStructRef` carries the
receiver's `ResolvedModuleArgumentType` + its `StructDef`;
`ResolvedUnionRef` additionally its `UnionDef` + the referenced
`VariantDef` — wrong-kind receivers and unknown variants rejected on
the spot), field-maps initializer kwargs
(`resolveKeywordArguments` resolves the expressions in source order;
unknown/duplicate fields, undersupply, and canonical field ordering
are owned by the initializer constructors — one shared shape for
struct and union), and binds every bare literal's
default module against the FileContext (`ResolvedLiteral.default` —
same resolve-time binding as `ResolvedFunctionCall.typ`). Scope:

- **File layout — one file per resolved type, actor procs on the
  facade.** The per-type files hold only the type declaration, its
  constructor, and its accessors. Every cross-type `resolve*` proc
  (plus the scope-lookup helpers that need to cross cluster
  boundaries) lives on the facade `src/analyzer/defanalyzer/resolver.nim`; per-type
  files never import each other transitively via the resolve chain.
  See the Project Structure table for the current file listing —
  `argdef` / `argtype` / `moduleargtype` / `genericargtype` /
  `filescope` / `functionscope` (argument-type cluster), `funcdef` /
  `externfunc` (function-def cluster), `structdef` / `variantdef` /
  `uniondef` / `datadef` (data-block cluster), `getter` /
  `literalinit` / `structref` / `unionref` / `statement` / `funcs`
  (body cluster), `module` / `generic` / `types` (top-level cluster),
  `imports` / `files` / `apps` (file / import / app layer).

  The facade `src/analyzer/defanalyzer/resolver.nim` re-exports every per-type
  file plus the nested parser layer (`src/analyzer/defanalyzer/resolver/parser.nim`)
  so consumers say `import resolver` once. The facade owns every
  `resolve*` proc from `resolveArgumentType` through `resolveApp`
  plus the constraint-satisfaction check (`satisfies` — deliberately
  shallow `(name, arity, accessibility)` verification; see the
  comment block above `resolveModuleArgumentType` for why the deep
  signature check lives one phase up, in the def analyzer's
  `checkImplSatisfies`). Every resolution site carries a
  `TypeContext` (enclosing module | enclosing generic, typecontext.nim)
  from which `FunctionAccess` is derived: `faAll` inside the
  defining module, `faPublic` everywhere else — `findFunctionDefs`
  filters by it at every layer. Scope lookups live with their owning type:
  name-keyed `findType` / `findModule` / `findGeneric` on `FileContext`
  (filecontext.nim, the name→parser-Type bridge), identity-keyed
  `findType` / `findModule` / `findGeneric` plus the scope-spanning
  `findGenericInScope` on `ResolvedFile` (files.nim), and identity-
  keyed `findFile` plus path-keyed `findImportedFile` on `ResolvedApp`
  (app.nim — the resolve-time result-and-accumulator that owns the
  topo-order assert).
- **Single-pass walk per app** (files come topo-sorted leaves-first
  from the parser's multi-file `parse*` entry, so imports are always
  resolved before use). For
  each file: build the `FileContext` (locally-defined names +
  imported bindings). Then for each defined type resolve requires
  (if any), the data block, and each function signature/body.
  Argument types along the way carry parser Module identifiers, so
  every `ResolvedModuleArgumentType` is well-formed at construction
  without any forward-reference dance. The historical shell /
  populate two-pass has been retired.
- **Impl-list validation** — `resolveModuleArgumentType` derives the
  require slots in the module's DEFINING scope: a local module via
  `inferGenerics` in this file's context (explicit `struct(...)`
  header or inferred struct/union fields), an imported module by
  reading the slots off the binding's captured resolved twin — so
  the contract generic need not be imported at the use site. It then
  checks the impls count ("expects N impls but found M") and calls
  `satisfies` on each pair. `satisfies` verifies `(name,
  arity)` plus accessibility at the parser level; signature parity
  is checked at def time by the def analyzer's identity-probe
  constraint check (`findImplDef`), which finds the contract through
  the imported module's source file (`findGenericInScope`), and
  `analyzeValueTypeAgainstDefType` still guards use sites.
- **Generic param-list ownership** — each data-block type derives
  its own order-preserving `generics` seq at construction:
  `ResolvedVariantDef` from its generic-typed fields,
  `ResolvedUnionDef` by merging variant requires (first-seen order
  across variants — one union scope, Rust-style shared params),
  `ResolvedStructDef` from its explicit `struct(...)` header or its
  inferred generic fields (the split is decided inside
  `resolveStructDef`; the constructed def carries no kind — nothing
  downstream needs to know which path produced it).
  `genericTypeIndex` is an on-demand projection of that seq; the
  `requires*` accessors read it directly. Use-sites that can't
  touch a mid-resolution module derive the same list from the
  parser side via `fileCtx.inferGenerics`. No uniqueness
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
  `ResolvedVariantDef` / `ResolvedUnionDef` / `ResolvedModule` /
  `ResolvedGeneric` carry every accessor the analyzer's retired
  phase-A wrappers used to add: `findField`, `findVariant`,
  `findFunctionDefs(name, arity, public)`, `funcNameArityIndex`,
  `funcDefIndex`. The analyzer reads these directly rather than
  rebuilding a parallel def-level view.
- **Body-level name resolution** — the resolver walks user-function
  bodies: each statement is dispatched, each expression is resolved,
  and every function call's root (the user-typed receiver name) is
  resolved against the FileContext to a `parser.LocalType` carried on
  `ResolvedFunctionCall.typ` — so the analyzer never resolves a
  user-typed name; it does identity lookups on what the resolver
  already bound. The per-file `FileContext` itself is stored on
  `ResolvedFile.scope` for downstream name→parser.LocalType bridging
  (e.g. the analyzer's bare-literal defaults). A `FunctionContext`
  (Table[Identifier, Location]) tracks the names of variables
  currently in scope; the value stores the declaration site so
  duplicate-declaration errors can point at the prior source
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

Two barrels split along the phase boundary, extending the nesting
convention one level (parser ⊂ resolver ⊂ defanalyzer ⊂ analyzer):

- `src/analyzer/defanalyzer.nim` — definition-analysis barrel.
  Hosts the phase-A analyze* procs (analyzeDefGenericArgumentType →
  analyzeDefApp) and re-exports the resolver layer + every
  def-level type. `src/analyzer/defanalyzer/` holds the def-level
  per-type files plus the nested resolver subtree (Phase 4).
- `src/analyzer.nim` — body-analysis barrel and top of the stack.
  Hosts the phase-B body walkers, the extract/find helpers, and the
  public two-pass `analyze*` entry; exports defanalyzer so
  `import analyzer` reaches everything. `src/analyzer/` holds the
  body-level per-type files (type declaration, constructor, and
  accessors only; `ls` the folders for the authoritative lists).

Takes a `ResolvedApp` and returns an `AnalyzedApp` — a type-rich view
of every value, expression, and statement in each function body.
**Two passes** (see plans/plan_analyzer_two_pass.md):

**Pass A — definitions** (`analyzeDefApp`). Walks every file →
every module + generic → every struct/union/literal block → every
funcDef signature → every user-function statement across the whole
app, producing an `AnalyzedDefApp`: per-file `AnalyzedDefFile`
(analyzed imports + defined types + the name-keyed
`ResolvedFileContext`), per-def `AnalyzedDefModule` (whose `functions`
are tagged `AnalyzedDefFunction`s — extern/user, each pairing the
resolver function with its pre-analyzed
`AnalyzedFunctionDef`; user functions additionally carry
their `AnalyzedDefStatement` tree) / `AnalyzedGeneric` (bare
`AnalyzedFunctionDef`s — generics have no extern/user split)
and the data-block wrappers (`AnalyzedStructDef` /
`AnalyzedVariantDef` / `AnalyzedUnionDef` / `AnalyzedLiteralDef` /
`AnalyzedDataDef`). The statement walk mirrors the resolver's statement
cluster 1:1 (`AnalyzedDefLiteral` → kwargs → fncalls → initializers
→ match → expression → statement, hosted in
`defanalyzer/statement.nim` with the ref wrappers in
`defanalyzer/structref.nim` / `unionref.nim`), re-binding each
def-level fact (literal default module + LiteralDef, call receiver
`ResolvedLocalType`, struct/union defs behind refs) from the file scope.
`AnalyzedDefApp` itself is just the fileDefs + a path-keyed
`fileDefIndex` behind `findFileDef` — all type lookup state lives on
the per-file scopes. Any def-site error fires here before any body
walker touches the AST.

Three phase-A invariants worth naming:

- **One context value, no twins.** Phase-A walkers carry a single
  `ResolvedTypeContext` (enclosing resolved module | resolved
  generic, defanalyzer/typecontext.nim — the identity-ladder twin of
  the resolver's `TypeContext`), consumed for exactly one decision:
  function visibility during constraint satisfaction. Everything
  else context-sensitive (the generic self-reference rule, name/
  arity/accessibility presence) was already enforced at resolve
  time, so there are no module/generic proc twins — one context
  value, one proc.
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
  decision (module → `access(module)`, generic → `faAll`). Hash =
  name + input types (input-signature uniqueness rule; return type
  and access are checked explicitly on the hit). Satisfaction is a
  binding-independent property of the module, decided by one index
  probe per required def — an impl with a mismatched signature is
  rejected at its declaration even if the function is never called.
  Phase B's `analyzeValueTypeAgainstDefType` generic arm now runs
  this same check (was a shallower identity-only loop), so the
  value-position check is visibility-aware too.
- **Identity lookups assert, never err — on the types themselves.**
  Every identity-keyed lookup (`findType` / `findModule` /
  `findGeneric` on both FileContext rungs, `ResolvedFile.findType`,
  `ResolvedApp.findFile` / `ResolvedApp.findImportedFile`,
  `AnalyzedDefApp.findFileDef`, `ResolvedFile.findGenericInScope`,
  `AnalyzedDefModule.findFunctionDef`) returns its value directly
  with an `assert "[BUG] - ..."` inside: by construction callers can
  only ask about identities the layer below bound, so a miss is a
  compiler bug and no caller consumes an error path. The split is
  principled — name-keyed lookups (resolve time, `findVariant`,
  `findFunctionDefs`, `findImplDef`) keep `Result` because user
  errors genuinely surface there; constraint-check failures are the
  def analyzer's own user errors. The exported surface is
  deliberately narrow: `analyzeDefApp` (the pass entry) and
  `analyzeDefArgumentType` (reused by phase B for synthetic argument
  types); every other walker is private to the barrel.

**Pass B — bodies.** The per-file `analyzeFile` walk first lifts
each phase-A import def to its body form (`analyzeImport` — each
imported type resolves to the source file's `AnalyzedLocalType`
via that file's fileDef), builds the per-file `AnalyzedFileContext`
spanning imports + local types, and then analyzes each module's
function bodies against it. Call sites read pre-analyzed funcDef
signatures via `fileCtx.findType(typ).findFunctionDefs(...)` — no
re-analysis of arg types or return types per call site. Body-level
analyzed types back-reference the phase-A defs that produced them
(`AnalyzedFile.def` / `AnalyzedModule.def`; extern functions carry
their `AnalyzedFunctionDef`). Scope:

- **Identity-based lookups only** — the analyzer never resolves a
  user-typed name. Every reference reaching it already carries the
  identity the layer below bound: function-call roots are resolved
  to a `parser.LocalType` at resolve time (`ResolvedFunctionCall.typ`);
  argument types carry their parser Module/Generic. Each layer's
  per-file scope answers "given what the layer below handed me,
  find my enrichment of it", all hash-by-loc:

      resolver     FileContext           Identifier   → parser.LocalType
      defanalyzer  ResolvedFileContext   parser.LocalType  → ResolvedLocalType
      analyzer     AnalyzedFileContext   ResolvedLocalType → AnalyzedLocalType

  Aliased imports (`import { u8 as Byte }`) can never miss.
  Bare-literal defaults are bound at resolve time too
  (`resolveLiteral` looks up `Literal.defaultType` — "i32"/"f32"/
  "String" — against the FileContext and stores the parser.Module on
  `ResolvedLiteral.default`); phase A carries the resolved default as
  an `AnalyzedModuleArgumentType` on `AnalyzedDefLiteral.default`,
  which phase B's `analyzeBareLiteral` reads directly (module-argtype
  throughout — no re-wrapping). See
  plans/plan_identity_based_lookups.md and
  plans/plan_alias_lookup_cleanup.md.
- **Per-file context = fileDef + fileCtx, minimal params** —
  phase A threads the `ResolvedFileContext` it is building and stores
  it on `AnalyzedDefFile.scope`; phase B threads the
  finished `fileDef: AnalyzedDefFile` (identity scope,
  resolver file, analyzed defs) plus the body-level
  `fileCtx: AnalyzedFileContext` built at `analyzeFile` entry.
  Phase-B shape: `(appDef, fileDef, fileCtx, module, funcCtx,
  ...)` where `module` is the enclosing `AnalyzedDefModule`
  (body walkers reach the resolver module via `module.resolved`);
  the extract helpers (`extractDataDef` / `extractStructFor`
  / `extractUnionFor`) dispatch off the AnalyzedFileContext. Wider
  contexts stay off the signatures: `app: ResolvedApp` appears only
  in phase A's file walk, where the app is the subject (`analyze*` /
  `analyzeDefApp` / `analyzeDefFile` and
  `analyzeDefImport`'s `app.findFile`). Phase B never sees
  it. `fileDef.findType` stays local-only by design —
  `analyzeImportedType` uses it to verify an imported name is
  DEFINED in its source file, not merely visible there.

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
  helper on the analyzer facade dispatches on `ResolvedLiteralDef`
  and validates the literal text against all integer kinds plus
  String (parsing lives in `analyzer/literalparse.nim`).
  `analyzeArgumentList`, `analyzeKeywordArgument`, and
  `analyzeLiteralInitializer` all route through it.
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
  retired def-level `AnalyzedArgumentDef` wrapper.
- **Scope tables** — `ResolvedFileContext`
  (defanalyzer/filecontext.nim) and `AnalyzedFileContext`
  (analyzer/filecontext.nim) both span imports + local defined types;
  the same type imported under two bindings lands on one key, so
  construction only rejects a genuinely different entry under an
  existing key. `AnalyzedFunctionContext` (analyzer/funccontext.nim,
  `Identifier → AnalyzedArgumentType`) is the per-function variable
  scope threaded through the body walkers — variables have no
  identity beyond their name, so name keying is correct there.

The remaining gaps are listed in **What's Next**. The headline ones
are the equality-vs-unification trap for free-generic types and the
substitution-chain handling in `concrete()` — both are flagged as
`TODO(union-inference)` in `analyzer/defanalyzer/argtype.nim` /
`analyzer/defanalyzer/genericimplmap.nim` and surface as case-arm uniformity
check failures on fixtures that flow leave-as-is values through
`verifyUniformReturnType` (the 2 known integration failures).

## Project Structure

```
src/
  asl.nim                          entry point
  cli.nim                          CLI parsing via argparse
  utils.nim                        generic bfs[T, V] + topoSort with
                                   cycle detection
  nim.cfg                          per-component module search paths
  analyzer/defanalyzer/resolver.nim            resolver facade — the public entry
                                   for the resolver layer. Re-exports
                                   every per-type file PLUS the nested
                                   parser (its AST types, `parse*`
                                   entry point, and Location). Also
                                   owns every cross-cluster `resolve*`
                                   proc and the constraint-
                                   satisfaction check (`satisfies` —
                                   shallow by design; deep signature
                                   parity is the analyzer's job).
                                   Scope lookups live with their
                                   owning types (filecontext.nim /
                                   files.nim / app.nim below).
                                   `import resolver` gives consumers
                                   everything they need to build,
                                   traverse, or diagnose ASL programs.

  analyzer/defanalyzer/resolver/              resolver internals — one file per
                                   resolved type. Each file holds the
                                   type declaration, constructor, and
                                   accessors only; the cross-type
                                   `resolve*` procs live on the facade.
    literaldef.nim                 ResolvedLiteralDef + newResolvedLiteralDef
    patterns.nim                   ResolvedCasePattern + resolveCasePattern
    imports.nim                    ResolvedImportedType / ResolvedImport
    filecontext.nim                  FileContext (Identifier → parser
                                   Type) — the name→identity bridge,
                                   populated from imports + local
                                   defs; keyed by binding so aliased
                                   imports resolve correctly. Owns
                                   the name-keyed findType /
                                   findModule / findGeneric.
    functioncontext.nim              FunctionContext
                                   (Table[Identifier, Location]) —
                                   names of variables currently in
                                   scope, keyed by identifier with
                                   the declaration Location as value
                                   for duplicate-declaration error
                                   pointers. Types are the analyzer's
                                   concern. Constructor
                                   newFunctionContext seeds from a
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
    structdef.nim                  ResolvedStructDef (owned generics
                                   seq + fieldIndex + findField;
                                   genericTypeIndex is an on-demand
                                   projection).
    variantdef.nim                 ResolvedVariantDef (fieldIndex +
                                   findField + generics derived from
                                   its generic-typed fields).
    uniondef.nim                   ResolvedUnionDef (variantIndex +
                                   findVariant + generics merged
                                   from variant requires, first-seen
                                   order).
    datadef.nim                    ResolvedDataDef (ddkLiteral / ddkStruct
                                   / ddkUnion).
    getter.nim                     ResolvedGetter.
    literalinit.nim                ResolvedLiteralInitializer.
    structref.nim                  ResolvedStructRef — parser
                                   StructRef back-ref + receiver
                                   ResolvedModuleArgumentType
                                   (validated impls) + its StructDef;
                                   wrong-kind receivers rejected at
                                   ref-resolve time.
    unionref.nim                   ResolvedUnionRef — parser UnionRef
                                   back-ref + receiver
                                   ResolvedModuleArgumentType + its
                                   UnionDef + the referenced
                                   VariantDef; wrong-kind receivers
                                   and unknown variants rejected at
                                   ref-resolve time.
    statement.nim                  Body-cluster mutually-recursive
                                   types: ResolvedLiteral (parsed
                                   Literal + its default Module,
                                   bound at resolve time) /
                                   ResolvedKeywordArgument /
                                   ResolvedStructInitializer /
                                   ResolvedUnionInitializer /
                                   ResolvedFunctionCall (carries
                                   `typ: parser.LocalType` — the call
                                   root resolved at resolve time) /
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
    types.nim                      Tagged ResolvedLocalType (rltkModule /
                                   rltkGeneric) — one-of over module
                                   and generic.
    files.nim                      ResolvedFile + identity-keyed
                                   typeIndex (parser.LocalType → int) +
                                   findType / findModule /
                                   findGeneric taking the parser-side
                                   Type / Module / Generic plus a loc
                                   for error messages. Also stores
                                   the resolve-time FileContext
                                   (`scope` accessor) for downstream
                                   name→parser.LocalType bridging.
    app.nim                        ResolvedApp — the resolver's
                                   app-level result AND accumulator:
                                   parsed App + ResolvedFiles added as
                                   they land, behind an identity
                                   fileIndex (findFile) and a
                                   path-keyed filePathIndex
                                   (findImportedFile — owns the
                                   topo-order assert the import-binding
                                   capture relies on). Type lookups
                                   live on the per-file scopes, not the
                                   app. `resolve*` builds it, add()s
                                   per file; the actor proc lives on
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
      structref.nim                StructRef — wraps the receiver
                                   ArgumentType (module root + impls;
                                   empty = bare surface form,
                                   populated = explicit-impls).
      unionref.nim                 UnionRef — the receiver
                                   ArgumentType plus the variant
                                   Identifier (the
                                   `Type[.Impls].Variant`
                                   production).
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
      generics.nim                 Generic (defs + funcDefArityIndex +
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

  analyzer/defanalyzer.nim         definition-analysis barrel —
                                   phase A. Hosts the def-level
                                   analyze* procs
                                   (analyzeDefGenericArgumentType →
                                   analyzeDefApp) and
                                   re-exports the resolver layer +
                                   every def-level type below, so
                                   the body layer imports
                                   ./defanalyzer once.

  analyzer/defanalyzer/            def-level per-type files
                                   (declaration + constructor +
                                   accessors only) + the nested
                                   resolver subtree above. `ls` for
                                   the authoritative list.
    filecontext.nim                  ResolvedFileContext (parser.LocalType →
                                   ResolvedLocalType, identity-keyed) —
                                   spans imports + local types;
                                   built per file in pass A, stored
                                   on AnalyzedDefFile.scope.
                                   Owns identity-keyed findType /
                                   findModule / findGeneric.
                                   Same-identity re-imports are
                                   idempotent.
    argtype.nim                    AnalyzedArgumentType — flat tagged
                                   union (aatkModule / aatkGeneric)
                                   mirroring the resolver shape +
                                   hash/== (hash-equality; see the
                                   equality-vs-unification TODO) +
                                   concrete* substitution overloads.
    moduleargtype.nim              AnalyzedModuleArgumentType —
                                   resolved back-ref + ResolvedModule
                                   + analyzed impls seq.
    genericargtype.nim             AnalyzedGenericArgumentType —
                                   ResolvedGeneric + use-site loc.
    genericimplmap.nim             GenericImplMap
                                   (Table[ResolvedGeneric,
                                   AnalyzedArgumentType]) + merge
                                   (conflict-on-different-binding;
                                   substitution-chain collapsing
                                   still TODO).
    argdef.nim                     AnalyzedArgumentDef —
                                   phase-A arg wrapper (resolved def
                                   + analyzed argType).
    funcdef.nim                    AnalyzedFunctionDef — args
                                   + return type fully analyzed.
    literaldef.nim                 AnalyzedLiteralDef.
    structdef.nim                  AnalyzedStructDef (analyzed fields).
    variantdef.nim                 AnalyzedVariantDef (analyzed fields).
    uniondef.nim                   AnalyzedUnionDef (analyzed variants).
    datadef.nim                    AnalyzedDataDef (adkLiteral /
                                   adkStruct / adkUnion).
    moduledef.nim                  AnalyzedDefModule (requires +
                                   data + functions:
                                   seq[AnalyzedDefFunction] +
                                   findFunctionDef(s) overload
                                   lookup; funcDefs projection
                                   accessor).
    function.nim                   AnalyzedDefExternFunction /
                                   AnalyzedDefUserFunction + tagged
                                   AnalyzedDefFunction (adfkExtern /
                                   adfkUser) with uniform def / name
                                   / arity accessors.
    generic.nim                    AnalyzedGeneric (funcDefs).
    types.nim                      AnalyzedLocalType (altkModule /
                                   altkGeneric) + findFunctionDefs
                                   uniform overload lookup.
    filedef.nim                    AnalyzedDefFile (resolved +
                                   imports + types + a modules
                                   projection + scope + local-only
                                   identity-keyed findType /
                                   findModule — used by
                                   analyzeImportedType to verify an
                                   imported name is DEFINED in its
                                   source file).
    appdef.nim                     AnalyzedDefApp (fileDefs +
                                   path-keyed fileDefIndex +
                                   findFileDef).
    appcontext.nim                 ResolvedAppContext — phase A's
                                   app-level accumulator (ResolvedApp
                                   + AnalyzedDefFiles added as they
                                   land, path-indexed); analyzeDefApp
                                   builds it and projects the seq
                                   into newAnalyzedDefApp. The rung-2
                                   twin of the resolver's ResolvedApp.
    importedtypedef.nim            AnalyzedDefImportedType (binding →
                                   ResolvedLocalType).
    importdef.nim                  AnalyzedDefImport (resolved
                                   import + imported type defs +
                                   source-file path).

  analyzer.nim                     body-analysis barrel — phase B and
                                   the top of the compiler stack.
                                   Imports + exports defanalyzer
                                   (transitively resolver → parser →
                                   Location), and owns the phase-B
                                   body walkers (analyzeExpression /
                                   analyzeStatement /
                                   analyzeFunctionCall /
                                   analyzeMatchExpression / ...), the
                                   AnalyzedFileContext-keyed extract
                                   helpers (extractDataDef,
                                   extractStructFor, extractUnionFor),
                                   and the public two-pass `analyze*`
                                   entry.

  analyzer/                        body-level per-type files
                                   (declaration + constructor +
                                   accessors only; all cross-type
                                   analyze* procs live on the
                                   barrels). Each imports
                                   ./defanalyzer once for def types
                                   + resolver.
    filecontext.nim                  AnalyzedFileContext (ResolvedLocalType →
                                   AnalyzedLocalType,
                                   identity-keyed) — the third rung
                                   of the scope ladder; spans
                                   imports + local types, built per
                                   file at analyzeFile entry and
                                   threaded through the body
                                   walkers. Owns findType /
                                   findModule / findGeneric.
    imports.nim                    AnalyzedImport — a phase-A import
                                   def lifted to its body form.
    importedtype.nim               AnalyzedImportedType (binding →
                                   the source file's
                                   AnalyzedLocalType).
    funccontext.nim                  AnalyzedFunctionContext (Identifier →
                                   AnalyzedArgumentType) —
                                   per-function variable scope;
                                   seeded from a pre-analyzed
                                   AnalyzedFunctionDef's args
                                   (newAnalyzedFunctionContext) and
                                   extended via update overloads
                                   (statement binding / case-pattern
                                   bindings). Case blocks copy by
                                   plain assignment for
                                   sibling-isolated scopes.
    literalparse.nim               parseInteger[T: SomeInteger] /
                                   float-parsing helpers (bounds
                                   checks, special-value forms).
    unionpatternscope.nim          AnalyzedUnionPatternScope —
                                   variant-coverage tracking for
                                   match exhaustiveness.
    literalpatternscope.nim        AnalyzedLiteralPatternScope —
                                   literal-coverage tracking (tagged
                                   union over the eight integer
                                   kinds).
    binding.nim                    AnalyzedBinding (name + argType) —
                                   pattern-side binding pair.
    unionpattern.nim               AnalyzedUnionPattern (resolved
                                   variant + bindings).
    casepattern.nim                AnalyzedCasePattern (acpkUnion /
                                   acpkInteger / acpkVariable).
    variable.nim                   AnalyzedVariable.
    literalinit.nim                AnalyzedLiteralInitializer.
    getter.nim                     AnalyzedGetter (source argType +
                                   property: AnalyzedArgumentDef
                                   — its argType is the getter's).
    statement.nim                  Body-cluster mutually-recursive
                                   types: AnalyzedExpression /
                                   AnalyzedStatement /
                                   AnalyzedFunctionCall /
                                   AnalyzedKeywordArgument /
                                   AnalyzedStructRef /
                                   AnalyzedUnionRef /
                                   AnalyzedStructInitializer /
                                   AnalyzedUnionInitializer /
                                   AnalyzedInitializer /
                                   AnalyzedMatchExpression /
                                   AnalyzedCaseBlock /
                                   AnalyzedAssignment /
                                   AnalyzedSetter. Type-only file —
                                   the corresponding analyze* procs
                                   live on the facade.
    userfunc.nim                   AnalyzedUserFunction (def:
                                   AnalyzedDefUserFunction twin +
                                   statements; resolved derived
                                   through the twin).
    externfunc.nim                 AnalyzedExternFunction — wraps the
                                   phase-A AnalyzedDefExternFunction
                                   directly (def + resolved reached
                                   through it).
    function.nim                   AnalyzedFunction tagged union
                                   (user / extern).
    module.nim                     AnalyzedModule (def:
                                   AnalyzedDefModule back-ref
                                   + analyzed functions).
    file.nim                       AnalyzedFile (def:
                                   AnalyzedDefFile back-ref +
                                   analyzed imports (AnalyzedImport,
                                   the phase-B form) + modules).
    app.nim                        AnalyzedApp (resolved + files) —
                                   the handle downstream codegen will
                                   thread through.
    appcontext.nim                 AnalyzedAppContext — phase B's
                                   app-level accumulator (the phase-A
                                   AnalyzedDefApp + AnalyzedFiles
                                   added as they land, path-indexed);
                                   analyze* builds it and projects
                                   the seq into newAnalyzedApp.

examples/
  base.aslr                        standard library definition (extern
                                   functions) — the `.aslr` runtime
                                   file wired in as the default `std`
                                   vendor (`--vendor=std:<path>`)
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
                                   src/analyzer/defanalyzer/resolver/parser/)
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
`tests/all.nim`. **327 tests** covering positive paths, negative
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
unit suite at **350/350**. Recent structural work: the two-pass
analyzer recovery (plans/plan_analyzer_two_pass.md), the
identity-based lookup migration
(plans/plan_identity_based_lookups.md +
plans/plan_alias_lookup_cleanup.md — post-resolution lookups key on
parser-level identity, immune to aliased imports), and the fileCtx
threading removal (plans/plan_filescope_threading.md). See tasks.md
for the DDD-refactor trail that preceded them.

What the analyzer does today (all wired):

- Overload selection at function-call sites — each candidate funcDef
  is unified against the call's argument types via `GenericImplMap`
  + `merge`, and uniqueness picks the survivor (ambiguity rejected).
- Impl-list arity + generic constraint satisfaction — presence and
  accessibility checked at resolve time in
  `resolveModuleArgumentType` via `satisfies`; signature parity
  checked def-time inline in `analyzeDefModuleArgumentType`
  (contract funcDefs concretized at definition level, probed by
  identity via `findImplDef`);
  `analyzeValueTypeAgainstDefType` still runs use-site checks.
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

**Phase B (body analysis) is the next fix target.** The phase-A
hardening arc — the identity ladder with assert-backed lookups, the
TypeContext/visibility machinery, definition-level constraint
satisfaction, input-signature uniqueness — was groundwork: phase B's
unification rebuild can now assume every def-level fact it consumes
is already validated and identity-addressable. The first two TODOs
below are the bugs that rebuild exists to fix.

Focused TODOs still open:

- **Equality vs unification for analyzed types**
  (`analyzer/defanalyzer/argtype.nim`, the `==` on `AnalyzedArgumentType` —
  flagged as `TODO(union-inference)`). Assignability against an
  expected type that carries free generics (post leave-as-is) needs
  unification, not hash equality. Surfaces as the case-arm
  uniformity check failing on fixtures that flow free-generic
  values through `verifyUniformReturnType` — the 2 known
  integration failures (`match.asl`, `nested_generics.asl`). Fix is
  to route every assignability check through
  `analyzeValueTypeAgainstDefType` + `merge`, with eager
  chain-collapsing in `merge`. Owned by
  plans/plan_deferred_typing.md.
- **Substitution chains in `merge` / `concrete()`**
  (`analyzer/defanalyzer/genericimplmap.nim`) — `Sample → K, K → u8` should
  collapse to `Sample → u8`; today `concrete()` does a single
  `getOrDefault`, so a type rewritten through the map can come out
  HALF-substituted (still carrying a free `K` where `u8` belongs).
  Downstream hash comparisons then see two different types for the
  same value — the visible symptom is `verifyUniformReturnType`
  failing with "function does not return the expected return type"
  on correct code (the match.asl integration failure). Pairs with
  the equality fix above; the two land together as the phase-B
  unification rebuild.
- **Phase-B re-entries analyze DEF-side argtypes in the USING
  file's scope** — found by the cross-file provenance tests
  (test_analyzer.nim documents the repro). Body walkers re-enter
  `analyzeDefArgumentType(fileDef.scope, ...)` on an imported
  module's OWN definition types — struct/variant field types
  (`analyzeStructInitializer`, `analyzeUnionCasePattern`) and union
  generic slots — so a field typed by the module's contract generic
  (`Pair { value: Comparable }`) hits
  `analyzeDefGenericArgumentType` → `fileCtx.findGeneric` against
  the use site's context and crashes on the phase-A `[BUG]` assert
  when the contract legitimately isn't imported there (legal since
  the P3-flip). The existing suite never hit it because every test
  container is `Array` with an explicit phantom header — no
  generic-typed field. Symptom chain: `Pair[Impl] { value: x }` in
  a file that imports Pair but not Comparable → AssertionDefect
  "type `Comparable` missing from the file context". Two fix
  routes, both P3-shaped: read the stored twin (the defining file
  already analyzed its own fields — B's `AnalyzedDefModule`
  carries the `AnalyzedArgumentType`s; reachable via
  `appDef.findFileDef(entry.imported.impFile.path)`) or route the
  re-entry's fileCtx to the owner's scope by module-entry
  provenance, mirroring the P3-swap dispatch. Site-WRITTEN
  argtypes (initializer/ref impl lists, synthetic literal types)
  stay in the use-site scope — only def-side re-entries move.
  ROUTE CHOSEN: read the stored twin — phase B was incrementally
  rewired to walk the AnalyzedDef* bundle instead of re-deriving.
  DONE: analyzer.nim no longer calls `analyzeDefArgumentType` at
  all — the module/function walk, the whole statement/expression
  walk, the statement outputs, the initializers, and finally the
  union case-pattern field types all read what phase A already
  analyzed (the last read `fieldDef.argType` off the analyzed
  variant twin). Every body output now anchors on its AnalyzedDef*
  twin (getter → AnalyzedArgumentDef; function call / kwarg /
  case block / match → their def twins; union pattern →
  AnalyzedVariantDef). The cross-file re-entry crash path is
  structurally gone. Acceptance gate: the two deferred positive
  provenance tests (see test_analyzer.nim's suite comment) go back
  in once concretization is restored.

  CURRENT STATE — deliberately RED (WIP): stripping the
  initializers' positional concretization (below) costs 3 unit
  tests (bare-literal default in a generic union kwarg, banged
  return types) and the integration suite (case-arm return-type
  uniformity sees unconcretized generics) until the replacement
  lands. Suites are red on main by intent; the WIP commits record
  the exact counts.

- **ImplMap-per-argument-type — the concretization rebuild
  (IN PROGRESS).** WHY: phase B used to rebuild concrete
  instantiations positionally — impls stored as a bare seq, each
  consumer re-zipping against the resolver's `genericTypeIndex` and
  re-entering `analyzeDefArgumentType` to translate slots, per
  initializer and per case pattern. Positions only compose when the
  substituted generic is one of the container's OWN slots in the
  container's OWN order — shape-fragile, resolver-coupled, and the
  reason `concrete()`'s single `getOrDefault` never had a place to
  collapse substitution chains. WHAT: the def analyzer will
  maintain a `GenericImplMap` per module argument type, built where
  `zip(requires, impls)` already happens
  (`analyzeDefModuleArgumentType`); phase B builds concrete types
  from the stored map. Identity-keyed (alias/cross-file-immune),
  free generics are simply absent keys (downstream unification
  fills them), slot ORDER comes from the module twin's ordered
  `requires` seq (retiring `genericTypeIndex` from phase-B use),
  and the map is payload — hash/== stay on module + impls. Map
  construction/merge becomes the single home for the
  substitution-chain collapse (`Sample → K, K → u8`), pairing with
  the equality-vs-unification rebuild below. PLUMBING OWED (the WIP
  red state): the map is not built yet — the struct/union
  initializer kwarg walks carry a `# TODO: build impl map` and
  currently type-check kwargs against the field's UNconcretized
  declared type, which is what drops the 3 unit + integration
  cases. When `analyzeDefModuleArgumentType` stores the map and the
  kwarg/pattern concretization reads it, those flip green and the
  deferred provenance tests join them.
- **Dummy location in `AnalyzedArgumentType.self`**
  (`analyzer/defanalyzer/argtype.nim`, marked TODO) — the generic arm
  reconstructs a `ResolvedGenericArgumentType` with a fabricated
  `newLocation()` (0:0). No current consumer renders that loc
  (constraint errors report the impl site; hashing ignores loc), but
  any future diagnostic built from a reconstructed self-type will
  point nowhere. Fix when the phase-B rebuild touches this path —
  the self shape should carry the use site's loc.
- **F32 / F64 / Pointer literal kinds** — Pointer literal positions
  still return a todo (`analyzer.nim`'s literal dispatch).
- **Impl-map update from literal positions** — when a literal arg
  flows into a generic position (e.g., `f(K=…)` with literal
  inferable type), the resulting binding isn't yet recorded.
- **Nested-impl generic accumulation** — a field typed
  `Box[u8, Sample]` should contribute `Sample` to the parent's
  requires; none of the generic-collection walks
  (`fileCtx.inferGenerics` and the per-type builds in
  structdef / variantdef / uniondef) descend into impls yet — when
  this lands, all of them need the same descent.
- **Require-slot derivation is implemented three times and must
  agree** — `fileCtx.inferGenerics` (use-site, name-keyed) plus the
  construction-time collections in structdef and uniondef that feed
  the resolved twin's stored `generics`. Pre-flip these were
  redundant checks of one truth; post-flip the twin's stored slots
  are AUTHORITATIVE for imported modules while locals still use the
  use-site derivation — any drift between the implementations
  (ordering, dedup semantics, the impl-descent above) now diverges
  across phases and lands on `analyzeDefModuleArgumentType`'s count
  assert as a [BUG] crash instead of a diagnostic. Consolidating to
  one derivation is a correctness item, not a cleanup.
- **`AnalyzedDefImportedType` stores the twin twice** — `typ` and
  `resolved.resolvedType` are the same object arriving via two
  different derivations (the def-time `impFile.findType` re-lookup
  vs the resolve-time P3-pre-1 capture), with no assert tying them.
  Either derive `typ` from the binding or assert the tie in the
  constructor.
- **Small hygiene** — the shallow-vs-deep comment block on the
  resolver facade still contains a pre-deep-check paragraph
  assigning signature parity to phase B's value-vs-defType walk
  (superseded by the def analyzer's identity-probe check described
  further down in the same block); and `ResolvedApp.findFile`
  returns a Result although by resolve time the loader has
  materialized every import target — either it is the assert-backed
  form per the identity-lookup doctrine, or the user error it can
  surface should be nameable.
- **Type-correctness checks across statements** — assignment
  compatibility and match exhaustiveness. (Setter type equality is
  now enforced in `analyzeSetter`; its error message is still rough
  — flagged with a TODO.)
- **Redundant constraint re-checking — PERFORMANCE, revisit after
  codegen.** The def-time constraint check in
  `analyzeDefModuleArgumentType` runs at every occurrence of a
  parameterized argument type: every field, every funcDef
  arg/return, every ref/initializer in the statement walk, plus
  phase B's synthetic argtypes. Because the check compares at
  DEFINITION level, its verdict is a constant per
  `(impl root, contract generic, access)` triple — a file writing
  `Array[u8]` fifty times derives the same fact fifty times. The
  natural fix is a per-app memo keyed on that triple (access has
  only two values); it needs a home that respects the pure-proc
  discipline, which is why it is deliberately deferred rather than
  bolted on. The same theme runs through every phase — the
  resolver's `inferGenerics` re-derives require slots at each
  local-module use site (imported modules read the twin's stored
  slots), phase B re-concretizes per call — so this line item stands
  in for a dedicated caching pass over the whole pipeline.
  Priority order is settled: memory-safe C code generation first,
  then the performance pass.

After the analyzer:
- **IR generation** — lower the analyzed AST into an intermediate
  representation suitable for optimization and code generation.
- **Code generation** — emit target code (likely C or LLVM IR).
