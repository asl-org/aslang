import "../blocks"

type ResolvedArgument* = ref object of RootObj
  kind: Token
  value*: Token

proc new_resolved_argument*(kind: Token, value: Token): ResolvedArgument =
  ResolvedArgument(kind: kind, value: value)

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

proc typ*(variable: ResolvedVariable): Token = variable.arg_def.arg_type
proc name*(variable: ResolvedVariable): Token = variable.arg_def.arg_name
