# Lessons Learned

## 2026-04-02 01:12 — Bug audit and CLI hardening

- Bare `except:` in Nim catches everything including `Defect` — always use `except CatchableError:` at minimum, and narrow further when exception types are known.
- `changeFileExt("")` on a file without an extension returns the same filename — enforce `.asl` extension on source files to prevent output overwriting input.
- Use plain `object` for small, short-lived data (CLI config, tokens). Use `ref object` for recursive, large, or widely-shared data (AST nodes, IR, symbols, types). Excessive `object` copying caused real perf issues during prototyping.
- `ref object of RootObj` is only needed when inheritance or runtime type checks (`of`) are required — don't use it by default.
- Pin nimble dependencies to exact versions (`==`) for a mission-critical compiler. Open ranges (`>=`) risk silent breakage from upstream updates.
- `switch("experimental", "dotOperators")` is intentional — used for short-circuiting in the compiler.
- `.gitignore` for Nim projects should include `nimcache/`, `nimbledeps/`, `*.o`, `*.so`, `*.dylib` beyond just the binary.
- File existence validation is a parsing concern, not an argparse concern — but deferred for now since the compiler is under active development.
- `parseInt(...).uint8` for `indentWidth` is safe when constrained by argparse `choices` — no need to over-engineer it.
