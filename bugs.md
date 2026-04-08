# Bugs & Issues

## Open

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
