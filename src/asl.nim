import os, results, strformat

import cli

proc readFileSafe(filepath: string): Result[string, string] =
  const MaxFileByteSize = 1 * 1024 * 1024 # 1 MB
  try:
    let fileByteSize = getFileSize(filepath)
    if fileByteSize > MaxFileByteSize:
      err(fmt"File `{filepath}` exceeds 1 MB limit ({fileByteSize} bytes).")
    else:
      ok(readFile(filepath))
  except IOError:
    err(fmt"Failed to read file `{filepath}`.")

proc compile(opts: AslBuildCommand): Result[string, string] =
  let source = ? readFileSafe(opts.filename.absolutePath)
  ok(source)

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

    let maybeSuccess = compile(buildCmd)
    if maybeSuccess.isErr:
      stderr.writeLine(fmt"[ERROR] - {maybeSuccess.error}")
      quit(1)
    else:
      echo(maybeSuccess.get)
      quit(0)
