import hashes

import "../location"

type StringLiteral* = ref object of RootObj
  value: string
  location: Location

proc `$`*(string_literal: StringLiteral): string =
  "\"" & string_literal.value & "\""

proc new_string_literal*(value: string, location: Location): StringLiteral =
  StringLiteral(value: value, location: location)

proc hash*(string_literal: StringLiteral): Hash =
  hash(string_literal.value)
