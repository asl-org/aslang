# Bugs & Issues

- [ ] **Output file can overwrite the source** (`cli.nim:45`) — If the source has no extension (e.g., `asl build myfile`), `changeFileExt("")` returns `myfile` — the output path is the same as the input. The compiler would silently destroy the source file.

- [ ] **No input file existence check** — The CLI parses the filename but never validates it exists. The user gets no useful error if they typo a filename — it'll blow up later with a less helpful message from whatever stage tries to read it.

- [ ] **`parseInt(...).uint8` is fragile** (`cli.nim:53`) — Currently safe because `choices = @["2", "4"]`, but if `argparse` is ever bypassed or the constraint relaxed, `parseInt` can throw a `ValueError` that gets caught by the bare `except` — turning a bad `--indent-width` into an opaque error.

- [ ] **Debug output left in main** (`asl.nim:12-15`) — Prints raw internals (`kind`, `debug`, `outputFile`, `indentWidth`) to stdout. Fine for now, but easy to forget when real compilation logic is added.

- [ ] **`.gitignore` is minimal** — Only ignores the `asl` binary. Missing `nimcache/`, `*.o`, `*.so`, `*.dylib`, and nimble cache directories. These will clutter the repo once the project grows.

- [ ] **Unpinned dependencies** (`asl.nimble:13-14`) — Open-ended version ranges (`>= 0.5.0`, `>= 4.0.0`). For a mission-critical tool, a `nimble.lock` or exact version pins prevent surprise breakage from upstream updates.

- [ ] **Experimental Nim feature enabled** (`asl.nimble:40`) — `switch("experimental", "dotOperators")` — Experimental features can change semantics across Nim versions. Risky foundation for a compiler targeting critical systems.

- [ ] **`ref object of RootObj` is heavier than needed** (`cli.nim:7`) — `AslCommand` doesn't need dynamic dispatch or inheritance — a plain `object` avoids heap allocation and GC overhead. Only use `ref object of RootObj` if you plan a command type hierarchy.

- [x] **Bare `except:` swallows all errors** (`cli.nim:57`) — Was catching everything including `Defect`, `OutOfMemoryError`, `AccessViolationDefect`, etc. Fixed by narrowing to `except CatchableError:`.

- [ ] **`except CatchableError:` is still broad** (`cli.nim:57`) [low priority] — Narrow to the exact exception types thrown by `argparse` (e.g., `UsageError`, `ValueError`) once those are confirmed. A tighter catch ensures unexpected recoverable errors from dependency bugs surface rather than being masked as CLI usage errors.
