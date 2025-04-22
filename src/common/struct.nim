import sequtils, strutils, hashes

import location, keyword_argument

type Struct* = ref object of RootObj
  kwargs: seq[KeywordArgument]
  location: Location

proc `$`*(literal: Struct): string =
  let kwargs = literal.kwargs.map(proc(f: KeywordArgument): string = $(f)).join(", ")
  "{ " & kwargs & " }"

proc new_struct*(kwargs: seq[KeywordArgument], location: Location): Struct =
  Struct(kwargs: kwargs, location: location)

proc hash*(struct: Struct): Hash =
  var res: Hash
  for kwarg in struct.kwargs:
    res = res !& hash(kwarg)
  return res
