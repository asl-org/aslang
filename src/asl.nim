import os, results, strformat

import cli

proc compile(opts: AslBuildCommand): Result[void, string] =
  ok()

when isMainModule:
  let maybeCommand = parseCliArgs(commandLineParams())
  if maybeCommand.isErr:
    stderr.writeLine(fmt"[ERROR] - {maybeCommand.error}")
    quit(1)

  let command = maybeCommand.get
  if command.help.isOk:
    let helpCmd = command.help.get
    echo(helpCmd.help)
    quit(0)
  elif command.build.isOk:
    let buildCmd = command.build.get
    if buildCmd.debug: echo(fmt"[COMMAND] - {command}")

    let maybeCompiled = compile(buildCmd)
    if maybeCompiled.isErr:
      echo(fmt"[ERROR] - {maybeCompiled.error}")
      quit(1)
    else:
      quit(0)
