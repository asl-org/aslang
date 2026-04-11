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

### Global ID
Every block in the `App` tree has a **global id** — a typed value
that encodes the full path from the root to the block as a sequence
of local positions. A module's global id is `(fileId, moduleId)`.
A function's global id is `(fileId, moduleId, functionId)`. A
variant field's global id is `(fileId, moduleId, variantId, fieldId)`.

Each block kind has its own strongly-typed id so that the type
system prevents mixing them up. The id is stored on the block
itself so a resolved node is self-contained: given a
`ResolvedFunction` you already know its file, its module, and its
local position without walking back up the tree.

Within an id the terminal field is always named `id` (the local
position in the immediate parent); the preceding fields name each
ancestor level: `file`, `module`, `generic`, `function`, `variant`,
`import`, etc. Examples:

```nim
type
  FileId* = object
    id: int              # index in app.files

  ModuleId* = object
    file: int            # index in app.files
    id: int              # index in file.modules

  FunctionId* = object
    file: int
    module: int
    id: int              # index in module.functions

  VariantFieldId* = object
    file: int
    module: int
    variant: int
    id: int              # index in variant.fields
```

The denormalized ancestor fields (each level keeps copies of its
parent's positions) trade a few bytes per block for O(1) navigation
from any id back to the root.

### Ref
For Phase 1 the only cross-scope reference that gets resolved is
imports → target file (`ResolvedImport.targetFileId: FileId`). A
richer `Ref` tagged union that handles primitives /
cross-file-module / cross-file-generic / locals / params / etc.
belongs to Phases 2 and 3. It's mentioned here only so the reader
knows what's coming.

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

## Complete ID Type List (Phase 1)

10 typed ID objects cover every declaration kind. The raw parser
`ArgumentDefinition` appears in four contexts, which the resolver
splits into two semantic categories:

- **Fields** (data members): struct fields and variant fields.
  Identified by **`FieldId`**.
- **Arguments** (computation inputs): function params, funcDef
  params, and — when Phase 3 lands — temporary local bindings
  inside function bodies. Identified by **`ArgumentId`**.

```nim
type
  FileId* = object
    id: int                   # index in app.files

  ModuleId* = object
    file: int
    id: int                   # index in file.modules

  GenericId* = object
    file: int
    id: int                   # index in file.generics

  ImportId* = object
    file: int
    id: int                   # index in file.imports

  ImportNameId* = object
    file: int
    importStmt: int           # parent import statement
    id: int                   # index in imp.names

  FunctionId* = object
    file: int
    module: int
    id: int                   # index in module.functions

  FuncDefId* = object         # inside a generic block
    file: int
    generic: int
    id: int                   # index in generic.funcDefs

  VariantId* = object
    file: int
    module: int
    id: int                   # index in union.variants

  # Data members: struct fields and variant fields
  FieldParentKind* = enum
    fpkStruct                  # parent = ModuleId
                               # (struct is implicit: module.data.struct)
    fpkVariant                 # parent = VariantId

  FieldId* = object
    id: int                   # local position in owner's fields list
    case parentKind*: FieldParentKind
    of fpkStruct:  structParent*: ModuleId
    of fpkVariant: variantParent*: VariantId

  # Computation inputs: function / funcDef params (and Phase 3 locals)
  ArgumentParentKind* = enum
    apkFunction                # parent = FunctionId
    apkFuncDef                 # parent = FuncDefId
    # Phase 3 will add apkLocal for temporary bindings inside
    # function bodies — same ArgumentId shape, different parent.

  ArgumentId* = object
    id: int                   # local position in owner's params list
    case parentKind*: ArgumentParentKind
    of apkFunction: functionParent*: FunctionId
    of apkFuncDef:  funcDefParent*: FuncDefId
```

Each resolved block type carries the corresponding global id as its
first field (e.g. `ResolvedModule.id: ModuleId`,
`ResolvedFunction.id: FunctionId`, `ResolvedField.id: FieldId`,
`ResolvedArgument.id: ArgumentId`).

The ancestor chain is preserved through the tagged `parent*Id`:
a struct field's `FieldId` carries a `ModuleId` (→ `file` +
`module`), giving the full path `file → module → struct → field`.
A variant field's `FieldId` carries a `VariantId` (→ `file` +
`module` + `variant`), giving `file → module → variant → field`.
A funcDef parameter's `ArgumentId` carries a `FuncDefId` (→ `file`
+ `generic` + `funcDef`), giving `file → generic → funcDef → param`.

## Resolved Types (Mirror of `Indexed*`)

```nim
type
  ResolvedApp* = ref object
    files: seq[ResolvedFile]
    fileIndex: Table[string, FileId]     # absolute path → FileId

  ResolvedFile* = ref object
    id: FileId
    path: string
    imports: seq[ResolvedImport]
    modules: seq[ResolvedModule]
    generics: seq[ResolvedGeneric]

  ResolvedImport* = ref object
    id: ImportId
    source: string
    targetFileId: FileId
    names: seq[ResolvedImportName]
    loc: Location

  ResolvedImportName* = ref object
    id: ImportNameId
    name: Identifier
    alias: Option[Identifier]
    loc: Location

  ResolvedModule* = ref object
    id: ModuleId
    decorators: seq[Decorator]           # raw until later
    name: Identifier
    data: Option[ResolvedData]
    functions: seq[ResolvedFunction]
    loc: Location

  ResolvedGeneric* = ref object
    id: GenericId
    decorators: seq[Decorator]
    name: Identifier
    funcDefs: seq[ResolvedFuncDef]
    loc: Location

  ResolvedField* = ref object            # struct field or variant field
    id: FieldId
    name: Identifier
    argType: ArgumentType                # raw until Phase 2
    loc: Location

  ResolvedArgument* = ref object         # function or funcDef parameter
    id: ArgumentId
    name: Identifier
    argType: ArgumentType                # raw until Phase 2
    loc: Location

  ResolvedStruct* = ref object
    fields: seq[ResolvedField]
    loc: Location

  ResolvedVariant* = ref object
    id: VariantId
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
    id: FunctionId
    decorators: seq[Decorator]
    name: Identifier
    params: seq[ResolvedArgument]
    returns: ArgumentType                # raw
    body: StatementList                  # raw — Phase 3 resolves
    loc: Location

  ResolvedFuncDef* = ref object
    id: FuncDefId
    name: Identifier
    params: seq[ResolvedArgument]
    returns: ArgumentType
    loc: Location
```

`ResolvedField` and `ResolvedArgument` are structurally identical
but carry different id types (`FieldId` vs `ArgumentId`) to reflect
the two semantic categories. The type system prevents passing a
struct field where a function parameter is expected and vice
versa — useful when Phase 3 starts resolving expression references
to field accesses vs. variable lookups.

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

Phase 1 breaks into **17 bite-sized commits**. Each one adds exactly
one id type + its corresponding block type (or one wiring step),
compiles cleanly, and leaves every existing example working. Target
~20–50 line diffs per commit — same pacing as PSR-40.

Each commit lives entirely in `src/resolver.nim` except R1 which
also touches `src/asl.nim` and R17 which touches the docs.

### Skeleton

- **R1** — **Create `src/resolver.nim`.** Empty `ResolvedApp* = ref
  object`. Stub `proc resolve*(app: App): Result[ResolvedApp,
  string] = ok(ResolvedApp())`. Wire into `asl.nim:compile`
  right after `validator.index`. Pipeline builds, output unchanged.

### File level

- **R2** — **`FileId` + `ResolvedFile{id, path}`.** Add
  `files: seq[ResolvedFile]` and `fileIndex: Table[string, FileId]`
  to `ResolvedApp`. `resolve` iterates `app.files` building
  `ResolvedFile(id: FileId(id: i), path: f.file.path)`.

### Imports

- **R3** — **`ImportId` + `ResolvedImport{id, source,
  targetFileId}`.** Wire `imports: seq[ResolvedImport]` into
  `ResolvedFile`. `targetFileId` from `ResolvedApp.fileIndex`
  lookup of the resolved import path.
- **R4** — **`ImportNameId` + `ResolvedImportName{id, name,
  alias}`.** Wire `names: seq[ResolvedImportName]` into
  `ResolvedImport`.

### Modules and generics (skeletons, body raw)

- **R5** — **`ModuleId` + `ResolvedModule{id, decorators, name,
  loc}`.** `data` and `functions` stay as raw AST pointers for
  now; wired in later commits. Wire `modules:
  seq[ResolvedModule]` into `ResolvedFile`.
- **R6** — **`GenericId` + `ResolvedGeneric{id, decorators, name,
  loc}`.** `funcDefs` stays raw. Wire `generics:
  seq[ResolvedGeneric]` into `ResolvedFile`.

### Field infrastructure

- **R7** — **`FieldParentKind` + `FieldId` (variant) +
  `ResolvedField{id, name, argType, loc}`.** Sets up the data-
  member type used by struct fields and variant fields. Defines
  the type + a factory helper
  `newFieldId(parentKind, parentId, localId)`. Stand-alone — not
  wired into anything yet.

### Struct path

- **R8** — **`ResolvedStruct{fields, loc}`.** Helper
  `resolveStruct(s: Struct, parent: ModuleId): ResolvedStruct`
  builds `ResolvedField` entries with `parentKind=fpkStruct`.

### Union path

- **R9** — **`VariantId` + `ResolvedVariant{id, name, fields,
  loc}`.** Helper `resolveVariant(v: VariantDefinition, parent:
  ModuleId, localId: int)` builds `ResolvedField` entries with
  `parentKind=fpkVariant`.
- **R10** — **`ResolvedUnion{variants, loc}`.** Helper
  `resolveUnion(u: Union, parent: ModuleId): ResolvedUnion`.

### Data block + module wiring

- **R11** — **`ResolvedData` tagged union** (`rdkStruct | rdkUnion`).
  Helper `resolveData(db: DataBlock, parent: ModuleId):
  ResolvedData`.
- **R12** — **Wire `ResolvedData` into `ResolvedModule.data`.**
  `data` field switches from raw `Option[DataBlock]` to
  `Option[ResolvedData]`. `resolveModule` now calls
  `resolveData`.

### Argument infrastructure

- **R13** — **`ArgumentParentKind` + `ArgumentId` (variant) +
  `ResolvedArgument{id, name, argType, loc}`.** Sets up the
  computation-input type used by function params, funcDef
  params, and (Phase 3) local bindings. Defines the type +
  factory helper. Stand-alone.

### Module functions

- **R14** — **`FunctionId` + `ResolvedFunction{id, decorators,
  name, params, returns, body, loc}`.** `body: StatementList`
  stays raw. Helper `resolveFunction(fn: Function, parent:
  ModuleId, localId: int)` builds `ResolvedArgument` params with
  `parentKind=apkFunction`. Wire `functions:
  seq[ResolvedFunction]` into `ResolvedModule`.

### Generic funcDefs

- **R15** — **`FuncDefId` + `ResolvedFuncDef{id, name, params,
  returns, loc}`.** Helper `resolveFuncDef(fd:
  FunctionDefinition, parent: GenericId, localId: int)` builds
  `ResolvedArgument` params with `parentKind=apkFuncDef`. Wire
  `funcDefs: seq[ResolvedFuncDef]` into `ResolvedGeneric`.

### Close-out

- **R16** — **Accessor surface pass.** Every new type gets
  readonly `proc foo*()` accessors (same pattern as parser.nim).
  One focused pass rather than sprinkled through R2–R15.
- **R17** — **Docs: mark PSR-41 Phase 1 resolved in `bugs.md`,
  retrospective entry in `lessons.md`.**

After R17: every declaration in the App tree carries a typed
global id (`FileId`, `ModuleId`, `FunctionId`, `FieldId`,
`ArgumentId`, etc.). A caller can navigate
`app.files[fnId.file].modules[fnId.module].functions[fnId.id]`
in O(depth). Function bodies and type references remain raw —
they become IDs in Phase 2 (signature type refs) and Phase 3
(expression resolution), each a separate PSR.

## Verification

Same pattern as PSR-39 / PSR-40:
1. `nimble build` clean after each commit.
2. All positive examples compile and round-trip byte-identical.
3. Add a negative fixture once Phase 2 lands (unknown type
   reference in a function signature).
