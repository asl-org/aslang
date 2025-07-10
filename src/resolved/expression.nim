import "../blocks"

type ResolvedExpression* = ref object of RootObj
  kind: Token
  value*: Token

proc new_resolved_expression*(kind: Token, value: Token): ResolvedExpression =
  ResolvedExpression(kind: kind, value: value)
