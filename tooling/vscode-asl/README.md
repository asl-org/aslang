# vscode-asl

ASLang support for `.asl` and `.aslr` files:

- Syntax highlighting (TextMate grammar).
- Live diagnostics from `asl lsp`: errors appear as you type, including
  in unsaved buffers and in open files that other open files import.

Go-to-definition, find-references and hover are planned; see
`plans/plan_lsp.md`.

## Install locally

```sh
cd tooling/vscode-asl && npm install && cd ../..
ln -s "$(pwd)/tooling/vscode-asl" ~/.vscode/extensions/vscode-asl
```

Then reload VSCode (`Developer: Reload Window`). The extension needs a
built compiler (`nimble build`).

Alternatively, open this folder in VSCode and press F5 to launch an
Extension Development Host.

## Settings

| Setting | Default | Meaning |
|---|---|---|
| `asl.compilerPath` | `""` | Path to `asl`. Empty: `asl` in the workspace root if present, else `asl` on PATH. |
| `asl.vendors` | `[]` | `name:path` entries passed as `--vendor=`. Without `std`, the compiler uses `examples/base.aslr` relative to the workspace root. |
| `asl.indentWidth` | `2` | Spaces per indentation level (2 or 4). |

Changing a setting restarts the server. After rebuilding the compiler,
run `ASLang: Restart Language Server`.

## Layout

- `package.json` registers the `asl` language, grammar, settings and
  the restart command.
- `extension.js` starts `asl lsp` over stdio via
  `vscode-languageclient`.
- `language-configuration.json` sets up `#` comments, bracket pairs,
  indentation-based folding, and indenting after a line ending in `:`.
- `syntaxes/asl.tmLanguage.json` is the grammar.

## Troubleshooting

- `Output` panel → `ASLang` shows the server's stderr.
- `Developer: Inspect Editor Tokens and Scopes` shows which grammar
  rule matched a token.
