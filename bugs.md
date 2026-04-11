# Bugs & Issues

## Open

### Match expression

- [x] **PSR-31: Add CasePattern AST type** — Done. `oneOf(integerLiteral, identifier)` variant.
- [x] **PSR-32: Add CaseBlock AST type and spec** — Done. `case pattern: statementList` using `blockSpec`.
- [x] **PSR-33: Add MatchExpression AST type and spec** — Done. `match expr: caseBlock+` using `blockSpec`. `skMatch` variant in Statement.
- [x] **PSR-34: Wire match into statementSpec** — Done. Match tried before indentation in `statementLineSpec` since it handles its own indentation via `blockSpec`. `aslBlock` dispatches block statements to multi-line formatting.

- [x] **PSR-35: Add variant pattern to case blocks** (`src/parser.nim`) [medium] — Done. `VariantPattern` with `variantName` + `seq[VariantPatternField]` (name: binding pairs). Uses `contained` + `separatedBy` for `{ field: binding }`. Tried before variable in `casePatternSpec` `oneOf` since `{` disambiguates.

- [x] **PSR-37: Add union initializer expression** (`src/parser.nim`) [medium] — Done. `Type.Variant { fields }` as `UnionInitializer`. Tried before non-primitive and function call in `oneOf` since all start with `argumentType` but disambiguate by `.Variant {` vs `{` vs `.method(`.

- [x] **PSR-38: Add import aliasing** (`src/parser.nim`) [medium] — Done. `ImportName` type with `name` and optional `alias` (empty string if none). `importNameSpec` parses `identifier ("as" identifier)?`. Import stores `seq[ImportName]` instead of `seq[string]`.

### Dependency resolution

- [ ] **PSR-36: Recursive BFS dependency resolver with cycle detection** (`src/parser.nim` or `src/asl.nim`) [high] — After parsing the root file, extract import sources, tokenize+parse each dependency, and recurse. BFS traversal ensures dependencies are resolved breadth-first. Detect cycles by tracking the current resolution path — if a file is encountered that's already on the path, report the cycle with the full dependency chain. Returns all parsed Files in dependency order.

### Name resolution

- [ ] **PSR-41 Phase 2: Signature-level type references** (`src/resolver.nim`) [medium] — Resolve `ArgumentType.root` everywhere it appears in a signature (struct/variant field types, function parameter types, return types). Each type reference becomes a `Ref` pointing at one of: primitive, current-file module, current-file generic, imported module, imported generic. Function bodies still untouched. See `plans/id-resolution.md` Phase 2 for design.
- [ ] **PSR-41 Phase 3: Function-body / expression resolution** (`src/resolver.nim`) [large] — Resolve `Assignment.target`, `Expression.variable`, `Getter.source/property`, `FunctionCall.name`, pattern bindings, etc. Requires expression type inference (Getter.property needs the source's type; VariantPattern.variantName needs the subject's type). Effectively a compact type checker; needs a separate detailed plan before execution.

### Parser cleanup (round 2)

- [ ] **PSR-15: Remove `StringContent` AST type** (`src/parser.nim`) [low] — Only used internally by string parsing specs, never appears in any AST node that leaves the parser. Simplify to return `string` or `Token` directly.

- [ ] **PSR-16: Unwrap `StatementList` and `FunctionList`** (`src/parser.nim`) [low] — Thin wrappers around `seq[Statement]` / `seq[Function]` with no extra fields. Replace with raw `seq` types in `Function` and `Module`.

- [ ] **PSR-17: Unwrap `ArgumentDefinitionList` and `ArgumentList`** (`src/parser.nim`) [low] — Wrappers around `seq` + `loc`, but `loc` is only the position of `(` which isn't used downstream. Replace with raw `seq` types in `FunctionDefinition` and `FunctionCall`.

- [ ] **PSR-18: Remove `EmptyLine` and `Comment` AST types** (`src/parser.nim`) [low] — Parsed but never stored. `ignorableLineSpec` maps them to `Location` which callers discard. The specs can return `Location` or `void` directly without dedicated types.

- [ ] **PSR-19: Add `withLeadingLines(spec)` combinator** (`src/parser.nim`) [low] — `importBlockSpec`, `fileItemBlockSpec`, and `funcBlockSpec` all follow the same pattern: `skip any(ignorableLineSpec) + parse spec`. Extract into a reusable combinator.

### Other

- [ ] **`except CatchableError:` is still broad** (`cli.nim:105`) [low] — Narrow to the exact exception types thrown by `argparse` (e.g., `UsageError`, `ValueError`) once those are confirmed.
- [ ] **`Token` is `ref object`** (`tokenizer.nim:72`) [low] — Each token is heap-allocated. For a tokenizer producing thousands of tokens, a plain `object` in `seq[Token]` avoids GC pressure since tokens are small (enum + string + two ints).
- [ ] **Empty list `loc` falls back to `newLocation()` which is incorrect** (`parser.nim`) [medium] — `FunctionList.loc` returns `1:1` for empty lists instead of the actual source position. Needs proper location propagation from the parent context.
- [x] **`readFileSafe` crashes on missing files** (`parser.nim`) — Caught only `IOError`, but on macOS `getFileSize` throws `OSError` for a missing file — the parser propagated an unhandled exception. Fixed by calling `fileExists` up front and catching `CatchableError` for everything else. Surfaced while building the `examples/errors/missing_file.asl` fixture.

## Resolved

### Parser combinator refactor (PSR-01 to PSR-09)

- [x] **PSR-01** — Combinator module with `Spec[T]`, `run`, `oneOf`, `any`, `atLeastOne`, `optional`, `separatedBy`, `map`, `contained`.
- [x] **PSR-02** — Leaf token specs: `tokenSpec`, `punctuationSpec`, `spaceSpec`, `newlineSpec`, `alphabetSpec`, `digitSpec`, `utf8Spec`.
- [x] **PSR-03** — Identifier parsing with `identifierSpec`, `keywordSpec`.
- [x] **PSR-04** — Comment, empty line, indentation specs. Fixed comment parsing to stop at newlines.
- [x] **PSR-05** — String literal parsing with `escapedSpec` factory, `stringContentSpec`, `stringLiteralSpec`.
- [x] **PSR-06** — Type and argument definition parsing. Forward-declared `argumentTypeSpec`, `separatorSpec` factory.
- [x] **PSR-07** — Expression, assignment, statement parsing. Forward-declared `expressionSpec`, `oneOf` + `map` composition.
- [x] **PSR-08** — Function, module, file parsing. `blockSpec`, `atLeastOne`, `any` for block-level specs.
- [x] **PSR-09** — Deleted `AslNode` infrastructure and dead code. -231 lines.

### Combinator improvements (PSR-10 to PSR-14)

- [x] **PSR-10** — Used `contained` in `argumentDefinitionListSpec`.
- [x] **PSR-11** — Merged escape spec factories into `escapedSpec(char, charSpec)`.
- [x] **PSR-12** — Fixed `any` backtracking: `parser.run(spec)` instead of `spec.parseFn(parser)`.
- [x] **PSR-13** — Fixed `separatedBy` backtracking: sep+element wrapped into atomic `pairSpec`.
- [x] **PSR-14** — Fixed `optional` backtracking.

### Name resolution (resolved)

- [x] **PSR-41 Phase 1: ID-based structural resolution of the App tree** (`src/resolver.nim`) — Done in 15 bite-sized commits (R1–R15). New `src/resolver.nim` owns a parallel `Resolved*` wrapper tree: `ResolvedApp → ResolvedFile → ResolvedModule / ResolvedGeneric → ResolvedFunction / ResolvedFuncDef → ResolvedArgument`; `ResolvedModule.data: Option[ResolvedData]` holds `ResolvedStruct` / `ResolvedUnion` → `ResolvedVariant` → `ResolvedField`. Every declaration carries a local `int id` (its position in its immediate parent). Typed global ids were considered and rejected as speculative — can be layered in later if Phase 2/3 need cross-block navigation. Function bodies (`StatementList`), type references (`ArgumentType`), and `ResolvedImportName.name`/`alias` stay raw; Phases 2 and 3 (separate entries above) resolve them.

### Location tracking

- [x] **PSR-40: Store names as `Identifier` instead of `string`** (`src/parser.nim`, `src/validator.nim`) — Done in 14 bite-sized commits (C1–C14). Every name-bearing field in the AST (`Module.name`, `Generic.name`, `ArgumentDefinition.name`, `VariantDefinition.name`, `ImportName.name`, `ImportName.alias`, `FunctionDefinition.name`, `Decorator.name`, `ArgumentType.root`, `FunctionCall.name`, `KeywordArgument.name`, `Getter.source`, `Getter.property`, `LiteralInitializer.typeName`, `UnionInitializer.variantName`, `Assignment.target`, `VariantPatternField.name`, `VariantPatternField.binding`, `VariantPattern.variantName`) now holds an `Identifier` carrying a `Location`. `ImportName.alias` flipped from `""`-sentinel `string` to `Option[Identifier]`. `Decorator.loc` deleted (redundant once the name carries its own loc). Validator errors now report exact `line:col`. `Identifier.name` renamed to `Identifier.value` so the common chain reads `m.name.value` / `m.name.loc` instead of the awkward `m.name.name`. Plan in `plans/name-identifiers.md`.

### Block indexing and validation

- [x] **PSR-39: Block indexing, validation rules, and lookup infrastructure** (`src/validator.nim`, `src/parser.nim`, `src/asl.nim`) — Done. New `src/validator.nim` owns all indexing. Wrapper types (`IndexedFile`, `IndexedModule`, `IndexedGeneric`, `IndexedStruct`, `IndexedUnion`, `IndexedVariant`, `IndexedData`) wrap raw AST with `Table[string, int]` / `Table[string, seq[int]]` indices. Six validation rules collapsed: rules #3/#5/#6 already enforced by grammar, rules #2/#4 enforced during indexing, rule #1 is a free side effect of index construction (modules/generics/imports share one file-level namespace). Function overloading supported via `Table[string, seq[int]]`; all other blocks are `Table[string, int]`. Public `find*` lookups return `-1` / `@[]` on miss. `App` root type wraps `seq[IndexedFile]` with a path-keyed file index. `parser.nim` exports AST types (`Module`, `Generic`, `Function`, `FunctionDefinition`, `DataBlock`, `DataBlockKind`, `Struct`, `Union`, `VariantDefinition`, `ArgumentDefinition`, `ImportName`) and gains readonly accessor procs; `DataBlock.struct`/`.union` assert the variant before returning. `asl.nim:compile` calls `validator.index(files)` after `parser.parse`. Negative test fixtures live in `examples/errors/`, positive overloading fixture in `examples/overload.asl`.

### Parser features (PSR-20 to PSR-30)

- [x] **PSR-20** — Decorator support (`@identifier`). `blockSpec` parses decorators before header.
- [x] **PSR-21** — Getter expression (`source.property`).
- [x] **PSR-22** — Initializer expression (`Type { kwargs }`). `KeywordArgument`, `KeywordArgumentList`.
- [x] **PSR-23** — Variable expression (bare identifier). Last in `oneOf`.
- [x] **PSR-24** — Integer literal (signed/unsigned variants). `UnsignedIntegerLiteral` (`digit+`), `SignedIntegerLiteral` (`(+|-) digit+`).
- [x] **PSR-25** — Fatal error propagation. `blockSpec` body errors marked fatal, `run` and `any` respect fatal flag.
- [x] **PSR-26** — Initializer split into primitive (`identifier literal`) and non-primitive (`Type { kwargs }`). `Literal` variant type.
- [x] **PSR-27** — Float literal (`(+|-)? digit+ ("." digit+)? ((e|E) (+|-)? digit+)?`). Unified `ekLiteral` in Expression.
- [x] **PSR-28** — Struct block (`struct:` + field lines). Fields reuse `ArgumentDefinition`.
- [x] **PSR-29** — Union block (`union:` + variant lines). `VariantDefinition` with optional `{ fields }`.
- [x] **PSR-30** — Optional data block in module. `DataBlock = oneOf(struct, union)`. Module body: `data? function*`.

### Legacy parser bugs

- [x] `Assignment.value` infinite recursion — Fixed.
- [x] `ankStrContent` accesses wrong variant — Fixed.
- [x] `ankAssignment` accesses wrong variant — Fixed.
- [x] Missing `fmt` in string error — Fixed.
- [x] No empty-list validation before creating AST nodes — Fixed.
- [x] `StatementList.loc` crashes on empty list — Fixed.
- [x] Typo `ankIndetation` — Fixed.
- [x] `StatementList` uses `ref object of RootObj` — Fixed.
- [x] `parseStatement` tries expression before assignment — Fixed.

### Other resolved

- [x] `--dump-tokens` flag added.
- [x] `asl -h` prints to stdout with exit 0.
- [x] Output file overwrite prevented.
- [x] Bare `except:` narrowed to `CatchableError`.
- [x] CLI refactored to variant objects.
- [x] Dependencies pinned.
- [x] Error message format consistency.
- [x] `.gitignore` updated.
