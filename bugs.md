# Bugs & Issues



- [x] **Bare `except:` swallows all errors** (`cli.nim:57`) — Was catching everything including `Defect`, `OutOfMemoryError`, `AccessViolationDefect`, etc. Fixed by narrowing to `except CatchableError:`.

- [ ] **`except CatchableError:` is still broad** (`cli.nim:57`) [low priority] — Narrow to the exact exception types thrown by `argparse` (e.g., `UsageError`, `ValueError`) once those are confirmed. A tighter catch ensures unexpected recoverable errors from dependency bugs surface rather than being masked as CLI usage errors.

- [x] **Dependencies pinned** (`asl.nimble:13-14`) — Pinned `results == 0.5.1` and `argparse == 4.0.2` to currently installed versions.

- [x] **`.gitignore` updated — Added `nimcache/`, `nimbledeps/`, `*.o`, `*.so`, `*.dylib`.

- [x] **Output file can overwrite the source** (`cli.nim:45`) — Fixed by enforcing `.asl` extension on source files. `splitFile()` validates the extension before proceeding, so `changeFileExt("")` is now always safe.

- [x] **`ref object of RootObj` changed to plain `object`** (`cli.nim:7`) — `AslCommand` doesn't need dynamic dispatch or inheritance. Plain `object` avoids heap allocation and GC overhead.
