import results, strformat, strutils, sets
import "../rules"

import common
import matcher

type
  FunctionKind* = enum
    FK_USER, FK_NATIVE
  Function* = ref object of RootObj
    def: FunctionDefinition
    spaces: int
    case kind: FunctionKind
    of FK_USER:
      statements: seq[Statement]
      match_blocks: seq[Matcher]
    of FK_NATIVE: discard

proc def*(fn: Function): FunctionDefinition = fn.def
proc spaces*(fn: Function): int = fn.spaces
proc statements*(fn: Function): Result[seq[Statement], string] =
  case fn.kind:
  of FK_USER: ok(fn.statements)
  of FK_NATIVE: return err(fmt"Native functions do not have statements")

proc `$`*(fn: Function): string =
  let prefix = prefix(fn.spaces)
  let child_prefix = child_prefix(fn.spaces)
  var content: seq[string] = @[prefix & $(fn.def)]
  for statement in fn.statements:
    content.add((child_prefix & $(statement)))
  return content.join("\n")

proc new_user_function*(def: FunctionDefinition,
    spaces: int): Function =
  Function(kind: FK_USER, def: def, spaces: spaces)

proc new_native_function*(def: FunctionDefinition): Function =
  Function(kind: FK_NATIVE, def: def, spaces: 4)

# TODO: add duplicate block validation
proc add_statement*(fn: Function, statement: Statement): Result[void, string] =
  case fn.kind:
  of FK_NATIVE:
    err(fmt"Native functions do not support statements")
  of FK_USER:
    if fn.match_blocks.len > 0:
      return err(fmt"There can be no statements after match block in a function")
    fn.statements.add(statement)
    ok()

proc add_match_block*(fn: Function, matcher: Matcher): Result[void, string] =
  case fn.kind:
  of FK_NATIVE:
    err(fmt"Native functions do not support statements")
  of FK_USER:
    if fn.match_blocks.len > 0:
      return err(fmt"Function do not support multiple match blocks yet")
    fn.match_blocks.add(matcher)
    ok()

# TODO: perform final validation
proc close*(fn: Function): Result[void, string] =
  case fn.kind:
  of FK_NATIVE:
    return err(fmt"Native function can not have statements")
  of FK_USER:
    discard

  if fn.statements.len == 0 and fn.match_blocks.len == 0:
    return err(fmt"function block must have at least one statement or match block")

  var arg_name_set: HashSet[string]
  for arg_def in fn.def.arg_def_list.defs:
    let name = $(arg_def.name)
    if name in arg_name_set:
      return err(fmt"Parameter {name} is used twice in the function definition")
    arg_name_set.incl(name)
  ok()

proc match_fn_def*(self: Function, other: Function): bool =
  # same name
  if $(self.def.name) != $(other.def.name): return false
  # same return value
  if $(self.def.returns) != $(other.def.returns): return false
  # same arity (arg count)
  if self.def.arg_def_list.defs.len != other.def.arg_def_list.defs.len: return false

  # same arg datatypes
  for index, self_arg_def in self.def.arg_def_list.defs:
    let other_arg_def = other.def.arg_def_list.defs[index]
    if $(self_arg_def.module) != $(other_arg_def.module):
      return false

  return true

