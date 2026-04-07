# Bugs & Issues

## Open

### Parser cleanup

- [x] **PSR-10: Use `contained` in `argumentDefinitionListSpec`** (`src/parser.nim`) [low] — Done. Replaced manual delimiter handling with `contained`.

- [x] **PSR-11: Merge `escapedCharSpec` and `escapedAlphaSpec` into one factory** (`src/parser.nim`) [low] — Done. Unified into `escapedSpec(char, charSpec)`.

### Parser features

- [x] **PSR-20: Add decorator support** (`src/parser.nim`) [medium] — Done. Introduces `Decorator` AST type (`@identifier`). `blockSpec` parses zero or more decorator lines before the block header. Function, Generic, and Module carry `decorators: seq[Decorator]`. Linter round-trips decorators at correct indentation. First decorator: `@export` for module/function visibility.

- [x] **PSR-21: Add getter expression** (`src/parser.nim`) [medium] — Done. `source.property` as `Getter` AST type. Tried after function call in `oneOf` since function call is more specific (requires `(`).

- [x] **PSR-22: Add initializer expression** (`src/parser.nim`) [medium] — Done. `Type { name: expr, name: expr }` as `Initializer` with `KeywordArgumentList` (mirrors `ArgumentList` using `contained` + `separatedBy`). `KeywordArgument` holds `name: string`, `expression: Expression`.

### Combinator backtracking bugs

- [x] **PSR-12: `any` combinator doesn't backtrack per iteration** (`src/parser.nim`) [high] — Fixed. Replaced `spec.parseFn(parser)` with `parser.run(spec)` which handles checkpoint/restore automatically.

- [x] **PSR-13: `separatedBy` doesn't backtrack failed elements** (`src/parser.nim`) [high] — Fixed. Sep+element wrapped into a `pairSpec` so `run` backtracks both atomically. All internal calls use `parser.run`.

- [x] **PSR-14: `optional` doesn't backtrack on partial failure** (`src/parser.nim`) [high] — Fixed. Replaced `spec.parseFn(parser)` with `parser.run(spec)`.

### Parser cleanup (round 2)

- [ ] **PSR-15: Remove `StringContent` AST type** (`src/parser.nim`) [low] — Only used internally by string parsing specs, never appears in any AST node that leaves the parser. Simplify to return `string` or `Token` directly.

- [ ] **PSR-16: Unwrap `StatementList` and `FunctionList`** (`src/parser.nim`) [low] — Thin wrappers around `seq[Statement]` / `seq[Function]` with no extra fields. Replace with raw `seq` types in `Function` and `Module`.

- [ ] **PSR-17: Unwrap `ArgumentDefinitionList` and `ArgumentList`** (`src/parser.nim`) [low] — Wrappers around `seq` + `loc`, but `loc` is only the position of `(` which isn't used downstream. Replace with raw `seq` types in `FunctionDefinition` and `FunctionCall`.

- [ ] **PSR-18: Remove `EmptyLine` and `Comment` AST types** (`src/parser.nim`) [low] — Parsed but never stored. `ignorableLineSpec` maps them to `Location` which callers discard. The specs can return `Location` or `void` directly without dedicated types.

- [ ] **PSR-19: Add `withLeadingLines(spec)` combinator** (`src/parser.nim`) [low] — `importBlockSpec`, `fileItemBlockSpec`, and `funcBlockSpec` all follow the same pattern: `skip any(ignorableLineSpec) + parse spec`. Extract into a reusable combinator.

### Parser bugs

- [x] **`Assignment.value` infinite recursion** (`parser.nim:274`) [high] — Fixed. `assignment.value` → `assignment.target`.
- [x] **`ankStrContent` accesses wrong variant** (`parser.nim:467`) [high] — Fixed. `node.strLit.loc` → `node.strContent.loc`.
- [x] **`ankAssignment` accesses wrong variant** (`parser.nim:495`) [high] — Fixed. `node.expression.value` → `node.assignment.value`.
- [x] **Missing `fmt` in string error** (`parser.nim:777`) [medium] — Fixed. Added `fmt` prefix.
- [x] **No empty-list validation before creating AST nodes** (`parser.nim`) [medium] — Fixed. `StatementList` now rejects empty at parse time. `FunctionList.loc` is now empty-safe. `ArgumentList` and `ArgumentDefinitionList` already stored `loc` directly — no fix needed.
- [x] **`StatementList.loc` crashes on empty list** (`parser.nim:307`) [medium] — Fixed. `parseStatementList` now returns an error if empty, so `[0]` access is safe by construction.
- [ ] **Empty list `loc` falls back to `newLocation()` which is incorrect** (`parser.nim`) [medium] — `FunctionList.loc` returns `1:1` for empty lists instead of the actual source position. Needs proper location propagation from the parent context. Will likely be addressed as part of parser re-architecture.
- [x] **Typo `ankIndetation`** (`parser.nim`) [medium] — Fixed. Renamed all 5 occurrences to `ankIndentation`.
- [x] **`StatementList` uses `ref object of RootObj`** (`parser.nim:300`) [low] — Fixed. Changed to plain `ref object`.
- [x] **`parseStatement` tries expression before assignment** (`parser.nim:885`) [low] — Fixed. Assignment is now tried first since `=` disambiguates earlier.

### Parser combinator refactor

- [x] **PSR-01: Create combinator module with `Spec[T]` and core combinators** (`src/combinator.nim`) [high] — Done. `Spec[T]`, `run`, `oneOf`, `any`, `atLeastOne`, `optional`, `separatedBy`, `map`, `contained`, plus `Parser`/`ParserError`/consume procs moved from parser.nim.

- [x] **PSR-02: Implement leaf token specs** (`src/combinator.nim`) [high] — Done. `tokenSpec`, `punctuationSpec`, `anyTokenSpec`, `anyTokenExceptNewlineSpec` factories and `spaceSpec`, `newlineSpec`, `alphabetSpec`, `digitSpec`, `utf8Spec` constants.

- [x] **PSR-03: Convert identifier parsing to combinators** (`src/parser.nim`) [high] — Done. `identifierSpec`, `keywordSpec`, helper char specs. All 8 callers updated. Fixed `result` shadowing warnings in combinator closures.

- [x] **PSR-04: Convert comment, empty line, and indentation parsing** (`src/parser.nim`) [medium] — Done. `spacesSpec`, `emptyLineSpec`, `commentSpec`, `ignorableLineSpec`, `indentationSpec(level)`. Fixed comment parsing to stop at newlines.

- [x] **PSR-05: Convert string literal parsing** (`src/parser.nim`) [medium] — Done. `escapedCharSpec`/`escapedAlphaSpec` factories, individual escape specs (`escapedBackslash`, `escapedDoubleQuote`, `escapedNewline`, `escapedTab`), `unescapedStringCharSpec`, `stringContentSpec`, `stringLiteralSpec`.

- [x] **PSR-06: Convert type and argument definition parsing** (`src/parser.nim`) [medium] — Done. `argumentTypeSpec` (forward-declared, self-referential), `argumentDefinitionSpec`, `argumentDefinitionListSpec`. Introduced `separatorSpec` factory and `commaWithSpacesSpec`/`colonWithSpacesSpec`.

- [x] **PSR-07: Convert expression, assignment, and statement parsing** (`src/parser.nim`) [high] — Done. `expressionSpec` (forward-declared, mutual recursion with `argumentListSpec`), `functionCallSpec`, `assignmentSpec`, `statementSpec` via `oneOf` + `map`.

- [x] **PSR-08: Convert function, module, and file parsing** (`src/parser.nim`) [medium] — Done. `functionDefinitionSpec`, `statementLineSpec`/`statementListSpec` (atLeastOne), `functionSpec`/`functionListSpec` (any), `moduleSpec`, `fileSpec`. Block-level specs use factory procs capturing indentation level.

- [x] **PSR-09: Delete `AslNode` infrastructure** (`src/parser.nim`) [high] — Done. Removed `AslNodeKind`, `AslNode`, all `newAslNode` overloads, `loc`/`value` dispatch procs, `InlineParserSpec`, `BlockParserSpec`, old `parse` overloads, and all commented-out dead code. -231 lines.

### Other

- [ ] **`except CatchableError:` is still broad** (`cli.nim:105`) [low] — Narrow to the exact exception types thrown by `argparse` (e.g., `UsageError`, `ValueError`) once those are confirmed.
- [ ] **`Token` is `ref object`** (`tokenizer.nim:72`) [low] — Each token is heap-allocated. For a tokenizer producing thousands of tokens, a plain `object` in `seq[Token]` avoids GC pressure since tokens are small (enum + string + two ints).

## Resolved

- [x] **Add `--dump-tokens` flag** (`cli.nim`, `asl.nim`, `tokenizer.nim`) [medium] — Added `--dump-tokens` flag to CLI and `AslBuildCommand`. Dump is gated behind the flag. Pipeline continues after dumping.
- [x] **`asl -h` prints help to stderr and exits with code 1** (`cli.nim`, `asl.nim`) [high] — Fixed by adding `ackHelp` variant with `AslHelpCommand`. `ShortCircuit` is now caught and returned as `ok(AslHelpCommand)`. Main module prints to stdout and exits with code 0.
- [x] **Output file can overwrite the source** (`cli.nim`) [high] — Fixed by enforcing `.asl` extension on source files.
- [x] **Bare `except:` swallows all errors** (`cli.nim`) [high] — Fixed by narrowing to `except CatchableError:`.
- [x] **`ref object of RootObj` changed to variant `object`** (`cli.nim`) [medium] — Refactored `AslCommand` into a variant object with `case kind` discriminator. Each command (`AslBuildCommand`, `AslHelpCommand`) is a separate type with safe `Result`-returning accessors.
- [x] **Dependencies pinned** (`asl.nimble`) [medium] — Pinned `results == 0.5.1` and `argparse == 4.0.2`.
- [x] **`validateSourceEncoding` is misleading** (`asl.nim`) [medium] — Removed the wrapper, inlined `scanDangerousCodepoints` directly in `compile`.
- [x] **UTF-8 error reports byte position not line:col** (`asl.nim`) [medium] — Intentional. Invalid UTF-8 bytes won't render properly in editors, so byte position is the most useful reference.
- [x] **BOM at file start is rejected** (`tokenizer.nim`) [medium] — Intentional. BOM is rejected everywhere, consistent with ASL's strict source file policy.
- [x] **No trailing newline handling** (`tokenizer.nim`) [low] — Fixed. Injects a newline token at the end if source doesn't end with one.
- [x] **Error message format inconsistency** (`cli.nim`, `asl.nim`, `tokenizer.nim`) [low] — Fixed. All inner errors are lowercase with no prefix. `[ERROR] -` prefix is added only at display time in `asl.nim` main.
- [x] **`$` export inconsistency** (`cli.nim`) [low] — Fixed. Both `AslBuildCommand.$` and `AslHelpCommand.$` now exported.
- [x] **`case` colon style inconsistency** (`cli.nim`, `asl.nim`) [low] — Fixed. All `case` statements now use trailing colon.
- [x] **Compile errors print to stdout instead of stderr** (`asl.nim`) [low] — Already fixed. Both parse and compile errors now use `stderr.writeLine`.
- [x] **No fallthrough handling in main** (`asl.nim`) [low] — Switched from `if/elif` to `case command.kind`. Nim compiler now enforces exhaustive matching.
- [x] **`.gitignore` updated** [low] — Added `nimcache/`, `nimbledeps/`, `*.o`, `*.so`, `*.dylib`.
- [x] **Trailing space in `$AslBuildCommand`** (`cli.nim`) [low] — Intentional.
