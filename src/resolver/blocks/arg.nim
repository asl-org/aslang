import tables, sets, strformat, sequtils, hashes
import function_ref

type ResolvedGeneric* = ref object of RootObj
  module: UserModule
  generic: Generic

proc new_resolved_generic*(module: UserModule,
    generic: Generic): ResolvedGeneric =
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

# TODO: Cleanup after scope contains resolved values
proc arg_type*(arg_type: ResolvedArgumentType): ArgumentType =
  case arg_type.kind:
  of RATK_DEFAULT:
    let children = arg_type.children.map_it(it.arg_type)
    new_argument_type(arg_type.parent.name, children)
  of RATK_GENERIC:
    new_argument_type(arg_type.generic.generic.name)

proc c*(arg_type: ResolvedArgumentType): string =
  case arg_type.kind:
  of RATK_DEFAULT:
    case arg_type.parent.kind:
    of MK_BUILTIN: $(arg_type.parent.name)
    else: "Pointer"
  of RATK_GENERIC: "Pointer"

type ResolvedArgumentDefinition* = ref object of RootObj
  name*: Token
  arg_type*: ResolvedArgumentType

proc new_resolved_argument_definition*(name: Token,
    arg_type: ResolvedArgumentType): ResolvedArgumentDefinition =
  ResolvedArgumentDefinition(name: name, arg_type: arg_type)

proc c*(arg_def: ResolvedArgumentDefinition): string =
  fmt"{arg_def.arg_type.c} {arg_def.name}"

# TODO: Cleanup after scope contains resolved values
proc arg_def*(arg_def: ResolvedArgumentDefinition): ArgumentDefinition =
  new_argument_definition(arg_def.arg_type.arg_type, arg_def.name)

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
    case kind*: ResolvedVariableKind
    of RVK_DEFAULT:
      arg_def*: ResolvedArgumentDefinition
    of RVK_GENERIC:
      variable: ResolvedVariable
      generic*: Token
      func_refs*: HashSet[ResolvedFunctionRef]

proc new_resolved_variable*(arg_def: ResolvedArgumentDefinition): ResolvedVariable =
  ResolvedVariable(kind: RVK_DEFAULT, arg_def: arg_def)

proc new_resolved_variable*(resolved_var: ResolvedVariable,
    generic: Token, func_refs: HashSet[ResolvedFunctionRef]): ResolvedVariable =
  ResolvedVariable(kind: RVK_GENERIC, variable: resolved_var, generic: generic,
      func_refs: func_refs)

proc function_refs*(variable: ResolvedVariable): HashSet[
    ResolvedFunctionRef] =
  case variable.kind:
  of RVK_DEFAULT: init_hashset[ResolvedFunctionRef]()
  of RVK_GENERIC: variable.func_refs

proc resolved_typ*(variable: ResolvedVariable): ResolvedArgumentType =
  case variable.kind:
  of RVK_DEFAULT: variable.arg_def.arg_type
  of RVK_GENERIC: variable.variable.arg_def.arg_type

proc typ*(variable: ResolvedVariable): ArgumentType =
  variable.resolved_typ.arg_type

proc name*(variable: ResolvedVariable): Token =
  case variable.kind:
  of RVK_DEFAULT: variable.arg_def.name
  of RVK_GENERIC: variable.variable.arg_def.name

proc generic_impls*(variable: ResolvedVariable): Table[string, HashSet[string]] =
  var impls: Table[string, HashSet[string]]
  case variable.kind:
  of RVK_DEFAULT: discard
  of RVK_GENERIC:
    impls[$(variable.generic)] = init_hashset[string]()
    impls[$(variable.generic)].incl($(variable.typ))
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

proc resolved_return_type*(arg: ResolvedArgument): ResolvedArgumentType =
  case arg.kind:
  of RAK_LITERAL: new_resolved_argument_type(new_module(arg.literal.module))
  of RAK_VARIABLE: arg.variable.resolved_typ

proc c*(arg: ResolvedArgument): string = $(arg.value)

proc new_resolved_argument*(literal: ResolvedLiteral): ResolvedArgument =
  ResolvedArgument(kind: RAK_LITERAL, literal: literal)

proc new_resolved_argument*(variable: ResolvedVariable): ResolvedArgument =
  ResolvedArgument(kind: RAK_VARIABLE, variable: variable)
