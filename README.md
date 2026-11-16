# ASL

ASL ("a Software Language", also called ASLang) is a statically typed
language for mission-critical software, and this repository is its
compiler, written in Nim. The compiler is meant to emit C first and
Verilog/VHDL later, so every generic is specialized away before code
generation.

## Status

- **Works end to end:** tokenizer → parser → resolver → definition
  analyzer → analyzer → monomorphizer.
- **No code generation yet.** `asl build` checks a program and prints
  `[SUCCESS]`, but writes no output. `--debug` and `-o/--output` are
  rejected until code generation exists.
- **Editor support:** a language server (`asl lsp`) with live
  diagnostics, and a VSCode extension.
- **Next:** ownership/lifetime analysis on the monomorphized program,
  then C code generation. See [overview.md](overview.md) §"What's Next".

## A taste of ASL

```asl
module Counter:
  struct:
    value: u32

  public func next(c: Counter): Counter!
    c.value = try u32.add(c.value, 1)
    Counter!.Ok { value: c }

public module Driver:
  public func start(): i32
    c = Counter { value: u32 0 }
    match Counter.next(c):
      case Ok { value: n }:
        value = string.from(n.value)
        System.println(value)
        i32 0
      case Err { error: e }:
        i32 1
```

- Code lives in **modules**. A module can hold one data block (`struct`,
  `union`, or `literal` for primitives) plus functions.
- **No operators and no exceptions.** Arithmetic is a call
  (`u32.add(a, b)`) that can fail, so it returns a `Status`; `T!` is
  short for `Status[T, Error]`, and `try` unwraps the value or passes
  the error up.
- **`match`** handles integers, bindings and union variants, and must
  cover every case.
- A function's last expression is its value; there is no `return`.
- `public` controls what other modules and files can use. A program
  needs one public module with `public func start(): i32`.

The full language reference is [documentation.md](documentation.md).

## Getting started

You need Nim 2.2 or newer, with `nimble`. The two dependencies are
pinned in [asl.nimble](asl.nimble).

```sh
nimble install -d               # install the pinned dependencies
nimble build                    # builds ./asl
./asl build examples/hello.asl  # check a program: prints [SUCCESS]
```

Run `asl` from the repository root. The standard library
([examples/base.aslr](examples/base.aslr)) is found at
`examples/base.aslr` relative to the current directory, so from
anywhere else pass it explicitly:
`--vendor=std:<vendor-path>/examples/base.aslr`.

`./asl --help` lists the options; [documentation.md](documentation.md)
§"CLI" explains them.

## Testing

Two gates, both run from the repository root:

```sh
nimble test   # unit suite (tests/all.nim)
./test.sh     # builds ./asl, then every examples/*.asl must build and
              # every examples/errors/*.asl must fail (two support
              # files there are skipped)
```

Known gaps are pinned by tests that assert today's behavior under an
`EXPECTED:` / `TODO(...)` comment. Fixing the TODO makes such a test
fail, which is the cue to flip it.

## Editor support

`./asl lsp` runs a language server over stdio. It reports the
compiler's error for every open file, including unsaved changes. The
VSCode extension in [tooling/vscode-asl](tooling/vscode-asl/README.md)
adds syntax highlighting and connects to it. For build-on-demand,
`.vscode/tasks.json` runs `asl build` on the current file
(Cmd+Shift+B).

## Repository layout

```
src/              the compiler (one package per pipeline stage)
  tokenizer/ parser/ resolver/ defanalyzer/ analyzer/
  monomorphize.nim  cli.nim  asl.nim  lsp/
examples/         sample programs, plus base.aslr (the standard library)
  errors/         programs that must fail, one rule each
tests/            unit tests (test_*.nim, aggregated by all.nim)
tooling/vscode-asl/  VSCode extension
plans/            design plans for current and upcoming work
```

## Documentation

| Document | What it covers |
|---|---|
| [documentation.md](documentation.md) | The language: syntax, types, generics, `match`, `try`, the CLI. Start here to write ASL. |
| [overview.md](overview.md) | How the compiler works: each pipeline stage, the project structure, design patterns, testing, and what's next. Start here to work on the compiler. |
| [grammar.md](grammar.md) | The domain grammar: the shapes every compiler stage's types follow. Changes to a concept land here first. |
| [validations.md](validations.md) | Every rule the compiler enforces, grouped by stage, each with the test that pins it. |
| [lessons.md](lessons.md) | Design retrospective: what was tried, what changed, and why. |
| [CLAUDE.md](CLAUDE.md) | Working notes for AI assistants, mainly the editor-tooling rules (stdout is the LSP channel, the server runs the front end only). |
| [tooling/vscode-asl/README.md](tooling/vscode-asl/README.md) | Installing and configuring the VSCode extension. |
| [plans/](plans/) | Design plans, e.g. the monomorphizer, the execution model, the language server roadmap. |

## License

MIT, as declared in [asl.nimble](asl.nimble).
