import strformat, hashes

import location, identifier, native_argument

type KeywordArgument* = ref object of RootObj
  name: Identifier
  value: NativeArgument
  location: Location

proc `$`*(kwarg: KeywordArgument): string =
  fmt"{kwarg.name}: {kwarg.value}"

proc new_kwarg*(name: Identifier, value: NativeArgument,
    location: Location): KeywordArgument =
  KeywordArgument(name: name, value: value, location: location)

proc hash*(kwarg: KeywordArgument): Hash =
  hash(kwarg.name) !& hash(kwarg.value)
