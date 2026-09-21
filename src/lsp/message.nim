## Incoming LSP messages, decoded once from JSON into a tagged union so
## the server dispatches on `kind` instead of re-reading JSON fields.
## Only the methods the server handles get their own variant; any
## other request (it carries an `id`) must still be answered, so it
## decodes to `lmkUnknownRequest`, and any other notification to
## `lmkUnknownNotification` (ignored).

import json

import documenturi

type
  TextDocument* = object
    path: string
    text: string

proc newTextDocument(path: string, text: string): TextDocument =
  TextDocument(path: path, text: text)

proc path*(document: TextDocument): string = document.path
proc text*(document: TextDocument): string = document.text

type
  LspMessageKind* = enum
    lmkInitialize
    lmkInitialized
    lmkShutdown
    lmkExit
    lmkDidOpen
    lmkDidChange
    lmkDidSave
    lmkDidClose
    lmkUnknownRequest
    lmkUnknownNotification

  LspMessage* = object
    case kind: LspMessageKind
    of lmkInitialize, lmkShutdown, lmkUnknownRequest: id: JsonNode
    of lmkDidOpen, lmkDidChange: document: TextDocument
    of lmkDidSave, lmkDidClose: path: string
    of lmkInitialized, lmkExit, lmkUnknownNotification: discard

proc kind*(message: LspMessage): LspMessageKind = message.kind
proc id*(message: LspMessage): JsonNode = message.id
proc document*(message: LspMessage): TextDocument = message.document
proc path*(message: LspMessage): string = message.path

const MethodKinds = [
  ("initialize", lmkInitialize),
  ("initialized", lmkInitialized),
  ("shutdown", lmkShutdown),
  ("exit", lmkExit),
  ("textDocument/didOpen", lmkDidOpen),
  ("textDocument/didChange", lmkDidChange),
  ("textDocument/didSave", lmkDidSave),
  ("textDocument/didClose", lmkDidClose),
]

proc methodKind(methodName: string, isRequest: bool): LspMessageKind =
  var kind = if isRequest: lmkUnknownRequest else: lmkUnknownNotification
  for (name, known) in MethodKinds:
    if name == methodName: kind = known
  kind

proc documentPath(params: JsonNode): string =
  params["textDocument"]["uri"].getStr.toPath

proc openedDocument(params: JsonNode): TextDocument =
  newTextDocument(documentPath(params), params["textDocument"]["text"].getStr)

proc changedDocument(params: JsonNode): TextDocument =
  ## Full text sync: the last content change carries the whole buffer.
  newTextDocument(documentPath(params), params["contentChanges"][^1]["text"].getStr)

proc decode*(message: JsonNode): LspMessage =
  let id = message.getOrDefault("id")
  let params = message.getOrDefault("params")
  let kind = methodKind(message.getOrDefault("method").getStr, not id.isNil)
  case kind:
  of lmkInitialize, lmkShutdown, lmkUnknownRequest: LspMessage(kind: kind, id: id)
  of lmkDidOpen: LspMessage(kind: kind, document: openedDocument(params))
  of lmkDidChange: LspMessage(kind: kind, document: changedDocument(params))
  of lmkDidSave, lmkDidClose: LspMessage(kind: kind, path: documentPath(params))
  of lmkInitialized, lmkExit, lmkUnknownNotification: LspMessage(kind: kind)
