import os, results, strformat

import cli, parser, resolver, analyzer

proc compile(opts: AslBuildCommand): Result[string, string] =
  let filepath = opts.filename.absolutePath
  let app = ? parse(filepath, opts.indentWidth, opts.dumpTokens, opts.vendorRoots)
  let resolvedApp = ? resolve(app)
  discard ? analyze(resolvedApp)
  ok("[SUCCESS]")

when isMainModule:
  let maybeCommand = parseCliArgs(commandLineParams())
  if maybeCommand.isErr:
    stderr.writeLine(fmt"[ERROR] - {maybeCommand.error}")
    quit(1)

  let command = maybeCommand.get
  echo(fmt"[INFO] - Executing command -> {command}")
  case command.kind:
  of ackHelp:
    let helpCmd = command.help.get
    echo(helpCmd.help)
    quit(0)
  of ackBuild:
    let buildCmd = command.build.get
    let maybeSuccess = compile(buildCmd)
    if maybeSuccess.isErr:
      stderr.writeLine(fmt"[ERROR] - {maybeSuccess.error}")
      quit(1)
    else:
      echo(maybeSuccess.get)
      quit(0)
