import argparse, strformat, results, os

const Usage = """Usage: asl <command> [options]

Commands:
  build <filename>      Compile an ASLang source file

Options:
  --debug               Emit source location comments in generated C
  --indent-width=<N>    Spaces per indentation level (default: 2)
  [-o|--output]=<file>  Output binary path (default: input filename without extension)
  [-h|--help]           Show this help message"""


type AslBuildCommand* = object
  filename: string
  outputFile: string
  indentWidth: uint8
  debug: bool

proc newAslBuildCommand(filename: string, outputFile: string,
    indentWidth: uint8, debug: bool): AslBuildCommand =
  AslBuildCommand(filename: filename, outputFile: outputFile,
      indentWidth: indentWidth, debug: debug)

proc filename*(cmd: AslBuildCommand): string = cmd.filename
proc outputFile*(cmd: AslBuildCommand): string = cmd.outputFile
proc indentWidth*(cmd: AslBuildCommand): uint8 = cmd.indentWidth
proc debug*(cmd: AslBuildCommand): bool = cmd.debug

proc `$`*(cmd: AslBuildCommand): string =
  let debug = if cmd.debug: fmt"--debug" else: ""
  fmt"build {cmd.filename} --output={cmd.outputFile} --indent-width={cmd.indentWidth} {debug}"

type AslHelpCommand* = object
  help: string

proc newAslHelpCommand(): AslHelpCommand =
  AslHelpCommand(help: Usage)

proc help*(cmd: AslHelpCommand): string = cmd.help
proc `$`(cmd: AslHelpCommand): string = "--help"

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
  else: err("Property `build` is not available on `AslCommand` object")
proc help*(cmd: AslCommand): Result[AslHelpCommand, string] =
  case cmd.kind:
  of ackHelp: ok(cmd.help)
  else: err("Property `help` is not available on `AslCommand` object")

proc `$`*(cmd: AslCommand): string =
  case cmd.kind:
  of ackBuild: fmt"asl {cmd.build}"
  of ackHelp: fmt"asl {cmd.help}"

proc parseCliArgs*(args: seq[string]): Result[AslCommand, string] =
  var p = newParser:
    command("build"):
      arg("filename", nargs = 1)
      flag("--debug")
      option("-o", "--output")
      option("--indent-width", default = some("2"), choices = @["2", "4"])

  try:
    let opts = p.parse(args)
    if opts.argparseBuildOpts.isSome:
      let buildOpts = opts.argparseBuildOpts.get

      let (_, _, ext) = buildOpts.filename.splitFile()
      if ext != ".asl":
        return err(fmt"source file must have a '.asl' extension, got: {buildOpts.filename}")

      let outputFile =
        if buildOpts.output == "": buildOpts.filename.changeFileExt("")
        else: buildOpts.output

      let indentWidth = parseInt(buildOpts.indentWidth).uint8
      let buildCmd = newAslBuildCommand(buildOpts.filename, outputFile,
          indentWidth, buildOpts.debug)
      ok(newAslCommand(buildCmd))
    else:
      ok(newAslCommand(newAslHelpCommand()))
  except ShortCircuit:
    ok(newAslCommand(newAslHelpCommand()))
  except CatchableError:
    err(getCurrentExceptionMsg() & "\n\n" & Usage)
