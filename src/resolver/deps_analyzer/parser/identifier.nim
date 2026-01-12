import results, strformat, hashes, strutils

import core
export core

type Identifier* = ref object of RootObj
  name: string
  location: Location

proc new_identifier*(name: string, location: Location): Result[Identifier, string] =
  if name.len == 0:
    return err(fmt"{location} [PE101] [UNREACHABLE] empty string can not be an identifier.")

  if name.len > MAX_IDENTIFIER_LENGTH:
    return err(fmt"{location} [PE102] identifier length `{name.len}` exceeded maximum identifier length of `{MAX_IDENTIFIER_LENGTH}`")
  ok(Identifier(name: name, location: location))

proc new_identifier*(name: string): Result[Identifier, string] =
  new_identifier(name, Location())

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
proc identifier_head_spec*(parser: Parser): Result[Token, string] =
  let maybe_underscore = parser.token_spec_util(TK_UNDERSCORE)
  if maybe_underscore.is_ok:
    maybe_underscore
  else:
    parser.token_spec_util(TK_ALPHABETS)

proc identifier_tail_spec*(parser: Parser): Result[Token, string] =
  let maybe_id_head = parser.expect(identifier_head_spec)
  if maybe_id_head.is_ok:
    maybe_id_head
  else:
    parser.token_spec_util(TK_DIGITS)

proc identifier_spec*(parser: Parser): Result[Identifier, string] =
  let id_head = ? parser.expect(identifier_head_spec)
  var name = id_head.value
  var location = id_head.location

  var maybe_id_tail = parser.expect(identifier_tail_spec)
  while maybe_id_tail.is_ok:
    name.add(maybe_id_tail.get.value)
    maybe_id_tail = parser.expect(identifier_tail_spec)

  new_identifier(name, location)
