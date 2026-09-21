## `file://` URI ↔ absolute path. The editor addresses documents by
## URI; the compiler (and every error string it produces) by absolute
## path. Each path segment is percent-encoded on the way out so
## spaces and other reserved characters survive the round trip.

import std/[strutils, sequtils, uri]

const FileScheme = "file://"

proc toPath*(documentUri: string): string =
  if documentUri.startsWith(FileScheme): decodeUrl(documentUri[FileScheme.len .. ^1], false)
  else: decodeUrl(documentUri, false)

proc toUri*(path: string): string =
  FileScheme & path.split('/').mapIt(encodeUrl(it, false)).join("/")
