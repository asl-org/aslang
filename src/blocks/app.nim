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

proc c*(app: App): Result[string, string] =
  var fn_code: seq[string]
  for fn in app.fns:
    let fnc = ? fn.c(app.def.name)
    fn_code.add(fnc)
  let fn_code_str = fn_code.join("\n")

  let code = @[
    """
#include <stdio.h>
#include <stdint.h>
#include <inttypes.h>
typedef uint8_t Byte;

Byte Byte_print(Byte value) {
  return printf("%d\n", value);
}
""",
    fn_code_str,
    "int main(int argc, char** argv) {",
    fmt"return {app.def.name}_start((Byte)argc);",
    "}"
  ]

  ok(code.join("\n"))
