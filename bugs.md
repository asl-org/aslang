# Bugs & Issues

## Open

- [ ] **`except CatchableError:` is still broad** (`cli.nim:105`) [low] — Narrow to the exact exception types thrown by `argparse` (e.g., `UsageError`, `ValueError`) once those are confirmed.
- [ ] **`$` export inconsistency** (`cli.nim:31,42`) [low] — `AslBuildCommand.$` is exported but `AslHelpCommand.$` is not.
- [ ] **`case` colon style inconsistency** (`cli.nim`) [low] — Some `case` statements use trailing colon (`case cmd.kind:`) while others don't. Pick one style.
- [ ] **Error message format inconsistency** (`cli.nim`, `asl.nim`) [low] — `cli.nim:90` uses lowercase no prefix, `cli.nim:64,68` accessor errors use uppercase `"Property..."`, while `asl.nim:11` wraps with `[ERROR] -`. Prefixing should live in one place.
- [ ] **Compile errors print to stdout instead of stderr** (`asl.nim:25`) [low] — Parse errors use `stderr.writeLine` but compile errors use `echo` (stdout). Both are errors and should go to stderr.

## Resolved

- [x] **`asl -h` prints help to stderr and exits with code 1** (`cli.nim`, `asl.nim`) [high] — Fixed by adding `ackHelp` variant with `AslHelpCommand`. `ShortCircuit` is now caught and returned as `ok(AslHelpCommand)`. Main module prints to stdout and exits with code 0.
- [x] **`ref object of RootObj` changed to variant `object`** (`cli.nim`) [medium] — Refactored `AslCommand` into a variant object with `case kind` discriminator. Each command (`AslBuildCommand`, `AslHelpCommand`) is a separate type with safe `Result`-returning accessors.
- [x] **Output file can overwrite the source** (`cli.nim`) [high] — Fixed by enforcing `.asl` extension on source files.
- [x] **`.gitignore` updated** [low] — Added `nimcache/`, `nimbledeps/`, `*.o`, `*.so`, `*.dylib`.
- [x] **Dependencies pinned** (`asl.nimble`) [medium] — Pinned `results == 0.5.1` and `argparse == 4.0.2`.
- [x] **Bare `except:` swallows all errors** (`cli.nim`) [high] — Fixed by narrowing to `except CatchableError:`.
