## Shared name→position index builder. Struct/variant field indexes and
## union variant indexes — on both the resolved and analyzed twins — are
## all the same first-seen-position table over a seq of things that have
## a `name: Identifier`. Duplicates are a compiler bug (the parser and
## resolver reject them upstream), asserted here.

import tables

import ../parser/main as parser

proc indexByName*[T](items: seq[T]): Table[Identifier, int] =
  mixin name
  for id, item in items:
    assert(item.name notin result, "[BUG] duplicate name in index — parser/resolver reject duplicates upstream")
    result[item.name] = id
