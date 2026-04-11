# ID-Based Name Resolution (App Tree)

## Context

PSR-39 built the `App` tree with `Indexed*` wrappers that keep
`Table[string, int]` indices for module/generic/field/variant/function
lookups. PSR-40 gave every name-bearing AST field a `Location` via
`Identifier`. The next step: replace every `Identifier` reference in
the tree with the integer ID the index already computed. Downstream
phases (type checker, name resolver, codegen) then navigate by
integer, not by string lookup.

The raw AST from `parser.nim` stays untouched. A new set of
`Resolved*` types (parallel to `Indexed*`) holds the ID-based form.
Resolution runs top-down, recursively: `App` first, then each file,
each module, each function, each expression.

## Vocabulary

### Local ID
Every block stores a single `id: int` — its position in its
immediate parent's list. That's it. No typed id objects, no
ancestor path encoding.

Navigation from the root is an explicit chain of `seq` accesses:

```nim
app.files[0].modules[1].functions[2]   # function at index 2
app.files[0].modules[1].data.get.union.variants[0].fields[1]  # variant field
```

A richer "global id" — a full ancestor path encoded as a typed
value — was considered and rejected for Phase 1 because it
complicates lookups (each typed id needs its own lookup proc) and
is speculative infrastructure until Phase 2 or 3 actually needs
cross-block references.

### Ref
For Phase 1 the only cross-block reference that gets resolved is
imports → target file (`ResolvedImport.targetFileId: int` — a plain
index into `ResolvedApp.files`). Phase 2 will introduce a richer
`Ref` tagged union for type references in signatures; Phase 3 will
extend it further for expression resolution. Not in scope here.

### Primitives
Primitive types (`u8`, `u16`, `u32`, `u64`, `u128`, `i8`, `i16`,
`i32`, `i64`, `i128`, `f32`, `f64`, `bool`, `str`) are not declared
anywhere in source. They live in a hard-coded table at `App`-level:

```nim
const primitives = ["u8", "u16", "u32", "u64", "u128",
                    "i8", "i16", "i32", "i64", "i128",
                    "f32", "f64", "bool", "str"]
```

`primitiveId` is the index into this list.

## Complete Identifier Inventory

Every `Identifier` in the AST, categorized as **declaration** (index
into parent) or **reference** (needs a `Ref`):

### Declarations (become positional ids)

| Field | Parent list | Becomes |
|---|---|---|
| `Module.name` | `File.modules` | position in `file.modules` |
| `Generic.name` | `File.generics` | position in `file.generics` |
| `ImportName.name` | `Import.names` | position in `imp.names` |
| `ImportName.alias` | — | renames the visible name (still needs resolution as a Ref in other files) |
| `ArgumentDefinition.name` (struct fields) | `Struct.fields` | position in `struct.fields` |
| `ArgumentDefinition.name` (variant fields) | `VariantDefinition.fields` | position |
| `ArgumentDefinition.name` (function params) | `FunctionDefinition.params` | position |
| `VariantDefinition.name` | `Union.variants` | position |
| `FunctionDefinition.name` | `Module.functions` / `Generic.funcDefs` | position (overloads stay as a seq) |
| `Decorator.name` | — | stays as an `Identifier` / interned string; decorators aren't references |
| `Assignment.target` | *function's local list* | position in function's resolved locals |
| `VariantPatternField.binding` | *case body's binding list* | position in case body's bindings |

### References (become `Ref`)

| Field | Resolves within | Needs type info? |
|---|---|---|
| `ArgumentType.root` | primitive / current file's modules+generics+imports | no |
| `FunctionCall.name` | methods on `FunctionCall.argType` | no (ref is the overload set) |
| `Getter.source` | local / param / module-level name / import | no |
| `Getter.property` | fields on `source`'s type | **yes — needs type of `source`** |
| `Expression.variable` (`ekVariable`) | local / param / module-level / import | no |
| `LiteralInitializer.typeName` | primitive only (grammar guarantees) | no |
| `UnionInitializer.variantName` | variants of `argType` (must be a union) | no (argType known) |
| `KeywordArgument.name` | params of target function/initializer | **yes — needs target function chosen** |
| `VariantPattern.variantName` | variants of match subject's union type | **yes — needs subject's type** |
| `VariantPatternField.name` | fields of the resolved variant | yes (transitively) |
| `CasePattern.variable` (`cpkVariable`) | local binding introduced by the case | no |

Anything marked **"needs type info"** cannot be resolved without
expression type inference. These force a type-checker pass before
the resolver can finish.

## Two semantic categories for `ArgumentDefinition`

The raw parser `ArgumentDefinition` appears in four contexts. The
resolver splits them into two semantic categories — each gets its
own resolved type so the type system prevents confusing data
members with computation inputs:

- **`ResolvedField`** — data members: struct fields and variant
  fields.
- **`ResolvedArgument`** — computation inputs: function params,
  funcDef params, and (Phase 3) temporary local bindings inside
  function bodies.

The two types are structurally identical (id + name + argType +
loc) but distinct at the type level.

## Resolved Types (Mirror of `Indexed*`)

```nim
type
  ResolvedApp* = ref object
    files: seq[ResolvedFile]
    fileIndex: Table[string, int]        # absolute path → index in files

  ResolvedFile* = ref object
    id: int                              # index in app.files
    path: string
    imports: seq[ResolvedImport]
    modules: seq[ResolvedModule]
    generics: seq[ResolvedGeneric]

  ResolvedImport* = ref object
    id: int                              # index in file.imports
    source: string
    targetFileId: int                    # index in app.files
    names: seq[ResolvedImportName]
    loc: Location

  ResolvedImportName* = ref object
    id: int                              # index in imp.names
    name: Identifier
    alias: Option[Identifier]
    loc: Location

  ResolvedModule* = ref object
    id: int                              # index in file.modules
    decorators: seq[Decorator]           # raw until later
    name: Identifier
    data: Option[ResolvedData]
    functions: seq[ResolvedFunction]
    loc: Location

  ResolvedGeneric* = ref object
    id: int                              # index in file.generics
    decorators: seq[Decorator]
    name: Identifier
    funcDefs: seq[ResolvedFuncDef]
    loc: Location

  ResolvedField* = ref object            # struct field or variant field
    id: int                              # index in parent's fields list
    name: Identifier
    argType: ArgumentType                # raw until Phase 2
    loc: Location

  ResolvedArgument* = ref object         # function or funcDef parameter
    id: int                              # index in parent's params list
    name: Identifier
    argType: ArgumentType                # raw until Phase 2
    loc: Location

  ResolvedStruct* = ref object
    fields: seq[ResolvedField]
    loc: Location

  ResolvedVariant* = ref object
    id: int                              # index in union.variants
    name: Identifier
    fields: seq[ResolvedField]
    loc: Location

  ResolvedUnion* = ref object
    variants: seq[ResolvedVariant]
    loc: Location

  ResolvedDataKind* = enum
    rdkStruct, rdkUnion
  ResolvedData* = ref object
    case kind: ResolvedDataKind
    of rdkStruct: struct: ResolvedStruct
    of rdkUnion: union: ResolvedUnion

  ResolvedFunction* = ref object
    id: int                              # index in module.functions
    decorators: seq[Decorator]
    name: Identifier
    params: seq[ResolvedArgument]
    returns: ArgumentType                # raw
    body: StatementList                  # raw — Phase 3 resolves
    loc: Location

  ResolvedFuncDef* = ref object
    id: int                              # index in generic.funcDefs
    name: Identifier
    params: seq[ResolvedArgument]
    returns: ArgumentType
    loc: Location
```

Every id is a plain `int` — the local position in the immediate
parent's list. `ResolvedField` and `ResolvedArgument` are
structurally identical but distinct types so the type system
catches mixing up a struct field with a function parameter.

## Phasing

Full resolution in one step is too much — three natural slices
with very different costs:

### Phase 1 — Structural / declarations only

Just position-based IDs on every declaration. No `Ref` computation,
no type-reference resolution, no function-body walking.

- `ResolvedApp.files` — each `ResolvedFile.id = position in app.files`
- `ResolvedFile.modules` — each `ResolvedModule.id = position`
- `ResolvedFile.generics` — each `ResolvedGeneric.id = position`
- `ResolvedFile.imports` — each `ResolvedImport.id = position`; each
  `ResolvedImportName.id = position`
- `ResolvedModule.data` — struct fields / union variants / variant
  fields all get positional ids
- `ResolvedModule.functions` — each `ResolvedFunction.id = position`;
  overloads remain (same name, different ids)
- `ResolvedGeneric.funcDefs` — positional ids
- Function params — positional ids (no type resolution yet)
- Function bodies — stored as raw `StatementList`, untouched

**Deliverable**: every declaration in the App tree carries an `id`
that is its position in its parent list. Downstream callers can
navigate `app.files[fileId].modules[modId].functions[fnId].params[paramId]`
in O(1) without string lookups. Imports still resolve to a target
file id (already computed by PSR-39's topo sort).

**Cost**: ~400 LoC. Mostly mechanical mirroring of `Indexed*`.

### Phase 2 — Signature-level type references

Resolve `ArgumentType.root` everywhere it appears in a *signature*:
struct field types, variant field types, function parameter types,
function return types, generic type params (`Array[u32]`'s `u32`).

- A type reference resolves to one of: primitive, current-file
  module, current-file generic, imported module, imported generic.
  (No local types — primitives can't be nested, generics can only
  appear at top level.)
- Recurses through `impls` (the type parameters).
- Function bodies still untouched.

**Deliverable**: every signature in the App tree is fully typed by
integer Ref. You can ask "what type does parameter 2 of function 0
of module 1 of file 0 return?" and get back a `Ref` without string
lookup.

**Cost**: ~300 LoC. Needs a `resolveArgumentType` proc that
consults the current file's indices and the primitive table.
Error reporting for unknown types uses the identifier's location
(already carried since PSR-40).

### Phase 3 — Function body / expression resolution

Walk every statement and expression inside every function body:

- `Assignment.target` introduces a new local.
- `VariantPatternField.binding` introduces a new binding in case scope.
- `Expression.variable` resolves against (locals, params,
  module-level data fields, module-level functions, file-level
  modules/generics/imports) in that order.
- `Getter.source` resolves like a variable.
- `Getter.property` resolves to a field on `source`'s type — this
  requires knowing `source`'s type, which requires **expression
  type inference**.
- `FunctionCall.name` resolves to an overload set on `argType`.
- `UnionInitializer.variantName` resolves to a variant on `argType`.
- `VariantPattern.variantName` resolves to a variant on the match
  subject's type — requires knowing the subject's type.
- `KeywordArgument.name` resolves to a parameter of the target
  function, which (for `FunctionCall` with overloads) requires
  overload resolution, which needs type inference.

Phase 3 is effectively a compact type checker. It's much larger
than Phases 1 and 2 combined and needs a separate detailed plan.

**Cost**: unknown — at minimum ~1000 LoC, possibly much more
depending on how much of the type system we commit to
(Hindley-Milner? simple unification? no generics?).

## Design Decisions Needed

Before starting even Phase 1, lock down:

1. **Location of Resolved types** — new file `src/resolver.nim`, or
   extend `src/validator.nim`? Recommend new file — keeps indexing
   (Phase PSR-39) and resolution (this PSR) cleanly separated.

2. **API shape** — `proc resolve*(app: App): Result[ResolvedApp,
   string]`? Or accept raw `seq[File]` and run index+resolve as one
   pipeline? Recommend: keep them separate. `asl.nim:compile`
   chains `parser.parse → validator.index → resolver.resolve`.

3. **`id` field duplication** — is it redundant to store the `id`
   on a child when it's also the child's position in its parent's
   seq? Rationale for keeping it: once a `ResolvedModule` is passed
   around by ref, callers shouldn't have to know which seq it came
   from to know its id. Cost: 1 `int` per declaration. Recommend:
   keep the `id` field.

4. **Raw Identifier retention** — Resolved types still carry the
   original `Identifier` alongside the id (for error messages and
   for the formatter to round-trip). Alternative: replace with
   just `loc` + interned string id. Recommend: keep the Identifier,
   it's cheap and unblocks good diagnostics.

5. **Phase 1 scope check**: is "declarations only" enough for the
   work you want to do next, or do you need Phase 2 immediately?
   Phase 3 is a very different commitment — it crosses into type
   checking.

## Phase 1 Commit Sequence

Phase 1 breaks into **15 bite-sized commits**. Each one adds one
block type (or one wiring step), compiles cleanly, and leaves
every existing example working. Target ~20–50 line diffs per
commit.

Each commit lives entirely in `src/resolver.nim` except R1 which
also touches `src/asl.nim` and R15 which touches the docs.

### Skeleton

- **R1** — **Create `src/resolver.nim`.** ✅ *committed as `ee23b7d`*.

### File level

- **R2** — **`ResolvedFile{id, path}`.** Add `files:
  seq[ResolvedFile]` and `fileIndex: Table[string, int]` to
  `ResolvedApp`. `resolve` iterates `app.files` building
  `ResolvedFile(id: i, path: f.file.path)`.

### Imports

- **R3** — **`ResolvedImport{id, source, targetFileId}`.** Wire
  `imports: seq[ResolvedImport]` into `ResolvedFile`.
  `targetFileId` comes from `ResolvedApp.fileIndex` lookup of the
  absolute import path.
- **R4** — **`ResolvedImportName{id, name, alias}`.** Wire `names:
  seq[ResolvedImportName]` into `ResolvedImport`.

### Modules and generics (skeletons, body raw)

- **R5** — **`ResolvedModule{id, decorators, name, loc}` skeleton.**
  `data` and `functions` stay as raw AST pointers; wired in later
  commits. Wire `modules: seq[ResolvedModule]` into `ResolvedFile`.
- **R6** — **`ResolvedGeneric{id, decorators, name, loc}`
  skeleton.** `funcDefs` stays raw. Wire `generics:
  seq[ResolvedGeneric]` into `ResolvedFile`.

### Struct / variant / union

- **R7** — **`ResolvedField{id, name, argType, loc}`.** Type used
  by both struct fields and variant fields. Stand-alone.
- **R8** — **`ResolvedStruct{fields, loc}`.** Helper
  `resolveStruct(s: Struct): ResolvedStruct` assigns positional
  ids to fields.
- **R9** — **`ResolvedVariant{id, name, fields, loc}`.** Helper
  `resolveVariant(v: VariantDefinition, localId: int)`.
- **R10** — **`ResolvedUnion{variants, loc}`.** Helper
  `resolveUnion(u: Union): ResolvedUnion`.
- **R11** — **`ResolvedData` tagged union** (`rdkStruct |
  rdkUnion`). Helper `resolveData(db: DataBlock): ResolvedData`.
- **R12** — **Wire `ResolvedData` into `ResolvedModule.data`.**
  `data` field switches from raw `Option[DataBlock]` to
  `Option[ResolvedData]`.

### Functions

- **R13** — **`ResolvedArgument{id, name, argType, loc}` +
  `ResolvedFunction{id, decorators, name, params, returns, body,
  loc}`.** `ResolvedArgument` is the computation-input type used
  by function params and funcDef params. `ResolvedFunction.body`
  stays raw `StatementList`. Helper `resolveFunction(fn: Function,
  localId: int)` assigns positional ids to params. Wire
  `functions: seq[ResolvedFunction]` into `ResolvedModule`.

### Generic funcDefs

- **R14** — **`ResolvedFuncDef{id, name, params, returns, loc}`.**
  Helper `resolveFuncDef(fd: FunctionDefinition, localId: int)`
  assigns positional ids to params. Wire `funcDefs:
  seq[ResolvedFuncDef]` into `ResolvedGeneric`.

### Close-out

- **R15** — **Accessor surface pass + docs.** Readonly `proc
  foo*()` accessors for every private field across the new
  resolver types, same pattern as parser.nim. Mark PSR-41 Phase 1
  resolved in `bugs.md` and add a retrospective entry to
  `lessons.md`.

After R15: every declaration in the App tree carries a local `id`
that is its position in its immediate parent's list. Navigation
is explicit: `app.files[i].modules[j].functions[k]`. Function
bodies, type references, and expression resolution stay for later
PSRs.

## Verification

Same pattern as PSR-39 / PSR-40:
1. `nimble build` clean after each commit.
2. All positive examples compile and round-trip byte-identical.
3. Add a negative fixture once Phase 2 lands (unknown type
   reference in a function signature).
