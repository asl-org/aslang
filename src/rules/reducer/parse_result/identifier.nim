import location

type Identifier* = ref object of RootObj
  name: string
  location: Location

proc `$`*(identifier: Identifier): string = identifier.name
proc name*(identifier: Identifier): string = identifier.name
proc location*(identifier: Identifier): Location = identifier.location

proc new_identifier*(name: string, location: Location): Identifier =
  Identifier(name: name, location: location)
