## Tests for the language server's pure parts: compiler error string →
## diagnostic mapping, URI conversion, message decoding, and the
## `handle` state machine (open / change / close over temp files).

import unittest, json, os, tables

import lsp/main as lsp
import tutils

proc publishedFor(outgoing: seq[JsonNode], path: string): seq[JsonNode] =
  var found: seq[JsonNode]
  for message in outgoing:
    if message{"method"}.getStr == "textDocument/publishDiagnostics" and
        message["params"]["uri"].getStr == path.toUri:
      found.add(message)
  found

proc diagnosticsIn(publish: JsonNode): seq[JsonNode] =
  publish["params"]["diagnostics"].getElems

proc openMessage(path: string, text: string): LspMessage =
  decode(%*{"jsonrpc": "2.0", "method": "textDocument/didOpen",
      "params": {"textDocument": {"uri": path.toUri, "languageId": "asl",
      "version": 1, "text": text}}})

proc changeMessage(path: string, text: string): LspMessage =
  decode(%*{"jsonrpc": "2.0", "method": "textDocument/didChange",
      "params": {"textDocument": {"uri": path.toUri, "version": 2},
      "contentChanges": [{"text": text}]}})

proc closeMessage(path: string): LspMessage =
  decode(%*{"jsonrpc": "2.0", "method": "textDocument/didClose",
      "params": {"textDocument": {"uri": path.toUri}}})

suite "lsp — error string → diagnostic":

  test "located error maps to a 0-based position":
    let d = toDiagnostic("/p/a.asl:7:8 duplicate type declaration encountered", "/p/root.asl")
    check d.path == "/p/a.asl"
    check d.line == 6
    check d.startCol == 7
    check d.endCol == 8
    check d.message == "duplicate type declaration encountered"

  test "located error keeps a trailing `see previous declaration at` location in the message":
    let d = toDiagnostic("/p/a.asl:7:8 duplicate field encountered, see previous declaration at /p/a.asl:6:5", "/p/root.asl")
    check d.path == "/p/a.asl"
    check d.message == "duplicate field encountered, see previous declaration at /p/a.asl:6:5"

  test "file-level error lands at the top of that file":
    let d = toDiagnostic("/p/missing.asl: file not found", "/p/root.asl")
    check d.path == "/p/missing.asl"
    check d.line == 0
    check d.message == "file not found"

  test "cyclic import lands at the top of the first file in the cycle":
    let d = toDiagnostic("cyclic dependency detected: /p/a.asl -> /p/b.asl -> /p/a.asl", "/p/root.asl")
    check d.path == "/p/a.asl"
    check d.line == 0

  test "unrecognized error lands at the top of the compile root":
    let d = toDiagnostic("internal compiler error: boom", "/p/root.asl")
    check d.path == "/p/root.asl"
    check d.message == "internal compiler error: boom"

  test "widen extends the range to the identifier under the start column":
    let d = toDiagnostic("/p/a.asl:2:9 type `Missing` is not defined", "/p/root.asl")
    let widened = d.widen("module M:\n    x = Missing.go()\n")
    check widened.startCol == 8
    check widened.endCol == 15

  test "widen keeps a one-character range on punctuation or past the end":
    let d = toDiagnostic("/p/a.asl:9:1 expected 'module'", "/p/root.asl")
    check d.widen("module M:\n").endCol == 1

suite "lsp — URIs and message decoding":

  test "path ↔ file URI round-trips, including spaces":
    let path = "/Users/me/my project/a.asl"
    check path.toUri == "file:///Users/me/my%20project/a.asl"
    check path.toUri.toPath == path

  test "didChange decodes the last content change as the full buffer":
    let message = changeMessage("/p/a.asl", "module M:\n")
    check message.kind == lmkDidChange
    check message.document.path == "/p/a.asl"
    check message.document.text == "module M:\n"

  test "an unknown request keeps its id; an unknown notification has none":
    check decode(%*{"jsonrpc": "2.0", "id": 4, "method": "textDocument/hover"}).kind == lmkUnknownRequest
    check decode(%*{"jsonrpc": "2.0", "method": "$/cancelRequest"}).kind == lmkUnknownNotification

suite "lsp — handle":

  test "initialize advertises full text sync":
    let (_, outgoing) = newLspServer(2, initTable[string, string]()).handle(
        decode(%*{"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {}}))
    check outgoing.len == 1
    check outgoing[0]["result"]["capabilities"]["textDocumentSync"]["change"].getInt == 1

  test "an unsaved broken buffer is diagnosed, and fixing it clears the diagnostic":
    let (roots, vendorDir) = writeStdVendor()
    let dir = writeFiles([("a.asl", "module M:\n  func go(): u8\n    u8 0\n")])
    let a = dir / "a.asl"
    let server = newLspServer(2, roots)
    let (opened, openOut) = server.handle(openMessage(a, "module M:\n  func go(): u8\n    x = Missing.go()\n    u8 0\n"))
    let (_, fixOut) = opened.handle(changeMessage(a, "module M:\n  func go(): u8\n    u8 0\n"))
    cleanupDir(dir); cleanupDir(vendorDir)
    check openOut.publishedFor(a).len == 1
    check openOut.publishedFor(a)[0].diagnosticsIn.len == 1
    check openOut.publishedFor(a)[0].diagnosticsIn[0]["range"]["start"]["line"].getInt == 2
    check fixOut.publishedFor(a)[0].diagnosticsIn.len == 0

  test "an error in an open imported buffer is published on the imported file":
    let (roots, vendorDir) = writeStdVendor()
    let dir = writeFiles([
      ("a.asl", "import { Helper } from \"./b.asl\"\n\nmodule Main:\n  func go(): u8\n    u8 0\n"),
      ("b.asl", "public module Helper:\n  public func go(): u8\n    u8 0\n"),
    ])
    let (a, b) = (dir / "a.asl", dir / "b.asl")
    let server = newLspServer(2, roots)
    let (withA, _) = server.handle(openMessage(a, readFile(a)))
    let (_, openBOut) = withA.handle(openMessage(b, "public module Helper:\n"))
    cleanupDir(dir); cleanupDir(vendorDir)
    check openBOut.publishedFor(b)[^1].diagnosticsIn.len == 1
    check openBOut.publishedFor(a)[^1].diagnosticsIn.len == 0

  test "closing a document clears its diagnostics":
    let (roots, vendorDir) = writeStdVendor()
    let dir = writeFiles([("a.asl", "module M:\n")])
    let a = dir / "a.asl"
    let (opened, openOut) = newLspServer(2, roots).handle(openMessage(a, readFile(a)))
    let (closed, closeOut) = opened.handle(closeMessage(a))
    cleanupDir(dir); cleanupDir(vendorDir)
    check openOut.publishedFor(a)[0].diagnosticsIn.len == 1
    check closeOut.publishedFor(a)[0].diagnosticsIn.len == 0
    check a notin closed.documents

  test "closing an unsaved broken import rechecks the roots that import it":
    # `a` imports `b`. A broken unsaved buffer for `b` makes root `a`
    # report an error on `b`. Closing `b` discards that buffer, so `a`
    # must be rechecked against the valid `b` on disk and the error cleared.
    let (roots, vendorDir) = writeStdVendor()
    let dir = writeFiles([
      ("a.asl", "import { Helper } from \"./b.asl\"\n\nmodule Main:\n  func go(): u8\n    u8 0\n"),
      ("b.asl", "public module Helper:\n  public func go(): u8\n    u8 0\n"),
    ])
    let (a, b) = (dir / "a.asl", dir / "b.asl")
    let (withA, _) = newLspServer(2, roots).handle(openMessage(a, readFile(a)))
    let (withB, openBOut) = withA.handle(openMessage(b, "public module Helper:\n"))
    let (_, closeOut) = withB.handle(closeMessage(b))
    cleanupDir(dir); cleanupDir(vendorDir)
    check openBOut.publishedFor(b)[^1].diagnosticsIn.len == 1
    check closeOut.publishedFor(b)[^1].diagnosticsIn.len == 0

  test "shutdown is acknowledged with a null result":
    let (after, outgoing) = newLspServer(2, initTable[string, string]()).handle(
        decode(%*{"jsonrpc": "2.0", "id": 9, "method": "shutdown"}))
    check after.shutdownRequested
    check outgoing[0]["result"].kind == JNull

suite "lsp — open TODO(growth-check)":

  # EXPECTED: unbounded type growth (grow[T] -> grow[Array[T]] -> ...) is
  # reported in the editor, at the growing call.
  # TODO(growth-check): today only the monomorphizer detects it, and the
  # server runs the front end only, so the buffer shows no diagnostic even
  # though `asl build` rejects it. This test asserts that. Flip it when the
  # TODO is fixed.
  test "unbounded type growth is not reported by the server":
    let source = """
public module M:
  public func grow(x: Any): u32!
    box = Array[Any] { size: u32 1 }
    filled = try Array.set(box, u32 0, x)
    _ = try M.grow(filled)
    u32!.Ok { value: u32 0 }

  public func start(): i32
    match M.grow(i32 0):
      case _:
        i32 0
"""
    # The real std (not `writeStdVendor`'s trimmed one): the program needs
    # `i32`, `Array` and `Error`, as it does under `asl build`.
    var roots = initTable[string, string]()
    roots["std"] = currentSourcePath().parentDir.parentDir / "examples" / "base.aslr"
    let dir = writeFiles([("a.asl", source)])
    let a = dir / "a.asl"
    let (_, openOut) = newLspServer(2, roots).handle(openMessage(a, source))
    cleanupDir(dir)
    check openOut.publishedFor(a)[^1].diagnosticsIn.len == 0
