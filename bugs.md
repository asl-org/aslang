# Bugs & Issues

## Open

- [ ] **`except CatchableError:` is still broad** (`cli.nim:105`) [low] — Narrow to the exact exception types thrown by `argparse` (e.g., `UsageError`, `ValueError`) once those are confirmed.
- [ ] **`Token` is `ref object`** (`tokenizer.nim:61`) [low] — Each token is heap-allocated. For a tokenizer producing thousands of tokens, a plain `object` in `seq[Token]` avoids GC pressure since tokens are small (enum + string + two ints).

### Robustness

- [x] **No trailing newline handling** (`tokenizer.nim`) [low] — Fixed. Injects a newline token at the end if source doesn't end with one.

## Resolved

- [x] **`asl -h` prints help to stderr and exits with code 1** (`cli.nim`, `asl.nim`) [high] — Fixed by adding `ackHelp` variant with `AslHelpCommand`. `ShortCircuit` is now caught and returned as `ok(AslHelpCommand)`. Main module prints to stdout and exits with code 0.
- [x] **Output file can overwrite the source** (`cli.nim`) [high] — Fixed by enforcing `.asl` extension on source files.
- [x] **Bare `except:` swallows all errors** (`cli.nim`) [high] — Fixed by narrowing to `except CatchableError:`.
- [x] **`ref object of RootObj` changed to variant `object`** (`cli.nim`) [medium] — Refactored `AslCommand` into a variant object with `case kind` discriminator. Each command (`AslBuildCommand`, `AslHelpCommand`) is a separate type with safe `Result`-returning accessors.
- [x] **Dependencies pinned** (`asl.nimble`) [medium] — Pinned `results == 0.5.1` and `argparse == 4.0.2`.
- [x] **`validateSourceEncoding` is misleading** (`asl.nim`) [medium] — Removed the wrapper, inlined `scanDangerousCodepoints` directly in `compile`.
- [x] **UTF-8 error reports byte position not line:col** (`asl.nim`) [medium] — Intentional. Invalid UTF-8 bytes won't render properly in editors, so byte position is the most useful reference.
- [x] **BOM at file start is rejected** (`tokenizer.nim`) [medium] — Intentional. BOM is rejected everywhere, consistent with ASL's strict source file policy.
- [x] **Error message format inconsistency** (`cli.nim`, `asl.nim`, `tokenizer.nim`) [low] — Fixed. All inner errors are lowercase with no prefix. `[ERROR] -` prefix is added only at display time in `asl.nim` main.
- [x] **`$` export inconsistency** (`cli.nim`) [low] — Fixed. Both `AslBuildCommand.$` and `AslHelpCommand.$` now exported.
- [x] **`case` colon style inconsistency** (`cli.nim`, `asl.nim`) [low] — Fixed. All `case` statements now use trailing colon.
- [x] **Compile errors print to stdout instead of stderr** (`asl.nim`) [low] — Already fixed. Both parse and compile errors now use `stderr.writeLine`.
- [x] **No fallthrough handling in main** (`asl.nim`) [low] — Switched from `if/elif` to `case command.kind`. Nim compiler now enforces exhaustive matching.
- [x] **`.gitignore` updated** [low] — Added `nimcache/`, `nimbledeps/`, `*.o`, `*.so`, `*.dylib`.
- [x] **Trailing space in `$AslBuildCommand`** (`cli.nim`) [low] — Intentional.
