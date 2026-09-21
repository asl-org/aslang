# vscode-asl

Syntax highlighting for ASLang `.asl` and `.aslr` files. It is a
TextMate grammar only; go-to-definition and diagnostics need a
language server (a future `asl lsp`).

## Install locally

```sh
ln -s "$(pwd)/tooling/vscode-asl" ~/.vscode/extensions/vscode-asl
```

Then reload VSCode (`Developer: Reload Window`).

Alternatively, open this folder in VSCode and press F5 to launch an
Extension Development Host.

## Layout

- `package.json` registers the `asl` language for `.asl` and `.aslr`.
- `language-configuration.json` sets up `#` comments, bracket pairs,
  indentation-based folding, and indenting after a line ending in `:`.
- `syntaxes/asl.tmLanguage.json` is the grammar.

## Inspecting scopes

Run `Developer: Inspect Editor Tokens and Scopes` on a token to see
which grammar rule matched it.
