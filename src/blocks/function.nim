import results, strformat, strutils
import "../rules"

import common

type Function* = ref object of RootObj
  def: FunctionDefinition
  statements: seq[Statement]
  spaces: int

proc `$`*(fn: Function): string =
  let prefix = prefix(fn.spaces)
  let child_prefix = child_prefix(fn.spaces)
  var content: seq[string] = @[prefix & $(fn.def)]
  for statement in fn.statements:
    content.add((child_prefix & $(statement)))
  return content.join("\n")

proc new_function*(def: FunctionDefinition,
    spaces: int): Function =
  Function(def: def, spaces: spaces)

# TODO: add duplicate block validation
proc add_statement*(fn: Function, statement: Statement): void =
  fn.statements.add(statement)

# TODO: perform final validation
proc close*(fn: Function): Result[void, string] =
  if fn.statements.len == 0:
    return err(fmt"function block must have at least one statement")
  ok()
