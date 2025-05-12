import strutils, results, strformat

import "../rules"

import common, function

type App* = ref object of RootObj
  def: AppDefinition
  fns: seq[Function]
  spaces: int

proc `$`*(app: App): string =
  var content: seq[string] = @[prefix(app.spaces) & $(app.def)]
  for fn in app.fns:
    content.add($(fn))
  content.join("\n")

proc new_app*(def: AppDefinition, spaces: int): App =
  App(def: def, spaces: spaces)

# TODO: add duplicate block validation
proc add_fn*(app: App, fn: Function): void =
  app.fns.add(fn)

# TODO: perform final validation
proc close*(app: App): Result[void, string] =
  if app.fns.len == 0:
    return err(fmt"app block must have at least one function block")
  ok()
