import sequtils, strutils, hashes

import "../location"
import keyword_argument

type StructLiteral* = ref object of RootObj
  kwargs: seq[KeywordArgument]
  location: Location

proc `$`*(literal: StructLiteral): string =
  let kwargs = literal.kwargs.map(proc(f: KeywordArgument): string = $(f)).join(", ")
  "{ " & kwargs & " }"

proc new_struct_literal*(kwargs: seq[KeywordArgument],
    location: Location): StructLiteral =
  StructLiteral(kwargs: kwargs, location: location)

proc hash*(struct: StructLiteral): Hash =
  var res: Hash
  for kwarg in struct.kwargs:
    res = res !& hash(kwarg)
  return res
