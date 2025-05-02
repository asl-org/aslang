import strformat, hashes

import "../location"
import "../identifier/struct"
import "../atom/struct"

type KeywordArgument* = ref object of RootObj
  name: Identifier
  value: Atom
  location: Location

proc `$`*(keyword_argument: KeywordArgument): string =
  fmt"{keyword_argument.name}: {keyword_argument.value}"

proc new_keyword_argument*(name: Identifier, value: Atom,
    location: Location): KeywordArgument =
  KeywordArgument(name: name, value: value, location: location)

proc hash*(keyword_argument: KeywordArgument): Hash =
  hash(keyword_argument.name) !& hash(keyword_argument.value)
