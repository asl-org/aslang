import argparse, strformat, results, os, tables, strutils

import parser/index as parser

const Usage = """Usage: asl <command> [options]

Commands:
  build <filename>      Compile an ASLang source file

Options:
  --debug               Emit source location comments in generated C
  --dump-tokens         Dump token stream to stdout after tokenization
  --indent-width=<N>    Spaces per indentation level (default: 2)
  --vendor=<name:path>  Register a vendor (repeatable). Vendor paths
                        are referenced from source as `import "@<name>"`.
                        Default: `std:examples/base.aslr` when --vendor
                        does not include a `std` entry.
  [-o|--output]=<file>  Output binary path (default: input filename without extension)
  [-h|--help]           Show this help message"""


type AslBuildCommand* = object
  filename: string
  outputFile: string
  indentWidth: uint32
  debug: bool
  dumpTokens: bool
  vendorRoots: VendorRoots

proc newAslBuildCommand(filename: string, outputFile: string,
    indentWidth: uint32, debug: bool, dumpTokens: bool,
    vendorRoots: VendorRoots): AslBuildCommand =
  AslBuildCommand(filename: filename, outputFile: outputFile,
      indentWidth: indentWidth, debug: debug, dumpTokens: dumpTokens,
      vendorRoots: vendorRoots)

proc filename*(cmd: AslBuildCommand): string = cmd.filename
proc indentWidth*(cmd: AslBuildCommand): uint32 = cmd.indentWidth
proc dumpTokens*(cmd: AslBuildCommand): bool = cmd.dumpTokens
proc vendorRoots*(cmd: AslBuildCommand): VendorRoots = cmd.vendorRoots

proc `$`*(cmd: AslBuildCommand): string =
  var debugFlags: seq[string]
  if cmd.debug: debugFlags.add("--debug")
  if cmd.dumpTokens: debugFlags.add("--dump-tokens")
  for name, path in cmd.vendorRoots.pairs:
    debugFlags.add(fmt"--vendor={name}:{path}")

  let debugFlagsStr = debugFlags.join(" ")
  fmt"build {cmd.filename} --output={cmd.outputFile} --indent-width={cmd.indentWidth} {debugFlagsStr}"

type AslHelpCommand* = object
  help: string

proc newAslHelpCommand(): AslHelpCommand =
  AslHelpCommand(help: Usage)

proc help*(cmd: AslHelpCommand): string = cmd.help
proc `$`*(cmd: AslHelpCommand): string = "--help"

type
  AslCommandKind* = enum
    ackBuild
    ackHelp

  AslCommand* = object
    case kind: AslCommandKind
    of ackBuild: build: AslBuildCommand
    of ackHelp: help: AslHelpCommand

proc newAslCommand(build: AslBuildCommand): AslCommand =
  AslCommand(kind: ackBuild, build: build)

proc newAslCommand(help: AslHelpCommand): AslCommand =
  AslCommand(kind: ackHelp, help: help)

proc kind*(cmd: AslCommand): AslCommandKind = cmd.kind
proc build*(cmd: AslCommand): Result[AslBuildCommand, string] =
  case cmd.kind:
  of ackBuild: ok(cmd.build)
  else: err("property `build` is not available on `AslCommand` object.")
proc help*(cmd: AslCommand): Result[AslHelpCommand, string] =
  case cmd.kind:
  of ackHelp: ok(cmd.help)
  else: err("property `help` is not available on `AslCommand` object.")

proc `$`*(cmd: AslCommand): string =
  case cmd.kind:
  of ackBuild: fmt"asl {cmd.build}"
  of ackHelp: fmt"asl {cmd.help}"

proc isValidVendorIdent(name: string): bool =
  ## ASL identifier rules — same shape as the parser's vendor-name
  ## validation in `toImportPath`. Head: ASCII letter or
  ## underscore; tail: letter, digit, or underscore.
  if name.len == 0: return false
  if not (name[0].isAlphaAscii or name[0] == '_'): return false
  for c in name[1..^1]:
    if not (c.isAlphaNumeric or c == '_'): return false
  true

proc parseVendorFlag(value: string): Result[(string, string), string] =
  ## Splits a `--vendor=<name>:<path>` value on its first `:`.
  ## Validates that both sides are non-empty and `name` is a valid
  ## ASL identifier (mirroring the parser's rule so user-typed
  ## `import "@<name>"` and CLI-typed `--vendor=<name>:...` agree
  ## on what a name looks like).
  let idx = value.find(':')
  if idx < 0:
    return err(fmt"--vendor value '{value}' must use the form '<name>:<path>'")
  let name = value[0..<idx]
  let path = value[idx+1..^1]
  if name.len == 0:
    return err(fmt"--vendor value '{value}' has an empty vendor name")
  if path.len == 0:
    return err(fmt"--vendor value '{value}' has an empty path")
  if not isValidVendorIdent(name):
    return err(fmt"--vendor name '{name}' is not a valid ASL identifier (head: letter or underscore; tail: letters, digits, underscore)")
  ok((name, path))

proc buildVendorRoots(rawFlags: seq[string]): Result[VendorRoots, string] =
  ## Validates and aggregates every `--vendor=...` value into a
  ## `VendorRoots` table. Rejects duplicate names with both paths in
  ## the diagnostic. After all user-supplied flags, defaults `std`
  ## to `examples/base.aslr` (absolute) when the user did not
  ## register a `std` vendor of their own.
  var roots = initTable[string, string]()
  for raw in rawFlags:
    let (name, path) = ? parseVendorFlag(raw)
    let absPath = path.absolutePath
    if name in roots:
      return err(fmt"--vendor name '{name}' specified more than once: '{roots[name]}' vs '{absPath}'")
    roots[name] = absPath
  if "std" notin roots:
    roots["std"] = "examples/base.aslr".absolutePath
  ok(roots)

proc parseCliArgs*(args: seq[string]): Result[AslCommand, string] =
  var p = newParser:
    command("build"):
      arg("filename", nargs = 1)
      option("-o", "--output")
      option("--indent-width", default = some("2"), choices = @["2", "4"])
      option("--vendor", multiple = true)
      flag("--debug")
      flag("--dump-tokens")

  try:
    let opts = p.parse(args)
    if opts.argparseBuildOpts.isSome:
      let buildOpts = opts.argparseBuildOpts.get

      let (_, _, ext) = buildOpts.filename.splitFile()
      if ext != ".asl":
        return err(fmt"source file `{buildOpts.filename}` must have a '.asl' extension.")

      let outputFile =
        if buildOpts.output == "": buildOpts.filename.changeFileExt("")
        else: buildOpts.output

      let indentWidth = parseInt(buildOpts.indentWidth).uint32
      let vendorRoots = ? buildVendorRoots(buildOpts.vendor)
      let buildCmd = newAslBuildCommand(buildOpts.filename, outputFile,
          indentWidth, buildOpts.debug, buildOpts.dumpTokens, vendorRoots)
      ok(newAslCommand(buildCmd))
    else:
      ok(newAslCommand(newAslHelpCommand()))
  except ShortCircuit:
    ok(newAslCommand(newAslHelpCommand()))
  except CatchableError:
    err(getCurrentExceptionMsg() & "\n\n" & Usage)
