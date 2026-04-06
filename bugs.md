# Bugs & Issues

## Open

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

- [ ] **PSR-01: Create combinator module with `Spec[T]` and core combinators** (`src/combinator.nim`) [high] — New file. Define `Spec[T] = ref object` with `name` and `parseFn`. Implement `run` (with checkpoint/restore), `oneOf`, `any`, `atLeastOne`, `optional`, `separatedBy`, `map`, `contained`. `contained[T](name, open, inner: Spec[T], close) -> Spec[T]` handles delimited containers (parens, brackets, braces) — open delimiter, optional whitespace, inner spec, optional whitespace, close delimiter. This is the foundation — no existing code changes yet, just the new module.

- [ ] **PSR-02: Implement leaf token specs** (`src/combinator.nim`) [high] — Define base specs that match single tokens: `tokenSpec(kind, repr) -> Spec[Token]`, `punctuationSpec(value) -> Spec[Token]`, `spaceSpec -> Spec[Token]`, `newlineSpec -> Spec[Token]`, `alphabetSpec -> Spec[Token]`, `digitSpec -> Spec[Token]`, `utf8Spec -> Spec[Token]`, `anyTokenExceptNewline -> Spec[Token]`. These replace the `consume*` procs as the building blocks for higher-level specs.

- [ ] **PSR-03: Convert identifier parsing to combinators** (`src/parser.nim`) [high] — Replace `parseIdentifierHead`, `parseIdentifierTail`, `parseIdentifier` with combinator-based `identifierHeadSpec`, `identifierTailSpec`, `identifierSpec`. Also add `keywordSpec(name) -> Spec[Location]` helper. First real integration of the combinator module into the parser. Verify the existing parse tests still pass.

- [ ] **PSR-04: Convert comment, empty line, and indentation parsing** (`src/parser.nim`) [medium] — Replace `parseComment`, `parseEmptyLine`, `parseIgnorableLine`, `parseSpaces`, `parseIndentation` with combinator specs. `parseIgnorableLine` becomes `oneOf("ignorable_line", [emptyLineSpec, commentSpec])`. Indentation specs take `level` via closure capture.

- [ ] **PSR-05: Convert string literal parsing to combinators** (`src/parser.nim`) [medium] — Replace `parseEscapedStringCharacter`, `parseStringContent`, `parseStringLiteral` with combinator specs. Tests `any` combinator (zero or more string content characters) and `oneOf` (escaped vs unescaped).

- [ ] **PSR-06: Convert type and argument definition parsing** (`src/parser.nim`) [medium] — Replace `parseArgumentType`, `parseArgumentDefinition`, `parseArgumentDefinitionList` with combinator specs. `argumentTypeSpec` is forward-declared and self-referential (generic params contain argument types). Tests recursive `Spec[T]` via forward declaration. Uses `separatedBy` for comma-separated arg defs and type params.

- [ ] **PSR-07: Convert expression, assignment, and statement parsing** (`src/parser.nim`) [high] — Replace `parseExpression`, `parseFunctionCall`, `parseArgumentList`, `parseAssignment`, `parseStatement` with combinator specs. `expressionSpec` is forward-declared and recursive (expressions appear inside argument lists of function calls). Uses `oneOf` for expression/statement alternatives and `map` to bridge sub-parsers into `Expression`/`Statement` variant types.

- [ ] **PSR-08: Convert function, module, and file parsing** (`src/parser.nim`) [medium] — Replace `parseFunctionDefinition`, `parseFunction`, `parseFunctionList`, `parseStatementList`, `parseModule`, `parseFile` with combinator specs. These are block-level (indentation-aware) — `level` is captured via closures. Uses `atLeastOne` for statement lists, `any` for function lists.

- [ ] **PSR-09: Delete `AslNode` infrastructure** (`src/parser.nim`) [high] — Remove `AslNodeKind` enum, `AslNode` variant object, all 20 `newAslNode` overloads, dispatching `loc(AslNode)` and `value(AslNode)` procs, `InlineParserSpec` and `BlockParserSpec` type aliases. ~200 lines deleted. Should be a no-op change — all callers already use concrete types from prior bugs.

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
