# Derivation audit — Resolved/Analyzed types vs their predecessors

## Principle

The compilation pipeline is:

```
Parse  →  Resolve  →  Analyze
```

Each layer's types should carry a back-reference to the previous layer's
type (`Resolved*` holds `parsed: <Parser*>`; `Analyzed*` holds
`resolved: <Resolver*>`) and **derive metadata via accessors** rather
than duplicating it into separate fields.

Canonical conformant examples to mirror:

- `ResolvedFunctionDefinition` (`parsed: FunctionDefinition`) — name /
  arity / loc / public / asl all accessor-delegated to `parsed.*`.
- `ResolvedVariant`, `ResolvedUnion`, `ResolvedFile`, `ResolvedGeneric` —
  same shape.
- `ResolvedModule` *almost* conforms but stores a redundant
  `loc: Location` field instead of delegating to `parsed.loc`.
- Analyzer side already largely conforms via `resolved: <Resolved*>`.

## Categories

- **DUP** — back-ref exists *and* a field duplicates info reachable
  through it.
- **MISSING** — no back-ref at all; the type stores parser/resolver
  data raw.
- **INTENT** — looks like a duplication but is actually a distinct
  concept (use-site loc, analyzer cache, no resolver counterpart, etc.).

## Resolver layer (target: add `parsed: <Parser*>`)

| Type | Back-ref? | Duplicated / raw fields | Should come from | Category |
|------|-----------|-------------------------|------------------|----------|
| `ResolvedImportedType` | none | `name`, `binding` | `parsed: ImportedType.name / .binding` | **MISSING** |
| `ResolvedImport` | `parsed: parser.File` (wrong target — currently the *imported* file, not the parser `Import` node) | `loc` | `parsed: Import.loc` | **DUP** (wrong back-ref) |
| `ResolvedArgumentDefinition` | none | `name` | `parsed: ArgumentDefinition.name` | **MISSING** |
| `ResolvedExternFunction` | none | `ffi: string` | `parsed: ExternFunction.ffi` | **MISSING** |
| `ResolvedModuleArgumentType` | none (only `root: Module`, parser type) | `loc` | `parsed: ArgumentType.loc` | **MISSING** |
| `ResolvedGenericArgumentType` | none (only `generic: Generic`, parser type) | `loc` | `parsed: ArgumentType.loc` | **MISSING** |
| `ResolvedFunctionRef` | none | `name`, `arity`, `loc` | `parsed: FunctionCall.name / .args.len / .loc` | **MISSING** (3 fields) |
| `ResolvedStruct` | none | (no scalar dups; parser `Struct` lost so loc unreachable) | `parsed: Struct` | **MISSING** |
| `ResolvedGetter` | none | `source`, `property` | `parsed: Getter.source / .property` | **MISSING** |
| `ResolvedLiteralInitializer` | none | `value: Literal` | `parsed: LiteralInitializer.value` | **MISSING** |
| `ResolvedKeywordArgument` | none | `name` | `parsed: KeywordArgument.name` | **MISSING** |
| `ResolvedStructInitializer` | none | (loc derived via `argType.loc`) | `parsed: StructInitializer` | **MISSING** |
| `ResolvedUnionInitializer` | none | `variant: Identifier` | `parsed: UnionInitializer.variant` | **MISSING** |
| `ResolvedFunctionCall` | none | (parser `FunctionCall` lost; loc unreachable) | `parsed: FunctionCall` | **MISSING** |
| `ResolvedAssignment` | none | `target: Identifier` | `parsed: Assignment.target` | **MISSING** |
| `ResolvedMutation` | none | (parser `Mutation` lost) | `parsed: Mutation` | **MISSING** |
| `ResolvedMatchExpression` | none | `loc` | `parsed: MatchExpression.loc` | **MISSING** |
| `ResolvedModule` | `parsed: Module` | `loc: Location` (accessor returns `module.loc` not `module.parsed.loc`) | `parsed.loc` | **DUP** |
| `ResolvedUserFunction` | none | (parser `UserFunction` lost; loc via `funcDef.loc`) | `parsed: UserFunction` | **MISSING** |
| `ResolvedDefinedType` | none | `id: int` | file-local index — distinct concept | **INTENT** |

**Conformant** (already follow the model): `ResolvedFunctionDefinition`,
`ResolvedVariant`, `ResolvedUnion`, `ResolvedFile`, `ResolvedGeneric`,
`ResolvedCaseBlock`.

## Analyzer layer (target: add `resolved: <Resolved*>`)

| Type | Back-ref? | Duplicated / raw fields | Should come from | Category |
|------|-----------|-------------------------|------------------|----------|
| `AnalyzedArgumentDefinition` | none | `name` | `resolved: ResolvedArgumentDefinition.name` | **MISSING** |
| `AnalyzedGenericArgumentType` | `resolved: ResolvedGeneric` | `loc: Location` | use-site loc, distinct from declaration; consider routing through a `parsed: ArgumentType` field if added to resolver | **INTENT** (follow-up of resolver fix) |
| `AnalyzedModuleArgumentType` | `resolved: ResolvedModuleArgumentType` | `module: ResolvedModule` | derivable via app lookup but stored for speed | **INTENT** (analyzer cache) |
| `AnalyzedStruct` | none | (no scalar dups; pairs with resolver gap) | `resolved: ResolvedStruct` | **MISSING** |
| `AnalyzedFunctionRef` | none | `argType`, `funcDefs`, no loc | `resolved: ResolvedFunctionRef` | **MISSING** |
| `AnalyzedVariable` | none | `name`, `argType` | no resolver-side counterpart (`ResolvedVariable` doesn't exist) | **INTENT** |
| `AnalyzedModule` | none (transitively via `def: AnalyzedModuleDefinition`) | — | `resolved: ResolvedModule` | **MISSING** (mild — already reachable transitively) |
| `AnalyzedFile` | none | imports / definedTypes / modules raw | `resolved: ResolvedFile` | **MISSING** |
| `AnalyzedVariantPattern` | `resolved: VariantPattern` (**parser type, not resolver**) | naming inconsistency — field called `resolved` but holds parser type | no `ResolvedVariantPattern` exists; resolver also stores parser type raw | **INTENT** (naming smell) |

**Conformant**: `AnalyzedImportedType`, `AnalyzedImport`,
`AnalyzedFunctionDefinition`, `AnalyzedVariant`, `AnalyzedUnion`,
`AnalyzedLiteralBlock`, `AnalyzedGetter`, `AnalyzedFunctionCall`,
`AnalyzedKeywordArgument`, `AnalyzedStructInitializer`,
`AnalyzedUnionInitializer`, `AnalyzedCaseBlock`,
`AnalyzedMatchExpression`, `AnalyzedAssignment`, `AnalyzedMutation`,
`AnalyzedModuleDefinition`, `AnalyzedGeneric`, `AnalyzedUserFunction`,
`AnalyzedExternFunction`, `AnalyzedApp`.

## Counts

- Resolver: **17 MISSING + 1 DUP** + 1 INTENT.
- Analyzer: **5 MISSING + 3 INTENT**.

## Execution plan

Resolver first. Each commit ≤ 100 lines changed. Order (leaf-level →
top-level, to minimize call-site ripple):

1. `ResolvedImportedType` (add `parsed: ImportedType`).
2. `ResolvedImport` (replace `parsed: parser.File` with `parsed: Import` + keep target-file lookup separate; this is the DUP fix).
3. `ResolvedArgumentDefinition`.
4. `ResolvedExternFunction`.
5. `ResolvedModuleArgumentType` + `ResolvedGenericArgumentType` (paired; both add `parsed: ArgumentType`).
6. `ResolvedFunctionRef`.
7. `ResolvedStruct`.
8. `ResolvedGetter`.
9. `ResolvedLiteralInitializer`.
10. `ResolvedKeywordArgument`.
11. `ResolvedStructInitializer` + `ResolvedUnionInitializer` (paired).
12. `ResolvedFunctionCall`.
13. `ResolvedAssignment` + `ResolvedMutation` (paired).
14. `ResolvedMatchExpression`.
15. `ResolvedModule` (DUP fix — drop the redundant `loc` field).
16. `ResolvedUserFunction`.

Then analyzer side (5 MISSING).

For each: add the back-ref field, update the constructor to take it,
add `parsed*` accessor, route name/loc/etc. delegating accessors to it,
delete the raw fields, fix every constructor call site, verify build +
tests don't regress.

Verification per commit: `nimble build`, `nimble test` (187/187),
`./test.sh` (15/35 baseline; marker `:229:15`).
