# Block Indexing and Validation

## Context

The original six validation rules were framed as "validation". The better framing: **indexing**. During the type resolution phase (post-parse), we need efficient name lookups — `findModule`, `findGeneric`, `findFunction`, `findField`, `findVariant`, `findFile`. If we build those indices, the construction process itself enforces uniqueness for free. Rule #1 is not a separate check — it's a side effect of building `Table[string, int]`.

This plan unifies:
- **Rule #1** (unique module/generic/import names in file) → enforced by file-level index construction
- **Rules #3, #5, #6** → already enforced in the parser grammar
- **Rules #2, #4** → enforced as simple post-index checks on each block
- Efficient lookups for the forthcoming type resolution phase

All new types and indexing logic live in `src/validator.nim`. `parser.nim` is unchanged except for minimal readonly accessors that `validator.nim` needs to walk the AST.

## The Block Hierarchy

```
App (new root type in validator.nim)
 └── files: seq[IndexedFile]         — indexed by path
     └── modules: seq[IndexedModule] — indexed by name (unique)
     │   ├── functions               — indexed by name (overloading → seq[int])
     │   └── data (Struct | Union)
     │       ├── Struct.fields       — indexed by name (unique)
     │       └── Union.variants      — indexed by name (unique)
     │           └── variant.fields  — indexed by name (unique)
     └── generics: seq[IndexedGeneric]
         └── funcDefs                — indexed by name (overloading → seq[int])
     └── imports                     — flattened visible names (alias or original)
```

**Namespace rule within a file:** modules, generics, and imported visible names all share one namespace. Building the three indices must fail on duplicates across all three.

**Overloading:** functions are the only block where the same name can appear multiple times. Their index is `Table[string, seq[int]]`. Everything else is `Table[string, int]`.

## Design: Wrapper Types in validator.nim

`validator.nim` defines `Indexed*` wrapper types that wrap the raw AST from `parser.nim` with their name→position indices. This keeps `parser.nim` unchanged and all indexing concerns isolated.

```nim
# validator.nim
type
  IndexedStruct* = ref object
    struct: Struct
    fieldIndex: Table[string, int]

  IndexedVariant* = ref object
    variant: VariantDefinition
    fieldIndex: Table[string, int]

  IndexedUnion* = ref object
    union: Union
    variantIndex: Table[string, int]
    variants: seq[IndexedVariant]

  IndexedDataKind* = enum
    idkStruct, idkUnion
  IndexedData* = ref object
    case kind: IndexedDataKind
    of idkStruct: struct: IndexedStruct
    of idkUnion: union: IndexedUnion

  IndexedModule* = ref object
    module: Module
    data: Option[IndexedData]
    functionIndex: Table[string, seq[int]]

  IndexedGeneric* = ref object
    generic: Generic
    funcDefIndex: Table[string, seq[int]]

  IndexedFile* = ref object
    file: File
    modules: seq[IndexedModule]
    generics: seq[IndexedGeneric]
    moduleIndex: Table[string, int]
    genericIndex: Table[string, int]
    importIndex: Table[string, (int, int)]  # visible name → (import stmt idx, name idx)

  App* = ref object
    files: seq[IndexedFile]
    fileIndex: Table[string, int]  # absolute path → index in files
```

## Public Lookup Procs (all in validator.nim)

```nim
proc findFile*(app: App, path: string): int
proc findModule*(file: IndexedFile, name: string): int
proc findGeneric*(file: IndexedFile, name: string): int
proc findImport*(file: IndexedFile, visibleName: string): (int, int)
proc findFunction*(module: IndexedModule, name: string): seq[int]
proc findFuncDef*(generic: IndexedGeneric, name: string): seq[int]
proc findField*(s: IndexedStruct, name: string): int
proc findField*(v: IndexedVariant, name: string): int
proc findVariant*(u: IndexedUnion, name: string): int
```

All return `-1` or `@[]` for "not found".

## Indexing / Validation Flow

`validator.nim` exposes `proc index*(files: seq[File]): Result[App, string]` that:
1. Walks each `File` top-down, building `IndexedFile` with its indices.
2. On duplicate (for unique kinds), returns `err` with a precise message.
3. Recursively indexes modules, generics, structs, unions, variants.
4. Enforces rules #2 and #4 during indexing.

Per-block private procs: `indexFile`, `indexModule`, `indexGeneric`, `indexStruct`, `indexUnion`, `indexVariant`.

## Accessors needed from parser.nim

`validator.nim` needs readonly access to these raw AST fields. Add public accessor procs in `parser.nim`:

```nim
# File
proc modules*(file: File): seq[Module]
proc generics*(file: File): seq[Generic]
# path*, imports* already exist

# Module
proc name*(m: Module): string
proc data*(m: Module): Option[DataBlock]
proc functions*(m: Module): seq[Function]  # shortcut for funcList.functions
# Function
proc name*(fn: Function): string  # shortcut for fn.def.name

# Generic
proc name*(g: Generic): string
proc funcDefs*(g: Generic): seq[FunctionDefinition]

# FunctionDefinition
proc name*(fd: FunctionDefinition): string

# DataBlock
proc kind*(db: DataBlock): DataBlockKind
proc struct*(db: DataBlock): Struct
proc union*(db: DataBlock): Union
# (plus export DataBlockKind, dbkStruct, dbkUnion)

# Struct
proc fields*(s: Struct): seq[ArgumentDefinition]

# ArgumentDefinition
proc name*(ad: ArgumentDefinition): string

# Union
proc variants*(u: Union): seq[VariantDefinition]

# VariantDefinition
proc name*(v: VariantDefinition): string
proc fields*(v: VariantDefinition): seq[ArgumentDefinition]

# Import
proc names*(imp: Import): seq[ImportName]

# ImportName (export type)
proc name*(n: ImportName): string
proc alias*(n: ImportName): string
```

Types to export from parser.nim: `Module`, `Generic`, `Function`, `FunctionDefinition`, `DataBlock`, `DataBlockKind`, `Struct`, `Union`, `VariantDefinition`, `ArgumentDefinition`, `ImportName`.

## Wiring

1. `parser.nim` top-level `parse` (multi-file, returns `seq[File]`) — unchanged signature for now.
2. `asl.nim:compile` — calls `parser.parse` to get `seq[File]`, then `validator.index(files)` to get `App`, then uses `app.files[^1].file.asl(indentWidth)` for output.

## Critical Files

- `src/validator.nim` — new file, all indexing logic and types
- `src/parser.nim` — add public accessor procs and exports (no behavioral changes)
- `src/asl.nim` — call `validator.index` after `parser.parse`

## Verification

1. Build: `nimble build`
2. Positive cases (existing examples):
   - `./asl build examples/hello.asl`
   - `./asl build examples/problem001.asl`
   - `./asl build examples/data.asl`
   - `./asl build examples/match.asl`
   - `./asl build examples/sample.asl`
3. Negative cases:
   - File with two modules named `Foo` → duplicate module error
   - File with `module Foo:` and `import { Foo } from "./x.asl"` → duplicate name error
   - File with `import { X as Y } from "./a.asl"` and `module Y:` → duplicate name error
   - Struct with two fields named `x` → duplicate field error
   - Union with two variants named `A` → duplicate variant error
   - Module with neither data nor functions → rule #4 error
   - File with only imports → rule #2 error
4. Positive case (overloading):
   - Module with `func foo(a: i64)` and `func foo(a: str)` → both indexed under `foo`, `findFunction` returns `@[0, 1]`
