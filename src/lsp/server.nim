## Server state + the message handler. `handle` takes the current
## state and one decoded message and returns the next state plus the
## JSON messages to send; the stdio loop in `main.nim` does the I/O.
##
## Diagnostics are owned per compile root: every open document is a
## root, compiled with all open buffers as overlays. A root's error may
## land in a file it imports, so a file's published list is the union
## of every root's diagnostic that points at it. After any edit every
## open root is rechecked, since the edit may break (or fix) a file
## that imports it.

import std/[json, sequtils, tables]
import results

import ../parser/main as parser
import ../resolver/main as resolver
import ../analyzer/main as analyzer

import diagnostic, documenturi, jsonrpc, message

const MethodNotFound = -32601

type LspServer* = object
  indentWidth: uint32
  vendorRoots: VendorRoots
  documents: Table[string, string]        # open path → buffer text
  diagnostics: Table[string, Diagnostic]  # compile root → its error
  shutdownRequested: bool

proc newLspServer*(indentWidth: uint32, vendorRoots: VendorRoots): LspServer =
  LspServer(indentWidth: indentWidth, vendorRoots: vendorRoots)

proc shutdownRequested*(server: LspServer): bool = server.shutdownRequested
proc documents*(server: LspServer): Table[string, string] = server.documents

proc capabilities(): JsonNode =
  %*{
    "capabilities": {
      "textDocumentSync": {"openClose": true, "change": 1, "save": {"includeText": false}},
    },
    "serverInfo": {"name": "asl"},
  }

proc compile(rootPath: string, indentWidth: uint32, vendorRoots: VendorRoots,
    overlays: Table[string, string]): Result[void, string] =
  let app = ? parse(rootPath, indentWidth, false, vendorRoots, overlays)
  let resolvedApp = ? resolve(app)
  discard ? analyze(resolvedApp)
  ok()

proc safeCompile(rootPath: string, indentWidth: uint32, vendorRoots: VendorRoots,
    overlays: Table[string, string]): Result[void, string] =
  ## A compiler assert must not take the server down with it.
  try: compile(rootPath, indentWidth, vendorRoots, overlays)
  except CatchableError, Defect: err("internal compiler error: " & getCurrentExceptionMsg())

proc sourceOf(documents: Table[string, string], path: string): string =
  if path in documents: documents[path]
  else:
    try: readFile(path)
    except CatchableError: ""

proc diagnosticPaths(diagnostics: Table[string, Diagnostic], root: string): seq[string] =
  if root in diagnostics: @[diagnostics[root].path] else: @[]

proc recheck(server: LspServer, root: string): (LspServer, seq[string]) =
  ## Compiles `root`; returns the next state and every path whose
  ## published list may have changed (the root's old and new targets).
  let outcome = safeCompile(root, server.indentWidth, server.vendorRoots, server.documents)
  var next = server
  if outcome.isErr:
    let found = toDiagnostic(outcome.error, root)
    next.diagnostics[root] = found.widen(sourceOf(server.documents, found.path))
  else: next.diagnostics.del(root)
  (next, @[root] & diagnosticPaths(server.diagnostics, root) & diagnosticPaths(next.diagnostics, root))

proc publish(diagnostics: Table[string, Diagnostic], path: string): JsonNode =
  let items = toSeq(diagnostics.values).filterIt(it.path == path).deduplicate.mapIt(it.toJson)
  notification("textDocument/publishDiagnostics", %*{"uri": path.toUri, "diagnostics": items})

proc recheckAll(server: LspServer, first: string): (LspServer, seq[JsonNode]) =
  ## `first` (the edited file) goes first; then every other open root.
  let roots = @[first] & toSeq(server.documents.keys).filterIt(it != first)
  var next = server
  var affected: seq[string]
  for root in roots:
    let (checked, paths) = next.recheck(root)
    next = checked
    affected.add(paths)
  (next, affected.deduplicate.mapIt(publish(next.diagnostics, it)))

proc open(server: LspServer, document: TextDocument): LspServer =
  var next = server
  next.documents[document.path] = document.text
  next

proc close(server: LspServer, path: string): (LspServer, seq[JsonNode]) =
  var next = server
  next.documents.del(path)
  next.diagnostics.del(path)
  let affected = (@[path] & diagnosticPaths(server.diagnostics, path)).deduplicate
  (next, affected.mapIt(publish(next.diagnostics, it)))

proc shutdown(server: LspServer): LspServer =
  var next = server
  next.shutdownRequested = true
  next

proc handle*(server: LspServer, message: LspMessage): (LspServer, seq[JsonNode]) =
  case message.kind:
  of lmkInitialize: (server, @[response(message.id, capabilities())])
  of lmkShutdown: (server.shutdown, @[response(message.id, newJNull())])
  of lmkUnknownRequest: (server, @[errorResponse(message.id, MethodNotFound, "method not supported")])
  of lmkDidOpen, lmkDidChange: server.open(message.document).recheckAll(message.document.path)
  of lmkDidSave: server.recheckAll(message.path)
  of lmkDidClose: server.close(message.path)
  of lmkInitialized, lmkExit, lmkUnknownNotification: (server, @[])
