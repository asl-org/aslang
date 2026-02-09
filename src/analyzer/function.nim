import results, strformat, tables, strutils, sets, options

import resolver
import module_ref
import arg_def
import func_def
import module_def
import file_def
import func_ref
import expression

type AnalyzedUserFunction* = ref object of RootObj
  def: AnalyzedFunctionDefinition
  steps: seq[AnalyzedStatement]

proc new_analyzed_user_function(def: AnalyzedFunctionDefinition, steps: seq[
    AnalyzedStatement]): AnalyzedUserFunction =
  AnalyzedUserFunction(def: def, steps: steps)

proc statements(function: AnalyzedUserFunction): seq[AnalyzedStatement] =
  function.steps

proc generic_impls*(function: AnalyzedUserFunction): Table[ResolvedModule,
    seq[HashSet[AnalyzedImpl]]] =
  var impl_set: Table[ResolvedModule, seq[HashSet[AnalyzedImpl]]]
  impl_set = impl_set.merge(function.def.generic_impls)
  for step in function.steps: impl_set = impl_set.merge(step.generic_impls)
  return impl_set

proc asl*(function: AnalyzedUserFunction, indent: string): seq[string] =
  var lines = @[function.def.asl]
  for statement in function.steps:
    for line in statement.asl(indent):
      lines.add(indent & line)
  return lines

proc c*(function: AnalyzedUserFunction): seq[string] =
  var lines: seq[string]
  lines.add(function.def.h.replace(";", ""))
  lines.add("{")
  for statement in function.statements:
    lines.add(statement.c)
  let last_arg = function.statements[^1].arg.name.asl
  lines.add(fmt"return {last_arg};")
  lines.add("}")
  return lines

proc analyze*(file_def: AnalyzedFileDefinition,
    function: ResolvedUserFunction,
    module_def: Option[AnalyzedModuleDefinition] = none[AnalyzedModuleDefinition]()): Result[
    AnalyzedUserFunction, string] =
  var scope = new_function_scope()
  let analyzed_function_def = if module_def.is_some:
    ? module_def.get.find_function_def(function.def)
  else:
    ? file_def.find_function_def(function.def)
  for arg in analyzed_function_def.args: scope = ? scope.set(arg)

  var analyzed_steps: seq[AnalyzedStatement]
  for step in function.steps:
    let analyzed_function_step = ? analyze(file_def, scope, step, module_def)
    analyzed_steps.add(analyzed_function_step)
    scope = ? scope.set(analyzed_function_step.arg)
  ok(new_analyzed_user_function(analyzed_function_def, analyzed_steps))

proc analyze*(file_def: AnalyzedFileDefinition,
    function: ResolvedFunction): Result[AnalyzedUserFunction, string] =
  case function.kind:
  of RFK_USER: file_def.analyze(function.user)
  of RFK_EXTERN: err("UNREACHABLE")

type
  AnalyzedFunctionKind = enum
    AFK_USER, AFK_EXTERN
  AnalyzedFunction* = ref object of RootObj
    case kind: AnalyzedFunctionKind
    of AFK_USER: user: AnalyzedUserFunction
    of AFK_EXTERN:
      def: AnalyzedFunctionDefinition
      extern: ResolvedExternFunction

proc new_analyzed_function*(user: AnalyzedUserFunction): AnalyzedFunction =
  AnalyzedFunction(kind: AFK_USER, user: user)

proc new_analyzed_function*(def: AnalyzedFunctionDefinition,
    extern: ResolvedExternFunction): AnalyzedFunction =
  AnalyzedFunction(kind: AFK_EXTERN, def: def, extern: extern)

proc generic_impls*(function: AnalyzedFunction): Table[ResolvedModule, seq[
    HashSet[AnalyzedImpl]]] =
  case function.kind:
  of AFK_USER: function.user.generic_impls
  of AFK_EXTERN: init_table[ResolvedModule, seq[HashSet[AnalyzedImpl]]]()

proc asl*(function: AnalyzedFunction, indent: string): seq[string] =
  case function.kind:
  of AFK_EXTERN: @[]
  of AFK_USER: function.user.asl(indent)

proc c*(function: AnalyzedFunction): seq[string] =
  case function.kind:
  of AFK_EXTERN: @[]
  of AFK_USER: function.user.c
