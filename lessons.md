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

## 2026-04-02 02:41 — CLI refactor with variant objects and help command

- argparse raises `ShortCircuit` (a `CatchableError`) on `--help` — must be caught explicitly before the general `CatchableError` handler, otherwise help requests look like errors.
- Nim variant objects (`case kind: EnumType`) are the idiomatic way to model command sum types — each variant carries only its relevant fields, enforced at compile time.
- Separate types per command (`AslBuildCommand`, `AslHelpCommand`) keeps concerns isolated and makes the CLI extensible for future commands.
- Return `Result`-based accessors on variant fields (e.g., `proc build*(cmd): Result[AslBuildCommand, string]`) to prevent unsafe variant access at runtime.
- `--help` should print to stdout with exit code 0. Errors should print to stderr with exit code 1. These are distinct paths — don't conflate them through the same `err()` return.
- Bare `asl` with no subcommand returns `err(Usage)` — prints to stderr, exits 1. Some CLIs treat this as implicit `--help` (stdout, exit 0). Design choice to revisit later.
- Always rebuild after code changes before testing — stale binaries cause confusion (e.g., old `ShortCircuit` error persisting after the fix).

## 2026-04-02 03:44 — Source encoding validation and Trojan Source defense

- Nim's `runes` iterator and `fastRuneAt` assume valid UTF-8 — they produce garbage or crash on invalid bytes. Always validate UTF-8 first before iterating runes.
- Trojan Source attacks use bidi codepoints (U+202A–U+202E, U+2066–U+2069), zero-width characters (U+200B–U+200D, U+FEFF), and invisible control characters to make source code appear different from what the compiler sees. A mission-critical compiler must reject these.
- Write bite-sized composable functions: `isBidiCodepoint`, `isZeroWidthCodepoint`, `isInvisibleCodepoint` → `classifyDangerous` → `scanDangerousCodepoints` → `validateSourceEncoding`. Each does one thing, `?` chains them.
- Pass `uint32` to codepoint checker functions instead of `Rune` — the checks are purely numeric, no need to carry the `Rune` type through.
- `validateUtf8` from `std/unicode` returns byte offset of the first invalid byte, or -1 if valid. Use a separate `byteOffsetToLineCol` helper to convert to human-readable positions.
- TOCTOU: `fileExists` followed by `readFile` is a race condition. Better to let `getFileSize`/`readFile` fail and catch `IOError` in one `try/except` block.
- `Result[void, T]` is a good pattern for validation functions — `ok()` means passed, `err(T)` carries the classification or error message.

## 2026-04-02 04:44 — Code consistency pass and cleanup

- Error messages from inner functions should be lowercase with no prefix. The `[ERROR] -` prefix belongs at the display boundary (`asl.nim` main) — not in library code. This keeps errors composable.
- If a one-line wrapper function adds no logic, inline it. `validateSourceEncoding` was just `? scanDangerousCodepoints(...)` — removed in favor of calling directly.
- Use `case` over `if/elif` on variant objects — Nim's exhaustive matching catches unhandled variants at compile time. Critical as the command set grows.
- All `case` statements should use trailing colon (`case x:`) for consistency.
- Export `$` on all public types — if one type's `$` is exported, all sibling types should match.
- Invalid UTF-8 errors should report byte position, not line:col — editors can't render the broken bytes meaningfully anyway, so byte offset is more actionable.
- BOM (`U+FEFF`) is rejected everywhere — intentional strict policy for ASL source files.
- When a bug is already fixed by prior changes, verify before attempting a fix — avoids redundant edits.
