## `asl lsp` — the language server's stdio loop. Everything that
## decides *what* to send lives in `server.handle`; this file only
## reads frames, decodes them, and writes the replies.

import std/[json, options]

import ../parser/main as parser

import diagnostic
export diagnostic

import documenturi
export documenturi

import jsonrpc
export jsonrpc

import message
export message

import server
export server

type Turn = object
  server: LspServer
  exitCode: Option[int]

proc tryDecode(frame: string): Option[LspMessage] =
  try: some(decode(parseJson(frame)))
  except CatchableError:
    stderr.writeLine("[asl lsp] dropping malformed message: " & getCurrentExceptionMsg())
    none(LspMessage)

proc exitCode(server: LspServer): int =
  ## Per the LSP spec: 0 only when `shutdown` preceded `exit`.
  if server.shutdownRequested: 0 else: 1

proc respond(server: LspServer, message: LspMessage): Turn =
  let (next, outgoing) = server.handle(message)
  for reply in outgoing: stdout.writeFrame(reply)
  case message.kind:
  of lmkExit: Turn(server: next, exitCode: some(next.exitCode))
  else: Turn(server: next, exitCode: none(int))

proc turn(server: LspServer, frame: Option[string]): Turn =
  if frame.isNone:
    Turn(server: server, exitCode: some(server.exitCode))
  else:
    let message = tryDecode(frame.get)
    if message.isNone: Turn(server: server, exitCode: none(int))
    else: server.respond(message.get)

proc runLsp*(indentWidth: uint32, vendorRoots: VendorRoots): int =
  ## Serves until the client sends `exit` or closes stdin; returns the
  ## process exit code.
  var current = Turn(server: newLspServer(indentWidth, vendorRoots), exitCode: none(int))
  while current.exitCode.isNone:
    current = current.server.turn(readFrame(stdin))
  current.exitCode.get
