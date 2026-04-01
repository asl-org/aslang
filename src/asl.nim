import os, results

import cli

when isMainModule:
  let maybeCommand = parseCliArgs(commandLineParams())
  if maybeCommand.isErr:
    stderr.writeLine(maybeCommand.error)
    quit(1)

  let command = maybeCommand.get
  echo command.kind
  echo command.debug
  echo command.outputFile
  echo command.indentWidth
