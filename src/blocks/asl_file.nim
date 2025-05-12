import results, strformat

import app

type AslFile* = ref object of RootObj
  apps: seq[App]

proc `$`*(file: AslFile): string =
  $(file.apps[0])

# TODO: add duplicate block validation
proc add_app*(file: AslFile, app: App): Result[void, string] =
  if file.apps.len == 1:
    return err(fmt"File must have at least one block")
  file.apps.add(app)
  ok()

# TODO: perform final validation
proc close*(file: AslFile): Result[void, string] =
  if file.apps.len != 1:
    return err(fmt"root block must have an app block")
  ok()
