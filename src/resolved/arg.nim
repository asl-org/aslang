import "../blocks"

type
  ResolvedLiteralKind* = enum
    RLK_INTEGER, RLK_FLOAT
  ResolvedLiteral* = ref object of RootObj
    kind*: ResolvedLiteralKind
    typ*: Token
    value*: Token

proc new_resolved_integer_literal*(typ: Token, value: Token): ResolvedLiteral =
  ResolvedLiteral(kind: RLK_INTEGER, typ: typ, value: value)

proc new_resolved_float_literal*(typ: Token, value: Token): ResolvedLiteral =
  ResolvedLiteral(kind: RLK_FLOAT, typ: typ, value: value)

type ResolvedVariable* = ref object of RootObj
  arg_def: ArgumentDefinition

proc new_resolved_variable*(arg_def: ArgumentDefinition): ResolvedVariable =
  ResolvedVariable(arg_def: arg_def)

proc typ*(variable: ResolvedVariable): Token = variable.arg_def.typ
proc name*(variable: ResolvedVariable): Token = variable.arg_def.name

type
  ResolvedArgumentKind = enum
    RAK_LITERAL, RAK_VARIABLE
  ResolvedArgument* = ref object of RootObj
    case kind: ResolvedArgumentKind
    of RAK_LITERAL: literal: ResolvedLiteral
    of RAK_VARIABLE: variable: ResolvedVariable

proc value*(arg: ResolvedArgument): Token =
  case arg.kind:
  of RAK_LITERAL: arg.literal.value
  of RAK_VARIABLE: arg.variable.name

proc new_resolved_argument*(literal: ResolvedLiteral): ResolvedArgument =
  ResolvedArgument(kind: RAK_LITERAL, literal: literal)

proc new_resolved_argument*(variable: ResolvedVariable): ResolvedArgument =
  ResolvedArgument(kind: RAK_VARIABLE, variable: variable)
