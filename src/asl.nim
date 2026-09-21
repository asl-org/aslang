import os, results, strformat

import cli
import parser/main as parser
import resolver/main as resolver
import analyzer/main as analyzer
import lsp/main as lsp


proc compile(opts: AslBuildCommand): Result[string, string] =
  let filepath = opts.filename.absolutePath
  let app = ? parse(filepath, opts.indentWidth, opts.dumpTokens, opts.vendorRoots)
  let resolvedApp = ? resolve(app)
  let analyzedApp = ? analyze(resolvedApp)
  ok("[SUCCESS]")

when isMainModule:
  let maybeCommand = parseCliArgs(commandLineParams())
  if maybeCommand.isErr:
    stderr.writeLine(fmt"[ERROR] - {maybeCommand.error}")
    quit(1)

  let command = maybeCommand.get
  case command.kind:
  of ackHelp:
    let helpCmd = command.help.get
    echo(helpCmd.help)
    quit(0)
  of ackBuild:
    echo(fmt"[INFO] - Building `{command}`")
    let buildCmd = command.build.get
    let maybeSuccess = compile(buildCmd)
    if maybeSuccess.isErr:
      stderr.writeLine(fmt"[ERROR] - {maybeSuccess.error}")
      quit(1)
    else:
      echo(maybeSuccess.get)
      quit(0)
  of ackLsp:
    let lspCmd = command.lsp.get
    quit(runLsp(lspCmd.indentWidth, lspCmd.vendorRoots))
