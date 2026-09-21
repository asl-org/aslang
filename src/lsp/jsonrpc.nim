## JSON-RPC 2.0 over the LSP base protocol: each message is a
## `Content-Length: <n>` header block, a blank line, then `n` bytes of
## JSON. `readFrame` / `writeFrame` are the only procs in `src/lsp`
## that touch stdio; the message builders below are pure.

import json, options, strutils

const ContentLengthHeader = "content-length:"

proc contentLength(header: string): Option[int] =
  if header.toLowerAscii.startsWith(ContentLengthHeader):
    some(parseInt(header[ContentLengthHeader.len .. ^1].strip))
  else: none(int)

proc readHeaders(input: File): Option[int] =
  ## Reads header lines up to the blank separator. `none` on EOF or
  ## when no Content-Length header was present.
  ## `readLine` strips the CRLF terminator, so the separator reads as "".
  var length = none(int)
  var line = ""
  var open = input.readLine(line)
  while open and line.len > 0:
    let parsed = contentLength(line)
    if parsed.isSome: length = parsed
    open = input.readLine(line)
  if open: length else: none(int)

proc readBody(input: File, length: int): Option[string] =
  var body = newString(length)
  let got = if length > 0: input.readBuffer(addr body[0], length) else: 0
  if got == length: some(body) else: none(string)

proc readFrame*(input: File): Option[string] =
  ## One message body, or `none` once the client closed the stream.
  let length = readHeaders(input)
  if length.isSome: readBody(input, length.get) else: none(string)

proc writeFrame*(output: File, message: JsonNode) =
  let body = $message
  output.write("Content-Length: " & $body.len & "\r\n\r\n" & body)
  output.flushFile()

proc response*(id: JsonNode, payload: JsonNode): JsonNode =
  %*{"jsonrpc": "2.0", "id": id, "result": payload}

proc errorResponse*(id: JsonNode, code: int, message: string): JsonNode =
  %*{"jsonrpc": "2.0", "id": id, "error": {"code": code, "message": message}}

proc notification*(methodName: string, params: JsonNode): JsonNode =
  %*{"jsonrpc": "2.0", "method": methodName, "params": params}
