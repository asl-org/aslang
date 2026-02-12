import results, sequtils, strformat, tables, sets

import resolver
import module_ref
import arg_def
import file_def
import func_ref

type
  AnalyzedArgumentKind* = enum
    RAK_VARIABLE, RAK_LITERAL
  AnalyzedArgument* = ref object of RootObj
    module_ref: AnalyzedModuleRef
    case kind: AnalyzedArgumentKind
    of RAK_LITERAL: literal: Literal
    of RAK_VARIABLE: variable: Identifier

proc new_analyzed_argument(module_ref: AnalyzedModuleRef,
    variable: Identifier): AnalyzedArgument =
  AnalyzedArgument(kind: RAK_VARIABLE, module_ref: module_ref,
      variable: variable)

proc new_analyzed_argument(module_ref: AnalyzedModuleRef,
    literal: Literal): AnalyzedArgument =
  AnalyzedArgument(kind: RAK_LITERAL, module_ref: module_ref, literal: literal)

proc kind*(arg: AnalyzedArgument): AnalyzedArgumentKind = arg.kind
proc location*(arg: AnalyzedArgument): Location =
  case arg.kind:
  of RAK_LITERAL: arg.literal.location
  of RAK_VARIABLE: arg.variable.location

proc generic_impls*(arg: AnalyzedArgument): Table[ResolvedModule, seq[
    HashSet[AnalyzedImpl]]] =
  arg.module_ref.generic_impls

proc asl*(arg: AnalyzedArgument): string =
  case arg.kind:
  of RAK_LITERAL: arg.literal.asl
  of RAK_VARIABLE: arg.variable.asl

proc analyze*(file_def: AnalyzedFileDefinition, scope: FunctionScope, args: seq[
    Argument], argdefs: seq[AnalyzedArgumentDefinition]): Result[seq[
    AnalyzedArgument], string] =
  var analyzed_args: seq[AnalyzedArgument]
  for (arg, def) in zip(args, argdefs):
    case arg.kind:
    of AK_VARIABLE:
      let variable = ? arg.variable
      let arg_module_ref = ? scope.get(variable)
      if arg_module_ref != def.module_ref:
        return err(fmt"{arg.location} expected `{variable.asl}` to be of type `{def.module_ref.asl}` but found `{arg_module_ref.asl}`")
      analyzed_args.add(new_analyzed_argument(arg_module_ref, variable))
    of AK_LITERAL:
      let literal = ? arg.literal
      ? def.module_ref.module.validate(literal)
      analyzed_args.add(new_analyzed_argument(def.module_ref, literal))
  ok(analyzed_args)
