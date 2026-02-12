import results, strformat, hashes, strutils

import core

type Identifier* = ref object of RootObj
  name: string
  location: Location

proc new_identifier*(name: string, location: Location): Result[Identifier, core.Error] =
  if name.len == 0:
    return err(err_parser_empty_identifier(location))

  if name.len > MAX_IDENTIFIER_LENGTH:
    return err(err_parser_identifier_too_long(location, name.len))
  ok(Identifier(name: name, location: location))

proc new_identifier*(name: string): Identifier =
  Identifier(name: name, location: new_location(name))

proc new_identifier*(location: Location): Identifier =
  let name = fmt"__asl_arg_{location.hash.to_hex}"
  Identifier(name: name, location: location)

proc location*(identifier: Identifier): Location =
  identifier.location

proc asl*(identifier: Identifier): string =
  identifier.name

proc hash*(identifier: Identifier): Hash =
  hash(identifier.name)

proc `==`*(a: Identifier, b: Identifier): bool =
  a.hash == b.hash

# identifier specs
proc identifier_head_spec*(parser: Parser): Result[Token, core.Error] =
  parser.first_of([underscore_spec, alphabets_spec])

proc identifier_tail_spec*(parser: Parser): Result[Token, core.Error] =
  parser.first_of([identifier_head_spec, digits_spec])

proc identifier_spec*(parser: Parser): Result[Identifier, core.Error] =
  let id_head = ? parser.expect(identifier_head_spec)
  var name = id_head.value
  var location = id_head.location

  var maybe_id_tail = parser.expect(identifier_tail_spec)
  while maybe_id_tail.is_ok:
    name.add(maybe_id_tail.get.value)
    maybe_id_tail = parser.expect(identifier_tail_spec)

  new_identifier(name, location)
