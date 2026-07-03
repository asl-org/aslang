- [x] Tell me what is the role of every single markdown file.

- [x] Change the `aslb` file prefix to `aslr` representing asl runtime file.

- [x] Re-enable the exact floating point value check but don't return error instead print it as warning that the closest approximate value will be used.

- [x] In import statements adding `.asl` suffix in the file name is optional the compiler will resolve the path if the file is not found then it would check the same path with auto appened `.asl` suffix

# --- DDD refactor: align every layer with the locked domain grammar. ---
# Ordering below is dependency-forward; each item should leave the
# compiler building + green so the next can pick up cleanly.

- [x] Lock the domain grammar as source-of-truth. Extract the agreed grammar into a stable file (e.g. `grammar.md` or an appendix in `overview.md`) that parser/resolver/analyzer type definitions can be traced back to. Every subsequent task references this file when it renames or introduces types.

- [x] Rename data-block variants to match the grammar's `*Def` suffix: `Struct` → `StructDef`, `Union` → `UnionDef`, existing data-kind `Literal` → `LiteralDef`. Mechanical wave across parser + resolver + analyzer + accessors + tests. Deliberately low-value on its own — this task is a naming alignment so later refactors read cleanly.

- [x] ~~Introduce role-typed identifiers as distinct newtypes wrapping `Identifier`~~ — dropped. The role names (`VarName`, `ModuleName`, `GenericName`, `FunctionName`, `TypeName`, `Variant`, `Field`, `Binding`, `Property`, `Source`, `LiteralRef`, `ImportedType`) in `grammar.md` are documentation labels that clarify each identifier position's role at review time; in the code every one of them stays as `Identifier`. Distinct newtypes would have required ~60 lines of borrow-op boilerplate to protect against a small class of realistic mistakes — the readability-of-the-grammar goal is enough on its own. Left checked as "handled" so the roadmap numbering stays stable.

- [x] Move `Setter` from `Expression` to `Statement` in the AST types. Add `VariablePattern` as a first-class `CaseDef` variant (structurally distinct from `LiteralPattern`, `UnionPattern`). Both changes align the AST with what the grammar actually says and eliminate downstream "is this really a value?" and "is this literal or variable?" branches.

- [x] Split `ArgumentType` at the resolver level into a tagged union: `ResolvedArgumentType: ResolvedModuleArgumentType | ResolvedGenericArgumentType`. Resolver disambiguates at name-lookup time (module vs generic). Every downstream "is this a module or a generic?" check collapses into a `case` arm.

- [ ] Merge analyzer phase-A into the resolver. Move the definition-level `Analyzed*` types (`AnalyzedStructDef`, `AnalyzedUnionDef`, `AnalyzedVariant`, `AnalyzedData`, `AnalyzedModuleDefinition`, `AnalyzedFileDefinition`, `AnalyzedAppDefinition`, `AnalyzedGeneric`, `AnalyzedDefinedType`) — plus their build procs and definition-level `analyze*` overloads — into the resolver. Fold their added fields into the `Resolved*` counterparts via accessor delegation from the parser back-ref. Delete the now-redundant analyzer-side wrappers.
  - [x] **Sub-task 6a.** Enrich `Resolved*` def-level types with the accessors/indexes that phase-A currently adds on the analyzer side: `ResolvedStructDef` gains `fieldIndex` + `findField` + `genericTypeIndex` accessor, `ResolvedVariant` gains `fieldIndex` + `findField`, `ResolvedUnionDef` gains `variantIndex` + `findVariant` + `genericTypeIndex` accessor, `ResolvedModule` gains `funcNameArityIndex` + `findFunctionDefs(name, arity, public)`, `ResolvedGeneric` gains `funcNameArityIndex` + `findFunctionDefs(name, arity)`. Additive change; the analyzer's phase-A types stay in place but the resolver now has everything phase-A produces directly available.
  - [ ] **Sub-task 6b.** Migrate the analyzer's body-level walkers to consume `Resolved*` types via the new accessors instead of the analyzed wrappers. Delete `Analyzed{StructDef, UnionDef, Variant, LiteralDef, Data, ModuleDefinition, Generic, DefinedType, FileDefinition, AppDefinition, FunctionDefinition, ArgumentDefinition}` + their build procs + their `analyze*` overloads. Update the `analyze()` entry point.
  - [ ] **Sub-task 6c.** Retire `ResolvedArgumentType`'s parser-level `root: Module` back-ref in favour of `resolvedModule: ResolvedModule` — moves the "look up scope symbol" work that the analyzer currently does in phase-A into the resolver proper. Requires restructuring the resolver so ResolvedModules exist before argument-type resolution runs.

- [ ] Move impl-list resolution + arity check + generic-constraint satisfaction check into the resolver. Every `StructInit`, `UnionInit`, and `FunctionCall`-with-receiver carries `resolvedImpls: seq[ResolvedArgumentType]` (possibly empty) that is arity- and constraint-validated at resolve time. The impl list becomes a provably valid value, not a claim the analyzer has to re-verify.

- [ ] Collapse the `default` / `impl` arms of `StructRef` and `UnionRef` into a single shape carrying `resolvedImpls: seq[ResolvedArgumentType]`. Analyzer's `GenericImplMap` initialization becomes a single code path: empty seq → empty map, non-empty → pre-populated. Kill the two-branch "did the user provide impls?" dispatch that today lives at every init/call site.

- [ ] Strict-DDD sweep — audit every `if x.kind == Foo` on domain values across parser/resolver/analyzer and convert to `case x.kind:` matches with exhaustive arms. Also audit multi-return procs: rewrite as single-expression bodies via `Result` + `?` chaining, or split into helpers if the natural shape needs a third indent level. Rule: `if` on domain kinds and mid-body `return`s are slip-ups; the type checker should be doing the branch-coverage work.

- [ ] Consider language-level support for empty union variants (drops parser's "≥1 field per variant" rule). If yes, revisit the lander port's `Event.Timeout { padding: u8 }` sentinel when it's next touched. Open question rather than a mandate.

- [ ] Sync `documentation.md` with the final vocabulary (data-block names, role-typed identifiers, ArgumentType shape, unified default/impl semantics) and `overview.md` with the merged-resolver / slimmer-analyzer pipeline. Cross-link the grammar file locked in the first task so every doc traces back to the same spec.
