import results

import kind

type
  TokenSpecKind* = enum
    TSK_STATIC, TSK_DYNAMIC
  TokenSpec* = ref object of RootObj
    token_kind*: TokenKind
    case kind*: TokenSpecKind
    of TSK_STATIC:
      value*: string
    of TSK_DYNAMIC:
      matcher*: proc(content: string, index: int): Result[string, string]
