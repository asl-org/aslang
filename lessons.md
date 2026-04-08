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

## 2026-04-06 — Parser combinator architecture design

- The `AslNode` variant object is the main obstacle to adding new syntax — every new node type requires ~6 touch points (enum, variant field, constructor, loc dispatch, value dispatch, assert at call site). It exists solely as a uniform return type for parse functions.
- The real AST types (`Expression`, `Statement`, `Module`, etc.) are already independent `ref object`s. `AslNode` is a redundant wrapper — eliminate it by making parse functions return concrete types.
- Parser combinators absorb the repetitive patterns: `oneOf` replaces the try-collect-errors-return-max pattern (~5 instances), `any`/`atLeastOne` replace the while-isOk loops (~8 instances), `separatedBy` replaces the A-comma-A loops (~3 instances).
- `Spec[T] = ref object` with generic `T` is the right combinator type for Nim. Being a `ref object` enables forward declaration for recursive grammars — create the spec with `parseFn: nil`, fill in the implementation later. Closures in other specs that capture this ref see the updated `parseFn` at parse time.
- Every `Spec` carries a `name: string` for two reasons: (1) error messages — `oneOf` can say "expected {spec.name}" when all alternatives fail, (2) identity — forward-declared specs are identifiable before they have an implementation.
- Sequencing should NOT be a combinator — just use normal Nim code with `?` operator. The `run` method on each sub-parse provides backtracking. The caller's `run` restores the index if the whole sequence fails. This hybrid (declarative combinators + imperative sequencing) is the pragmatic sweet spot for Nim.
- Core combinator set: `oneOf[T](name, specs) -> Spec[T]`, `any[T](spec) -> Spec[seq[T]]`, `atLeastOne[T](spec) -> Spec[seq[T]]`, `optional[T](spec) -> Spec[Option[T]]`, `separatedBy[T,S](spec, sep) -> Spec[seq[T]]`, `map[T,U](spec, name, fn) -> Spec[U]`.
- `run[T](parser, spec) -> Result[T, ParserError]` replaces both `InlineParserSpec` and `BlockParserSpec` — generic over return type, with automatic checkpoint/restore.
- `map` combinator bridges between parse results and AST nodes. E.g., `stringLiteralSpec.map("string_expr", proc(s): Expression = newExpression(s))` converts a `Spec[StringLiteral]` to `Spec[Expression]` for use in `oneOf`.
- Block-level (indentation-aware) specs need `level: uint32` — handled by closures that capture the level, not by a separate spec type.
- `contained[T](name, open, inner: Spec[T], close) -> Spec[T]` is a higher-level combinator for delimited containers. It handles: open delimiter, optional whitespace, inner spec, optional whitespace, close delimiter. Composes with `separatedBy` — container handles delimiters, `separatedBy` handles comma-separated content. Captures three recurring patterns in the parser: `(..args)`, `[..types]`, `{..fields}`.

## 2026-04-06 — Parser combinator refactor execution

- `separatorSpec(sep)` factory generalizes the "optional_spaces separator optional_spaces" pattern. Used for `,`, `:`, `=` — adding a new separator is one line.
- `escapedSpec(char, charSpec)` factory unifies punctuation and alphabet escape handling. Adding a new escape sequence is one line + adding to the `oneOf` array.
- `unescapedStringCharSpec` must reject both `"` and `\` — not just `"`. The old code only rejected `"`, which would have caused `\` to be consumed as a regular character instead of starting an escape sequence.
- Nim's `result` is a special variable inside procs (implicit return value). Naming a local variable `result` inside combinator closures triggers `ResultShadowed` warnings. Use `res` or `maybeValue` instead.
- Nim's `options` module (`Option[T]`, `isSome`, `get`) must be explicitly imported in `parser.nim` — the linter removed the re-export from `combinator.nim`.
- Forward-declared specs (`newSpec[T]`) work because `Spec[T]` is `ref object` — closures capture the ref, not the parseFn. When the parseFn is set later, all closures see the update at parse time. Two forward-declared specs in the parser: `argumentTypeSpec` (self-referential generics) and `expressionSpec` (mutual recursion with argumentList via functionCall).
- `expressionSpec.parseFn = oneOf(...).parseFn` — assign the parseFn from a combinator result to a forward-declared spec. The `oneOf` creates a new spec; we extract its parseFn and assign it to the existing ref.
- When `any(combinator)` backtracks a failed iteration, it also undoes any "ignorable line" consumption from within that iteration. This can leave trailing newlines unconsumed. The `fileSpec` loop needs `if parser.done(): break` after consuming ignorable lines to handle trailing whitespace at end of file.
- `statementListSpec` is `atLeastOne(statementLineSpec)` where each statementLine is `indentation + statement + newline`. The combinator replaces a 15-line manual while loop with a one-liner.
- `functionListSpec` is `any(functionBlockSpec)` where each block skips leading ignorable lines then parses a function. `any` backtracks the ignorable line consumption if no function follows.
- Block-level specs (statementList, function, functionList, module) are simple `let` declarations, not factory procs. `parser.level` is a field on Parser — `blockSpec` increments it for body parsing, `run` saves/restores it on backtracking alongside `parser.index`.
- `blockSpec[H, B, R](name, header, body, combine)` is the higher-level combinator for indented blocks: `indentation + header + newline + body(level+1)`. Used by `functionSpec`, `moduleSpec`, `genericSpec`. Adding a new block type is: define header spec, pick a body spec, one `blockSpec` call.
- Don't over-generalize header specs — `moduleHeaderSpec` and `genericHeaderSpec` look the same today (`keyword name :`) but may diverge (e.g., function definition is already a different header shape). Keep them separate.
- `parser.filepath` belongs on Parser — it's needed by `fileSpec` to construct `File` directly. Without it, you'd need intermediate tuple types (`FileContent`) to pass data between `fileSpec` and the `parse*` entry point.
- `File` stores `imports`, `modules`, `generics` as separate arrays. `newFile` accepts `seq[FileItem]` and filters by kind — the sum type (`FileItem`) is only used during parsing, the `File` type keeps the concerns separated.
- Import syntax: `import { Name, Name } from "path"`. Uses `contained` for the braced name list and `separatedBy` for comma-separated identifiers. `keywordSpec("from")` matches the source keyword.
- File grammar is `import* (module | generic)*` — imports must come before modules/generics. `fileSpec` parses `any(importBlockSpec)` first, then `any(fileItemBlockSpec)`.
- `value` procs on AST types became dead code after the combinator refactor — the `compile` function in `asl.nim` discards the parsed `File` and returns the raw source. Removing them also eliminated the `strutils`/`sequtils` imports.
- Linters may add `?` to `discard parser.run(...)` calls, turning optional parses into required ones. This silently breaks parsing when the consumed element isn't always present (e.g., optional spaces before `(`). Review linter changes carefully on Result-returning expressions.

## 2026-04-07 — Expression types, error propagation, and linting

- Expression ordering in `oneOf` follows specificity: string literal (starts with `"`), float literal (digit with `.` or `e`), integer literal (digit), initializer (identifier + `{` or space+literal), function call (identifier + `.` + name + `(`), getter (identifier + `.`), variable (bare identifier — always last, catches anything).
- `Literal` is a variant (string | integer | float) shared between expressions and primitive initializers. Expression has a single `ekLiteral` variant that forwards to `Literal`, avoiding three separate literal variants.
- Integer literal is itself a variant: `UnsignedIntegerLiteral` (`digit+`) and `SignedIntegerLiteral` (`(+|-) unsigned`). The sign is required for signed — a bare `42` is unsigned, `-42` is signed.
- Float literal requires either decimal part or exponent to distinguish from integer: `3.14` and `1e10` are floats, `42` is not. Tried before integer in `oneOf` since integers are a prefix of floats.
- Initializer is a variant: primitive (`identifier space+ literal`, e.g., `u8 0`) and non-primitive (`argumentType { kwargs }`, e.g., `Array[u32] { size: 10 }`). Primitive uses plain identifier for type, non-primitive uses `argumentType` (supports generics).
- Fatal error propagation: when `blockSpec`'s header succeeds but body fails, the error is marked `fatal: true`. `run` skips backtracking for fatal errors, `any` propagates them instead of silently returning partial results. This ensures error messages point to the real failure, not a misleading indentation mismatch at a higher level.
- `asl` methods on AST types use bottom-up approach: inline types return `string`, block types return `seq[string]`. Parents indent child lines by `" ".repeat(indentWidth)`. No `depth` tracking — indentation compounds naturally.
- Reuse existing types: `ArgumentDefinition` (`name: Type`) serves as struct fields, union variant fields, and function arguments. No need for separate `FieldDefinition` type.

## 2026-04-08 — Data blocks in modules

- Module body is `optional(dataBlock) + functionList`. Data block is `oneOf(struct, union)`. Must appear before functions if present.
- Struct block: `struct:` + field lines where each field is an `ArgumentDefinition`. No name on the struct — it's implicitly the module's data layout.
- Union block: `union:` + variant lines. Each `VariantDefinition` has a name and optional fields in braces (`Free { usage: u32 }`). Fields reuse `ArgumentDefinition` inside `contained("{", separatedBy(...), "}")`.
- Nameless block headers (`struct:`, `union:`) return just `Location` from their header spec. `blockSpec` handles them the same as named headers — the combine function ignores the location if not needed.
- Module body became a composite spec (`ModuleBody` tuple) since `blockSpec` takes a single body spec. The tuple `(Option[DataBlock], FunctionList)` is unpacked in the combine function.
