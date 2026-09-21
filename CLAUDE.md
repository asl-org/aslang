# CLAUDE.md

## Editor tooling (VSCode extension + `asl lsp`)

The design record, phases (W1–W8) and open TODOs are in `plans/plan_lsp.md`.
Read it before changing anything below.

### What exists

- `tooling/vscode-asl/`: VSCode extension. It has:
  - a TextMate grammar (`syntaxes/asl.tmLanguage.json`) and
    `language-configuration.json`;
  - `extension.js`, a plain-JS `vscode-languageclient` client with no
    build step, which starts `asl lsp` over stdio.

  Settings: `asl.compilerPath` (empty means `./asl` in the workspace
  root, else `asl` on PATH), `asl.vendors`, `asl.indentWidth`. Run
  `npm install` once in the folder; `node_modules` is git-ignored.
  Install locally by symlinking the folder into `~/.vscode/extensions/`.
- `.vscode/tasks.json`: a Cmd+Shift+B task that runs `asl build` on the
  current file. It has three problem matchers: located, file-level and
  cyclic errors.
- `src/lsp/` (the `asl lsp [--indent-width] [--vendor]` subcommand):
  - Incoming JSON-RPC is decoded into the `LspMessage` tagged union.
  - A pure `handle` (`server.nim`) returns the next `LspServer` state
    plus the replies to send. `main.nim` owns the stdio loop.
  - Every open document is its own compile root. All open buffers are
    passed to `parse` as overlays (absolute path → text).
  - Diagnostics are keyed per compile root, so one root's fix never
    clears another root's error. Every open root is rechecked after
    each edit.
  - Compiler error strings are mapped to diagnostics by trying each
    known shape in turn (`diagnostic.nim`).

### Rules

- stdout is the protocol channel under `lsp`. Never `echo` on that
  path (`asl.nim` skips its `[INFO]` banner for `lsp`); log to stderr.
- `asl.nim`'s `compile` and `server.nim`'s `compile` each chain the
  pipeline by hand. When monomorphize / lifetime / codegen are added
  to the CLI, update the server too, or it silently stops reporting
  those errors.
- The server parses the compiler's error *wording*. A new `err(...)`
  should keep the `{loc} message` shape until structured errors land.

### Deferred (don't start unprompted)

- **Structured errors** (`TODO(structured-errors)`): `(Location,
  message, related)` instead of `Result[_, string]` in every layer.
  Planned by the maintainer; it touches every layer.
- **Phase 2** (reference index → go-to-definition, find-references,
  hover; semantic tokens): waits until the resolver settles.
- Other tags: `TODO(parser-errors)` (report the furthest parse failure;
  the biggest diagnostics-quality win), `TODO(lsp-error-shapes)`,
  `TODO(lsp-stale-edits)`.
- Next cheap step: **Phase 1** `textDocument/documentSymbol`
  (outline). It is parser-only, but needs block end ranges, since the
  AST has start `Location`s only.

### Publishing (not planned yet)

The process is `vsce` → Marketplace, plus Open VSX for VSCodium/Cursor.
Blocker first: the `std` vendor defaults to `examples/base.aslr`
relative to the current directory (`cli.nim` `buildVendorRoots`), and
the extension assumes an `asl` binary. Fix by resolving `std` relative
to the binary and shipping platform-specific VSIXs
(`vsce publish --target`) that bundle `asl` + `base.aslr`.

### Verifying tooling changes

- Grammar: tokenize `examples/` with `vscode-textmate` +
  `vscode-oniguruma` and check for unscoped tokens.
- Server: drive `./asl lsp` with `vscode-jsonrpc` (it is in the
  extension's `node_modules`). Open every `examples/**/*.asl` and
  compare the published diagnostic with `asl build`'s error (all 38
  matched at landing). Also cover a malformed frame, a path with
  spaces, a >1 MB buffer, and a burst of edits.
- An automated VSCode extension-host run hangs in Claude Code's sandbox;
  test the UI by hand instead.
