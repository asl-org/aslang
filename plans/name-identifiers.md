# Store Names as `Identifier` Instead of `string`

## Context

`validator.nim` reports duplicate-name errors as:

```
/path/to/file.asl: duplicate name 'Foo'
```

No line or column. The location exists — `identifierSpec` returns an
`Identifier` that carries a `Location` — but every AST type stores the
name as raw `string`, throwing the location away the moment the name is
handed to a `newX` constructor.

Every downstream phase (name resolution, type checking, codegen errors)
will want to point at the exact token. The fix is to replace every
name-bearing `string` field in the AST with an `Identifier` (name +
loc) so the location flows through the pipeline automatically.

This plan breaks the refactor into **small, independently reviewable
commits**. Each commit compiles cleanly, keeps all existing examples
green, and ideally ships one visible improvement on its own.

## `Identifier` (already exists)

```nim
type Identifier = ref object
  name: string
  loc: Location
```

Only used today in `Expression.variable` (`ekVariable: variable: Identifier`).
`identifierSpec` already returns this type; 24 call sites in
`parser.nim` currently discard the `loc` by passing `.name` to
constructors.

## API decision

Accessors on AST types return the `Identifier` (not `string`):

```nim
proc name*(m: Module): Identifier = m.name
```

Callers extract the textual name via `m.name.name` and the position via
`m.name.loc`. Alternative (keep accessors returning `string` and add
sibling `nameLoc*` procs per type) was rejected for adding double the
accessor surface.

## Commit Sequence

Each commit is a single focused change: one field (or a tight pair) on
one or two AST types, updated constructor, updated parse site, updated
formatter, updated accessor, updated validator error message if the
field is validator-visible. Target diff size: ~20–50 lines per commit.

### Phase A — Foundation

#### C1. Export `Identifier` with readonly accessors
- `type Identifier = ref object` → `type Identifier* = ref object`
- Add `proc name*(id: Identifier): string = id.name`
- Add `proc loc*(id: Identifier): Location = id.loc`
- No behavior change. `nimble build` green.

### Phase B — Validator-visible declaration names

Each commit in this phase ships a *user-visible* improvement: one more
duplicate-name error message now carries `line:col`.

#### C2. `Module.name: string` → `Identifier`
- Parser: `moduleHeaderSpec` already captures the `Identifier`; just
  stop extracting `.name`. Drop `ModuleHeader` tuple in favor of
  `Identifier` directly (or keep it as a type alias for clarity).
- `newModule` signature: `name: string` → `name: Identifier`.
- `asl(Module)` formatter: `module.name` → `module.name.name`.
- `name*(m: Module)` accessor: returns `Identifier`.
- `validator.indexFile`: module dup error becomes
  `fmt"{file.path}:{m.name.loc}: duplicate name '{m.name.name}'"`.
  Namespace-collision checks change from `.hasKey(m.name)` to
  `.hasKey(m.name.name)`.
- `indexModule` empty-module error also updates.
- **Verify**: `examples/errors/dup_module.asl` now reports the second
  `module Foo:` at `5:1`.

#### C3. `Generic.name: string` → `Identifier`
- Same shape as C2 for `Generic`.
- **Verify**: add a `dup_generic.asl` fixture under `examples/errors/`.

#### C4. `ArgumentDefinition.name: string` → `Identifier`
- Touches struct fields, union variant fields, and function parameters
  (all parse through `argumentDefinitionSpec`).
- Update `newArgumentDefinition`, `asl(ArgumentDefinition)`, parse site.
- Add `name*(ad: ArgumentDefinition): Identifier` — already exists but
  changes return type.
- `validator.indexStruct` / `indexVariant` error strings pick up `loc`.
- **Verify**: `examples/errors/dup_field.asl` now reports second `x`.

#### C5. `VariantDefinition.name: string` → `Identifier`
- `newVariantDefinition`, parse site, `asl`, accessor, validator.
- `validator.indexUnion` error string picks up `loc`.
- **Verify**: `examples/errors/dup_variant.asl` now reports second `A`.

#### C6. `ImportName.name: string` → `Identifier`
- `newImportName` signature, parser site, formatter, accessor.
- `alias` stays `string` for now; formatter/validator still use
  `alias.len > 0`.
- `validator.indexFile` import-dup error picks up `loc` when the
  collision is on the unaliased name.
- **Verify**: `examples/errors/import_module_collide.asl` reports the
  `module X` at the expected `line:col`.

#### C7. `ImportName.alias: string` → `Option[Identifier]`
- Ergonomic cleanup: kills the `""`-as-absent sentinel.
- `asl(ImportName)`: `if importName.alias.len > 0` → `if importName.alias.isSome`.
- `newImportName` signature updates to take `Option[Identifier]`.
- Parser site uses `some(aliasIdent)` / `none(Identifier)`.
- `validator.indexFile` import-dup helper (`visibleLoc`) uses the alias
  identifier's `loc` when present, else the name identifier's.
- **Verify**: `examples/errors/alias_collide.asl` reports the
  `module Y` at the expected `line:col`.

### Phase C — Declaration names, no current validator impact

These finish the "declaration" side of the AST. No user-visible change
today, but name resolution and type checking will need them.

#### C8. `FunctionDefinition.name: string` → `Identifier`
- Function declarations inside modules and generics.

#### C9. `Decorator.name: string` → `Identifier`, delete `Decorator.loc`
- `@export`-style decorators. Delete the now-redundant `loc` field on
  `Decorator` in the same commit (`newDecorator` signature drops
  `loc`; callers stop passing it).

### Phase D — Identifier *uses* (defer until Phase B/C land)

These are the places where an identifier appears as a reference, not a
declaration. Their locations will matter for "unknown type" / "unknown
variable" errors from the forthcoming type checker.

#### C10. `ArgumentType.root: string` → `Identifier`
- Type references (`Array`, `u32`, `User`). Affects `asl(ArgumentType)`
  and every `argumentTypeSpec` call.

#### C11. `FunctionCall.name` + `KeywordArgument.name` → `Identifier`
- Tightly related expression leaves.

#### C12. `Getter.source` + `Getter.property` → `Identifier`

#### C13. `LiteralInitializer.typeName` + `UnionInitializer.variantName` → `Identifier`

#### C14. `Assignment.target` + `VariantPatternField.name/binding` + `VariantPattern.variantName` → `Identifier`

## Verification per commit

After every commit:

1. `nimble build` — must succeed.
2. All positive examples compile:
   `./asl build examples/{hello,problem001,data,match,sample,overload}.asl`
3. All negative fixtures still fire the expected error (the message
   text may have improved in Phase B commits — update the relevant
   commit message accordingly).
4. For Phase B commits specifically: confirm the new error message now
   carries `line:col` by re-running the corresponding
   `examples/errors/*.asl` fixture and eyeballing the output.

## Not in scope

- Locations on `Import.source` (URL string, not an identifier).
- Locations on `StringLiteral.content`, integer/float literals, numeric
  text fields. These already carry their own `loc` on the containing
  AST node.
- Name resolution / cross-file duplicate checks.

## Decisions (approved)

1. **Scope**: go all the way through Phase D — 14 commits total.
2. **`ImportName`**: split across two commits — C6 changes `.name` to
   `Identifier`, C7 changes `.alias` to `Option[Identifier]`.
3. **`Decorator.loc`**: delete the redundant `loc` field in C9 as part
   of the same commit that converts `.name` to `Identifier`.
