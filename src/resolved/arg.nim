import tables, sets

import "../blocks"
import function_ref

type ResolvedGeneric* = ref object of RootObj
  module: Module
  generic: Generic

proc new_resolved_generic*(module: Module, generic: Generic): ResolvedGeneric =
  ResolvedGeneric(module: module, generic: generic)

type
  ResolvedArgumentTypeKind* = enum
    RATK_DEFAULT, RATK_GENERIC
  ResolvedArgumentType* = ref object of RootObj
    case kind: ResolvedArgumentTypeKind
    of RATK_DEFAULT:
      parent: Module
      children: seq[ResolvedArgumentType]
    of RATK_GENERIC:
      generic: ResolvedGeneric

proc new_resolved_argument_type*(parent: Module): ResolvedArgumentType =
  ResolvedArgumentType(kind: RATK_DEFAULT, parent: parent)

proc new_resolved_argument_type*(parent: Module, children: seq[
    ResolvedArgumentType]): ResolvedArgumentType =
  ResolvedArgumentType(kind: RATK_DEFAULT, parent: parent, children: children)

proc new_resolved_argument_type*(generic: ResolvedGeneric): ResolvedArgumentType =
  ResolvedArgumentType(kind: RATK_GENERIC, generic: generic)

type ResolvedArgumentDefinition* = ref object of RootObj
  name: Token
  arg_type: ResolvedArgumentType

proc new_resolved_argument_definition*(name: Token,
    arg_type: ResolvedArgumentType): ResolvedArgumentDefinition =
  ResolvedArgumentDefinition(name: name, arg_type: arg_type)

type
  ResolvedLiteralKind* = enum
    RLK_INTEGER, RLK_FLOAT
  ResolvedLiteral* = ref object of RootObj
    kind*: ResolvedLiteralKind
    module*: BuiltinModule
    value*: Token

proc new_resolved_integer_literal*(module: BuiltinModule,
    value: Token): ResolvedLiteral =
  ResolvedLiteral(kind: RLK_INTEGER, module: module, value: value)

proc new_resolved_float_literal*(module: BuiltinModule,
    value: Token): ResolvedLiteral =
  ResolvedLiteral(kind: RLK_FLOAT, module: module, value: value)


type
  ResolvedVariableKind* = enum
    RVK_DEFAULT, RVK_GENERIC
  ResolvedVariable* = ref object of RootObj
    arg_def*: ArgumentDefinition
    case kind*: ResolvedVariableKind
    of RVK_DEFAULT: discard
    of RVK_GENERIC:
      generic*: Token
      func_refs*: HashSet[ResolvedFunctionRef]

proc new_resolved_variable*(arg_def: ArgumentDefinition): ResolvedVariable =
  ResolvedVariable(kind: RVK_DEFAULT, arg_def: arg_def)

proc new_resolved_variable*(resolved_var: ResolvedVariable,
    generic: Token, func_refs: HashSet[
        ResolvedFunctionRef]): ResolvedVariable =
  ResolvedVariable(kind: RVK_GENERIC, arg_def: resolved_var.arg_def,
      generic: generic, func_refs: func_refs)

proc function_refs*(resolved_var: ResolvedVariable): HashSet[
    ResolvedFunctionRef] =
  case resolved_var.kind:
  of RVK_DEFAULT: init_hashset[ResolvedFunctionRef]()
  of RVK_GENERIC: resolved_var.func_refs

proc typ*(variable: ResolvedVariable): ArgumentType = variable.arg_def.typ
proc name*(variable: ResolvedVariable): Token = variable.arg_def.name

proc generic_impls*(variable: ResolvedVariable): Table[string, HashSet[string]] =
  var impls: Table[string, HashSet[string]]
  case variable.kind:
  of RVK_GENERIC:
    impls[$(variable.generic)] = init_hashset[string]()
    impls[$(variable.generic)].incl($(variable.typ))
  of RVK_DEFAULT:
    discard
  return impls

type
  ResolvedArgumentKind* = enum
    RAK_LITERAL, RAK_VARIABLE
  ResolvedArgument* = ref object of RootObj
    case kind*: ResolvedArgumentKind
    of RAK_LITERAL: literal*: ResolvedLiteral
    of RAK_VARIABLE: variable*: ResolvedVariable

proc function_refs*(arg: ResolvedArgument): HashSet[ResolvedFunctionRef] =
  case arg.kind:
  of RAK_VARIABLE: arg.variable.function_refs
  else: init_hashset[ResolvedFunctionRef]()

proc generic_impls*(arg: ResolvedArgument): Table[string, HashSet[string]] =
  case arg.kind:
  of RAK_VARIABLE: arg.variable.generic_impls
  else: init_table[string, HashSet[string]]()

proc value*(arg: ResolvedArgument): Token =
  case arg.kind:
  of RAK_LITERAL: arg.literal.value
  of RAK_VARIABLE: arg.variable.name

proc return_type*(arg: ResolvedArgument): ArgumentType =
  case arg.kind:
  of RAK_LITERAL: new_argument_type(arg.literal.module.name)
  of RAK_VARIABLE: arg.variable.typ

proc c*(arg: ResolvedArgument): string = $(arg.value)

proc new_resolved_argument*(literal: ResolvedLiteral): ResolvedArgument =
  ResolvedArgument(kind: RAK_LITERAL, literal: literal)

proc new_resolved_argument*(variable: ResolvedVariable): ResolvedArgument =
  ResolvedArgument(kind: RAK_VARIABLE, variable: variable)
