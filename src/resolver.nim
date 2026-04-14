import results

import parser

type File = parser.File

proc resolve(app: App, file: File, imp: Import): Result[void, string] =
  echo "Resolving import: ", imp.source, " path: ", imp.path
  err("todo: resolve imports")

proc resolve(app: App, file: File, module: Module): Result[void, string] =
  echo "Resolving module: ", module.name.value
  err("todo: resolve modules")

proc resolve(app: App, file: File): Result[void, string] =
  echo "Resolving file: ", file.path
  for imp in file.imports:
    ? resolve(app, file, imp)
  for module in file.modules:
    ? resolve(app, file, module)
  err("todo: resolve file")

proc resolve*(app: App): Result[void, string] =
  echo "Resolving app..."
  for file in app.files:
    ? resolve(app, file)
  err("todo: resolve app")
