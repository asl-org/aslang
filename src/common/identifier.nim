import hashes

import location

type Identifier* = ref object of RootObj
  name: string
  location: Location

proc `$`*(identifier: Identifier): string = identifier.name
proc `==`*(self: Identifier, other: Identifier): bool = self.name == other.name

proc new_identifier*(name: string): Identifier =
  Identifier(name: name)

proc new_identifier*(name: string, location: Location): Identifier =
  Identifier(name: name, location: location)

proc hash*(identifier: Identifier): Hash = hash(identifier.name)
