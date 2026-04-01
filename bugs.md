# Bugs & Issues

## Open

- [ ] **`except CatchableError:` is still broad** (`cli.nim:105`) [low priority] — Narrow to the exact exception types thrown by `argparse` (e.g., `UsageError`, `ValueError`) once those are confirmed. A tighter catch ensures unexpected recoverable errors from dependency bugs surface rather than being masked as CLI usage errors.

## Resolved

- [x] **`asl -h` prints help to stderr and exits with code 1** (`cli.nim`, `asl.nim`) — Fixed by adding `ackHelp` variant with `AslHelpCommand`. `ShortCircuit` is now caught and returned as `ok(AslHelpCommand)`. Main module prints to stdout and exits with code 0.
- [x] **`ref object of RootObj` changed to variant `object`** (`cli.nim`) — Refactored `AslCommand` into a variant object with `case kind` discriminator. Each command (`AslBuildCommand`, `AslHelpCommand`) is a separate type with safe `Result`-returning accessors.
- [x] **Output file can overwrite the source** (`cli.nim`) — Fixed by enforcing `.asl` extension on source files.
- [x] **`.gitignore` updated** — Added `nimcache/`, `nimbledeps/`, `*.o`, `*.so`, `*.dylib`.
- [x] **Dependencies pinned** (`asl.nimble`) — Pinned `results == 0.5.1` and `argparse == 4.0.2`.
- [x] **Bare `except:` swallows all errors** (`cli.nim`) — Fixed by narrowing to `except CatchableError:`.
