import "../blocks"

type ResolvedArgument* = ref object of RootObj
  kind: Token
  value*: Token

proc new_resolved_argument*(kind: Token, value: Token): ResolvedArgument =
  ResolvedArgument(kind: kind, value: value)
