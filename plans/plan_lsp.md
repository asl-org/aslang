# Plan — Language server (`asl lsp`) for editor tooling

## Status (as of 2026-09-21) — IN PROGRESS

- Done before this plan: `tooling/vscode-asl` TextMate grammar
  (a1a88e4); `.vscode/tasks.json` problem matchers over `asl build`
  output (1b48ffb).
- Phase 0 (W1–W4): implemented, uncommitted. Gates: 394/394 unit
  (+4 loader overlay, +2 CLI, +15 LSP), 35/36 integration (only
  nested_generics.asl, unchanged), sample.asl [SUCCESS]. Verified
  end-to-end against `asl lsp` with a scripted client and with
  `vscode-jsonrpc`: all 38 fixtures in `examples/` + `examples/errors/`
  publish the same error as `asl build`. Robustness also checked:
  malformed frame (dropped, server keeps going), path with spaces,
  >1 MB buffer, 50-edit burst (189 ms). Not yet exercised inside the
  VSCode UI (an automated extension-host run was blocked by the sandbox).
  Deviation from the design below: diagnostics are keyed per compile
  root (`diagnostics: Table[root, Diagnostic]`) instead of a flat
  `published` set, so a file's list is the union over roots and one
  root's fix can't clear another root's error.
- Phase 1 (W5): not started.
- Phase 2 (W6–W8): deferred until the resolver settles (the
  `ai-coding` flat-`ResolvedApp` migration and the monomorphization
  arc both reshape the structures a reference index would hang off).

## Context

The tasks.json problem matcher gives squiggles, but only on an explicit
build, only for saved files, and only the first error. An LSP server
fixes the first two immediately and is the host for everything later
(outline, go-to-definition, find-references, hover, semantic tokens).

Two facts about the current compiler shape the plan:

- **The parser reads from disk only.** `loadFile` → `readFileSafe`
  (`src/parser/main.nim`). An editor needs the *unsaved buffer* checked,
  and for imports of other open-and-dirty files to see their buffers too.
- **Errors are pre-formatted strings.** Every layer returns
  `Result[_, string]`; 113 of the 176 `err(` sites prefix `{loc}` →
  `<abs path>:<line>:<col> <message>`. The rest are file-level
  (`<path>: file not found`), cyclic imports
  (`cyclic dependency detected: <path> -> ...`), or location-less.
  Converting to a structured error type touches every layer and would
  conflict with the unmerged `ai-coding` branch, so Phase 0 parses the
  strings (same three shapes the tasks.json matchers already handle).

## Design

### Pipeline

```
VSCode ── vscode-languageclient (tooling/vscode-asl/extension.js)
   │  stdio, JSON-RPC with Content-Length framing
   ▼
asl lsp ── read frame → decode to LspMessage → handle (pure) → write frames
                                                  │
                             parse(root, overlays) → resolve → analyze
```

### Source overlays (W1)

`parse` gains an `overlays: Table[string, string]` argument — absolute
path → buffer text. `loadFile` reads from the overlay when the path is
present, else from disk. Both sources pass the same size / UTF-8
validation. The existing 4-arg `parse` stays as a delegating overload
passing an empty table (no default params), so the CLI and every test
are untouched.

Data, not a callback: the server owns a `Table` of open documents
already, and a table keeps `parse` free of closures.

### Messages as a tagged union (W2)

Incoming JSON decodes once into `LspMessage`, a `case kind:` union:
`initialize`, `initialized`, `shutdown`, `exit`, `didOpen`, `didChange`,
`didSave`, `didClose`, plus `unknownRequest` (has an id → reply
MethodNotFound) and `unknownNotification` (ignored). `handle(server,
message)` is pure and returns the next server state plus the outgoing
JSON messages; the stdio loop in `src/lsp/main.nim` is the only impure
part.

`LspServer` holds: `indentWidth`, `vendorRoots`, `documents` (path →
text), `published` (paths currently carrying diagnostics),
`shutdownRequested`.

Text sync is **Full** (the client sends the whole buffer on each
change). Compiles are milliseconds on the examples, so no debounce yet.

### Diagnostics (W3)

On open / change / save of file F: compile with F as root and every
open document as an overlay. On failure the error string maps to
`(path, range, message)`:

| Shape | Maps to |
|---|---|
| `<path>:<line>:<col> <msg>` | range at line/col, extended to the end of the identifier under it (read from the overlay or disk) |
| `<path>: <msg>` | line 0, col 0 of `<path>` |
| `cyclic dependency detected: <path> -> ...` | line 0, col 0 of the first path |
| anything else | line 0, col 0 of F |

Stale-diagnostic clearing: each publish replaces the file's set; any
path in `published` that has no error this round gets an empty publish.

Positions: compiler lines/cols are 1-based and rune-counted; LSP is
0-based UTF-16. Rune == UTF-16 unit for the BMP, which covers source
identifiers; astral chars in strings/comments can shift the column on
that line only. Accepted for Phase 0.

A `Defect` (compiler assert) during compile is caught and reported as
an `internal compiler error` diagnostic on F, so one crash doesn't kill
the server.

### VSCode client (W4)

`tooling/vscode-asl/extension.js` (plain JS, no build step) starts
`<asl.compilerPath> lsp --vendor=... --indent-width=...` over stdio.
Settings: `asl.compilerPath` (default: `asl` in the workspace root,
else `asl` on PATH), `asl.vendors` (list of `name:path`),
`asl.indentWidth`. `node_modules` is git-ignored; `npm install` once in
the folder.

## Work items

Every item keeps the three gates green (`nimble test`, `./test.sh`,
`./asl build examples/sample.asl` → [SUCCESS]).

### Phase 0 — live diagnostics

- **W1 [STRUCTURAL-neutral]** — source overlays in `parse`.
- **W2 [BEHAVIORAL]** — `asl lsp` subcommand: CLI variant
  `AslLspCommand` (indentWidth, vendorRoots), `src/lsp/` (framing,
  message union, server state, pure `handle`), stdio loop. `asl.nim`
  stops printing the `[INFO]` banner to stdout for `lsp` (it would
  corrupt the protocol stream).
- **W3 [BEHAVIORAL]** — diagnostics: error-string mapping, identifier
  range extension, stale clearing, Defect capture. Unit tests in
  `tests/test_lsp.nim` for the mapping and for `handle`.
- **W4 [BEHAVIORAL]** — VSCode client + settings; README updated.
  The tasks.json task stays as a fallback.

### Phase 1 — outline (parser only)

- **W5** — `textDocument/documentSymbol` from the parsed `File`:
  modules, generics, functions, struct fields, variants. Gives Outline,
  breadcrumbs, Cmd+Shift+O. Parse-only, so it works even when
  resolution fails.

### Phase 2 — after the resolver settles

- **W6** — reference index built during resolution: use-site span →
  definition `Location`. Enables `definition`, `references`, `hover`.
- **W7** — semantic tokens from the index (variant vs module vs field
  vs generic).
- **W8** — structured errors `(Location, message, related)` across all
  layers + error recovery (multiple diagnostics, partial results).

## Open TODOs

Each is also a `TODO(<tag>)` comment at the code site (`grep -rn
'TODO(parser-errors\|TODO(structured-errors\|TODO(lsp-' src`).

- **`TODO(parser-errors)`** — `src/parser/main.nim` (`parseAslFile`).
  Report the furthest parse failure instead of the last alternative
  tried; backtracking currently hides the real error and misplaces it.
- **`TODO(structured-errors)`** — `src/lsp/diagnostic.nim` header.
  Structured `(Location, message, related)` errors across all layers;
  retires the string parsing. Same work as W8.
- **`TODO(lsp-error-shapes)`** — `src/lsp/diagnostic.nim`
  (`ErrorShapes`). Recognize `<abs path> <message>` (1 MB limit,
  invalid UTF-8, read failure) so those land on the named file.
- **`TODO(lsp-stale-edits)`** — `src/lsp/server.nim` (`recheckAll`).
  Handle only the newest queued buffer per document / debounce.

## Non-goals (for now)

- Incremental re-parsing; the whole import graph recompiles per change.
- Multi-root workspaces or a project file; each open file is its own
  compile root.
- Publishing the extension to the marketplace.
