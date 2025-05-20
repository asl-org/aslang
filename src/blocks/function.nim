import results, strformat, strutils, sets, sequtils
import "../rules"

import common
import matcher

type
  FunctionStepKind* = enum
    FSK_STATEMENT, FSK_MATCHER
  FunctionStep* = ref object of RootObj
    case kind: FunctionStepKind
    of FSK_STATEMENT: statement: Statement
    of FSK_MATCHER: matcher: Match

proc new_function_step(matcher: Match): FunctionStep =
  FunctionStep(kind: FSK_MATCHER, matcher: matcher)

proc new_function_step(statement: Statement): FunctionStep =
  FunctionStep(kind: FSK_STATEMENT, statement: statement)

proc kind*(step: FunctionStep): FunctionStepKind = step.kind
proc statement*(step: FunctionStep): Statement = step.statement
proc matcher*(step: FunctionStep): Match = step.matcher

proc `$`*(step: FunctionStep): string =
  case step.kind:
  of FSK_MATCHER: $(step.matcher)
  of FSK_STATEMENT: $(step.statement)

type
  FunctionKind* = enum
    FK_USER, FK_NATIVE
  Function* = ref object of RootObj
    def: FunctionDefinition
    spaces: int
    case kind: FunctionKind
    of FK_USER:
      steps: seq[FunctionStep]
    of FK_NATIVE:
      native_fn_name: string

proc kind*(fn: Function): FunctionKind = fn.kind
proc def*(fn: Function): FunctionDefinition = fn.def
proc spaces*(fn: Function): int = fn.spaces
proc native_fn_name*(fn: Function): string = fn.native_fn_name
proc steps*(fn: Function): seq[FunctionStep] = fn.steps

proc match_block*(fn: Function): Result[Match, string] =
  case fn.kind:
  of FK_USER:
    case fn.steps[^1].kind:
    of FSK_MATCHER: ok(fn.steps[^1].matcher)
    of FSK_STATEMENT: return err(fmt"No match block found")
  of FK_NATIVE: err(fmt"Native functions do not have statements")

proc `$`*(fn: Function): string =
  let prefix = prefix(fn.spaces)
  let child_prefix = child_prefix(fn.spaces)
  var content: seq[string] = @[prefix & $(fn.def)]
  if fn.kind == FK_USER:
    for step in fn.steps:
      content.add((child_prefix & $(step)))
  return content.join("\n")

proc new_user_function*(def: FunctionDefinition,
    spaces: int): Function =
  Function(kind: FK_USER, def: def, spaces: spaces)

proc new_native_function*(def: FunctionDefinition,
    native_fn_name: string): Function =
  Function(kind: FK_NATIVE, def: def, native_fn_name: native_fn_name, spaces: 4)

# TODO: add duplicate block validation
proc add_step*(fn: Function, step: FunctionStep): Result[void, string] =
  case fn.kind:
  of FK_NATIVE: err(fmt"Native functions do not support steps")
  of FK_USER:
    if fn.steps.len == 0:
      fn.steps.add(step)
      return ok()

    case fn.steps[^1].kind:
    of FSK_MATCHER:
      return err(fmt"Match block must be the last step of a function")
    of FSK_STATEMENT:
      fn.steps.add(step)
      return ok()

proc add_statement*(fn: Function, statement: Statement): Result[void, string] =
  fn.add_step(new_function_step(statement))

proc add_match_block*(fn: Function, matcher: Match): Result[void, string] =
  fn.add_step(new_function_step(matcher))

# TODO: perform final validation
proc close*(fn: Function): Result[void, string] =
  case fn.kind:
  of FK_NATIVE:
    return err(fmt"Native function can not have statements")
  of FK_USER:
    if fn.steps.len == 0:
      return err(fmt"function block must have at least one statement or match block")

    var arg_name_set: HashSet[string]
    for arg_def in fn.def.arg_def_list:
      let name = $(arg_def.name)
      if name in arg_name_set:
        return err(fmt"Parameter {name} is used twice in the function definition")
      arg_name_set.incl(name)
  ok()

proc `==`*(self: Function, other: Function): bool =
  # same name
  if $(self.def.name) != $(other.def.name):
    return false

  # same arity (arg count)
  if self.def.arg_def_list.len != other.def.arg_def_list.len:
    return false

  # same arg types
  for (self_arg_def, other_arg_def) in zip(self.def.arg_def_list,
      other.def.arg_def_list):
    if $(self_arg_def.module) != $(other_arg_def.module):
      return false

  return true

