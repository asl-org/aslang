import results

import parser

type File = parser.File

proc resolveImport(app: App, file: File, imp: Import): Result[void, string] =
  err("todo: resolve import")

proc resolveFile(app: App, file: File): Result[void, string] =
  for imp in file.imports:
    ? resolveImport(app, file, imp)

  err("todo: resolve file")

proc resolve*(app: App): Result[void, string] =
  for file in app.files:
    ? resolveFile(app, file)

  err("todo: resolve app")
