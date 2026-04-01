import argparse, strformat, results

type
  AslCommandKind* = enum
    cmdBuild

  AslCommand* = ref object of RootObj
    kind: AslCommandKind
    filename: string
    outputFile: string
    indentWidth: uint8
    debug: bool

proc kind*(cmd: AslCommand): AslCommandKind = cmd.kind
proc filename*(cmd: AslCommand): string = cmd.filename
proc outputFile*(cmd: AslCommand): string = cmd.outputFile
proc indentWidth*(cmd: AslCommand): uint8 = cmd.indentWidth
proc debug*(cmd: AslCommand): bool = cmd.debug

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
  except:
    err(fmt"[ERROR] - {getCurrentExceptionMsg()}" & "\n" & Usage)
