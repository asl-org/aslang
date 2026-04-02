import os, results, strformat, unicode

import cli, tokenizer

proc readFileSafe(filepath: string): Result[string, string] =
  const MaxFileByteSize = 1 * 1024 * 1024 # 1 MB
  try:
    let fileByteSize = getFileSize(filepath)
    if fileByteSize > MaxFileByteSize:
      err(fmt"{filepath} file exceeds 1 MB limit ({fileByteSize} bytes).")
    else:
      let source = readFile(filepath)
      let pos = validateUtf8(source)
      if pos == -1: ok(source)
      else: err(fmt"{filepath} invalid UTF-8 byte at position {pos}.")
  except IOError:
    err(fmt"{filepath} failed to read file.")

proc compile(opts: AslBuildCommand): Result[string, string] =
  let filepath = opts.filename.absolutePath
  let source = ? readFileSafe(filepath)
  let tokens = ? tokenize(source, filepath)
  for token in tokens: echo(token)
  ok(source)

when isMainModule:
  let maybeCommand = parseCliArgs(commandLineParams())
  if maybeCommand.isErr:
    stderr.writeLine(fmt"[ERROR] - {maybeCommand.error}")
    quit(1)

  let command = maybeCommand.get
  echo(fmt"[COMMAND] - {command}")
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
