import argparse, strformat, results, os

type
  AslCommandKind* = enum
    cmdBuild

  AslCommand* = object
    kind: AslCommandKind
    filename: string
    outputFile: string
    indentWidth: uint8
    debug: bool

proc `$`(cmdKind: AslCommandKind): string =
  case cmdKind:
  of cmdBuild: "build"

proc kind*(cmd: AslCommand): AslCommandKind = cmd.kind
proc filename*(cmd: AslCommand): string = cmd.filename
proc outputFile*(cmd: AslCommand): string = cmd.outputFile
proc indentWidth*(cmd: AslCommand): uint8 = cmd.indentWidth
proc debug*(cmd: AslCommand): bool = cmd.debug
proc `$`*(cmd: AslCommand): string =
  let debug = if cmd.debug: fmt"--debug" else: ""
  fmt"asl {cmd.kind} {cmd.filename} --output={cmd.outputFile} --indent-width={cmd.indentWidth} {debug}"

const Usage = """Usage: asl <command> [options]

Commands:
  build <filename>      Compile an ASLang source file

Options:
  --debug               Emit source location comments in generated C
  --indent-width=<N>    Spaces per indentation level (default: 2)
  [-o|--output]=<file>  Output binary path (default: input filename without extension)
  [-h|--help]           Show this help message"""

proc parseCliArgs*(args: seq[string]): Result[AslCommand, string] =
  var p = newParser:
    command("build"):
      arg("filename", nargs = 1)
      flag("--debug")
      option("-o", "--output")
      option("--indent-width", default = some("2"), choices = @["2", "4"])

  try:
    let opts = p.parse(args)
    if opts.argparseBuildOpts.is_some:
      let buildOpts = opts.argparseBuildOpts.get

      let (_, _, ext) = buildOpts.filename.splitFile()
      if ext != ".asl":
        return err("[ERROR] - Source file must have a '.asl' extension, got: " &
            buildOpts.filename)

      let outputFile =
        if buildOpts.output == "": buildOpts.filename.changeFileExt("")
        else: buildOpts.output

      ok(AslCommand(
        kind: cmdBuild,
        filename: buildOpts.filename,
        debug: buildOpts.debug,
        outputFile: outputFile,
        indentWidth: parseInt(buildOpts.indentWidth).uint8,
      ))
    else:
      err(Usage)
  except CatchableError:
    err(fmt"[ERROR] - {getCurrentExceptionMsg()}" & "\n" & Usage)
