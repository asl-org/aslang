# Bugs & Issues

## Open

### Match expression

- [x] **PSR-31: Add CasePattern AST type** — Done. `oneOf(integerLiteral, identifier)` variant.
- [x] **PSR-32: Add CaseBlock AST type and spec** — Done. `case pattern: statementList` using `blockSpec`.
- [x] **PSR-33: Add MatchExpression AST type and spec** — Done. `match expr: caseBlock+` using `blockSpec`. `skMatch` variant in Statement.
- [x] **PSR-34: Wire match into statementSpec** — Done. Match tried before indentation in `statementLineSpec` since it handles its own indentation via `blockSpec`. `aslBlock` dispatches block statements to multi-line formatting.

- [x] **PSR-35: Add variant pattern to case blocks** (`src/parser.nim`) [medium] — Done. `VariantPattern` with `variantName` + `seq[VariantPatternField]` (name: binding pairs). Uses `contained` + `separatedBy` for `{ field: binding }`. Tried before variable in `casePatternSpec` `oneOf` since `{` disambiguates.

- [x] **PSR-37: Add union initializer expression** (`src/parser.nim`) [medium] — Done. `Type.Variant { fields }` as `UnionInitializer`. Tried before non-primitive and function call in `oneOf` since all start with `argumentType` but disambiguate by `.Variant {` vs `{` vs `.method(`.

- [x] **PSR-38: Add import aliasing** (`src/parser.nim`) [medium] — Done. `ImportedType` type with `name` and optional `alias` (empty string if none). `importedTypeSpec` parses `identifier ("as" identifier)?`. Import stores `seq[ImportedType]` instead of `seq[string]`.

### New grammar (needed for base.asl)

- [ ] **`literal:` data block** — `literal: "u8"` inside a module declares the module as a built-in literal type. Needs a new `DataBlockKind` variant (`dbkLiteral` exists in AST but grammar doesn't parse it yet). `base.asl` uses this for every numeric module.
- [ ] **`requires(TypeParam)` on modules** — `requires(Any)` declares that a module is parameterized (like `Array[Any]`). Not in the grammar yet. Used by `Array` and potentially other generic containers in `base.asl`.
- [ ] **`public generic`** — `genericHeaderSpec` doesn't parse an optional `public` keyword prefix. `base.asl` has `public generic Any:` which fails at parse time.
- [ ] **`Pointer` as a type name** — `base.asl` uses `Pointer` (capitalized) as a type for raw pointers. Currently the built-in is `ptr` (lowercase). Either add `Pointer` as a built-in alias or let it be resolved as a module type.

### Parser bugs

- [ ] **Blank line after `struct:` / `union:` bypasses `atLeastOne` in blockSpec** (`src/parser/grammar.nim`) [medium] — `struct:` followed by a blank line then `func` compiles as a module with only a function (struct silently discarded). `blockSpec` with `atLeastOne(fieldLineSpec)` should reject zero fields, but the blank line causes a backtrack that drops the struct entirely. `newStruct` has a defense-in-depth guard (`fields.len == 0` check) but it's never reached because `blockSpec` backtracks before calling the combine function. Needs investigation into how `blockSpec` handles empty bodies after header success.

### Parser cleanup (round 2)

- [ ] **PSR-15: Remove `StringContent` AST type** (`src/parser/grammar.nim`) [low] — Only used internally by string parsing specs, never appears in any AST node that leaves the parser. Simplify to return `string` or `Token` directly.

- [ ] **PSR-16: Unwrap `StatementList` and `FunctionList`** (`src/parser/ast.nim`) [low] — Thin wrappers around `seq[Statement]` / `seq[Function]` with no extra fields. Replace with raw `seq` types in `Function` and `Module`.

- [ ] **PSR-17: Unwrap `ArgumentDefinitionList` and `ArgumentList`** (`src/parser/ast.nim`) [low] — Wrappers around `seq` + `loc`, but `loc` is only the position of `(` which isn't used downstream. Replace with raw `seq` types in `FunctionDefinition` and `FunctionCall`.

- [ ] **PSR-18: Remove `EmptyLine` and `Comment` AST types** (`src/parser/grammar.nim`) [low] — Parsed but never stored. `ignorableLineSpec` maps them to `Location` which callers discard. The specs can return `Location` or `void` directly without dedicated types.

- [ ] **PSR-19: Add `withLeadingLines(spec)` combinator** (`src/parser/combinators.nim`) [low] — `importBlockSpec`, `typeBlockSpec`, and `funcBlockSpec` all follow the same pattern: `skip any(ignorableLineSpec) + parse spec`. Extract into a reusable combinator.

### Other

- [ ] **`except CatchableError:` is still broad** (`src/cli.nim:105`) [low] — Narrow to the exact exception types thrown by `argparse` (e.g., `UsageError`, `ValueError`) once those are confirmed.
- [ ] **`Token` is `ref object`** (`src/tokenizer/tokenizer.nim:72`) [low] — Each token is heap-allocated. For a tokenizer producing thousands of tokens, a plain `object` in `seq[Token]` avoids GC pressure since tokens are small (enum + string + two ints).
- [ ] **Empty list `loc` falls back to `newLocation()` which is incorrect** (`src/parser/ast.nim`) [medium] — `FunctionList.loc` returns `1:1` for empty lists instead of the actual source position. Needs proper location propagation from the parent context.
- [x] **`readFileSafe` crashes on missing files** (`src/parser/loader.nim`) — Caught only `IOError`, but on macOS `getFileSize` throws `OSError` for a missing file — the parser propagated an unhandled exception. Fixed by calling `fileExists` up front and catching `CatchableError` for everything else. Surfaced while building the `examples/errors/missing_file.asl` fixture.

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

### Project structure

- [x] **Component directory modules** — `src/tokenizer/` and `src/parser/` (5 files: ast, combinators, grammar, loader, parser entry). `src/nim.cfg` adds each component directory to the module search path. All cross-component imports use bare names. No `../` imports anywhere.

### Validator absorbed into parser

- [x] **PSR-39 + validator deletion** — Originally a separate `src/validator/` component with `Indexed*` wrapper types and `Table` indices. Validation checks were progressively moved into parser constructors (`newStruct`, `newUnion`, `newVariantDefinition`, `newModule`, `newFile`, etc.) which enforce uniqueness at construction time. Remaining lookup indices (`functionIndex`, `funcDefIndex`, `moduleIndex`, `genericIndex`, `importIndex`, `fileIndex`) migrated directly onto parser AST types (`Module`, `Generic`, `File`, `App`). The `find*` lookup procs now live on the parser types. Validator deleted entirely — zero validation or indexing logic remains outside the parser.

### ExternFunction + Function union

- [x] **Function is now a tagged union** (`src/parser/ast.nim`, `src/parser/grammar.nim`) — `fkUser` (UserFunction: decorators + def + body) and `fkExtern` (ExternFunction: `@extern("symbol")` + def, no body). `externFunctionSpec` parses `@extern("symbol")` on one line, function definition at the same indentation on the next. `funcBlockSpec` tries extern first, falls back to user function. `Function.name`, `.def`, `.arity` dispatch on kind. Resolver dispatches via `resolveUserFunction` / `resolveExternFunction`.

### Resolver (WIP rewrite, 2026-04)

- [ ] **Resolver rewrite** (`src/resolver.nim`) — In progress. Old resolver deleted (native types + body resolution dropped). New scope: name and shape resolution only — walks files in topo order, two passes per file (declare all defined+imported names into a `FileScope`, then resolve every `ArgumentType` inside data blocks and function signatures). Function bodies punted to a future Analyzer phase. Generic-signature rule (inside a generic block, arg/return type roots may only be self or a module) enforced during Pass B. No constraint-satisfaction checks on impl types — that's the Analyzer's job too.

### Resolver (previous — deleted)

- [x] **PSR-41 Phases 1+2** — Built `Resolved*` wrapper types with local int ids and `ResolvedArgumentType` for signature-level type resolution. Subsequently deleted in full. Built-in type canonicalization (`str → String`, `U8 → u8`, `pointer → ptr`) applied to examples during this phase and retained.

### Location tracking

- [x] **PSR-40: Store names as `Identifier` instead of `string`** (`src/parser/ast.nim`) — Every name-bearing field in the AST holds an `Identifier` (value + Location). `ImportedType.alias` is `Option[Identifier]`. Error messages report exact `line:col`. `Identifier.value` is the textual name (renamed from `.name` to avoid `.name.name` stutter).

### Block indexing and validation

- [x] **PSR-39** — Lookup indices live directly on AST types. Validation rules enforced by parser constructors. `App` root type wraps `seq[File]` with path-keyed `fileIndex`. `find*` procs on `File`, `Module`, `Generic`, `App`.

### Dependency resolution

- [x] **PSR-36** — BFS multi-file import resolution in `src/parser/loader.nim`. Topological sort with cycle detection. `Import.path` (absolute) set during BFS. Parent-directory escape prevention via normalized path comparison.

### Parser features (PSR-20 to PSR-30)

- [x] **PSR-20** — Decorator support (`@identifier`). `blockSpec` parses decorators before header. Note: `@export` replaced by `public` keyword on modules and functions; decorators still parsed but `@export` no longer used.
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
