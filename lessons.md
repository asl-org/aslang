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

## 2026-04-02 07:12 — Tokenizer design and debug infrastructure

- The tokenizer is intentionally dumb — it's a per-rune character classifier. Multi-character tokens, keywords, strings, numbers, indentation, and comment handling are all parser concerns.
- Name functions for what they actually check. `validateUtf8` was renamed to `isCompilerSafe` — it checks for dangerous codepoints, not UTF-8 encoding validity.
- Nim `set` can't hold `uint32` values properly (warning for >65535). Use typed `array` with `contains`-based `in` lookup instead.
- `r.uint32 <= 0x7F` is the correct way to check if a rune is ASCII — it's a semantic check. `r.size == 1` gives the same result but answers a different question.
- `r.char` only works safely for ASCII runes. For non-ASCII it truncates to the low byte.
- All valid ASCII is valid UTF-8 — ASCII (0x00–0x7F) is a subset of UTF-8.
- Debug dump flags (`--dump-tokens`, future `--dump-ast`, etc.) should be per-stage. Dump to stdout so it can be piped. Gate behind the flag — never dump unconditionally. Pipeline continues after dumping.
- Empty files are valid — the tokenizer returns an empty `seq[Token]` and the parser handles structural validation.
- Trailing newlines are normalized by the tokenizer — inject a newline token at the end if missing, so the parser always sees a consistent stream.
- Span tracking (start + end position) is unnecessary when the tokenizer is single-character. Can be added later if the tokenizer becomes multi-character.
- Null bytes get rejected as unknown tokens by the existing `else` branch — no special handling needed.

## 2026-04-05 10:55 — Parser audit and design observations

- The parser is a recursive descent backtracking parser built on top of a dumb single-character tokenizer. It combines raw tokens into multi-character constructs (identifiers, strings, numbers, etc.) — this complexity lives in the parser by design, not the tokenizer.
- Checkpoint/restore pattern for backtracking: `parse` procs save `parser.index`, try a spec, and restore on failure. Clean and predictable.
- `ParserError` with `Location` and `<` operator lets `max(errors)` pick the deepest error — the one that got furthest before failing. Good heuristic for error reporting in backtracking parsers.
- Inline vs block parser specs (`InlineParserSpec` vs `BlockParserSpec`) separate parsers that don't care about indentation from those that do (via `level: uint32`).
- Watch for variant object field access bugs — accessing `node.strLit` when you meant `node.strContent` compiles if both variants have the same field types but is a runtime bug. Nim's variant objects don't protect against this at compile time when using `ref object`.
- Self-referential `value` procs are a common copy-paste bug — `assignment.value` calling itself instead of `assignment.target` causes infinite recursion.
- When two parse alternatives start with the same token pattern (e.g., expression and assignment both start with an identifier), ordering matters for performance. Put the one with the earlier disambiguator first (assignment has `=` after the identifier).
- `ref object of RootObj` should not appear unless inheritance is needed — it was found on `StatementList` with nothing inheriting from it.
