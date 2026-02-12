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
  var errors: seq[core.Error]

  let maybe_underscore = parser.token_spec_util(TK_UNDERSCORE)
  if maybe_underscore.is_ok: return maybe_underscore
  else: errors.add(maybe_underscore.error)

  let maybe_alphabet = parser.token_spec_util(TK_ALPHABETS)
  if maybe_alphabet.is_ok: return maybe_alphabet
  else: errors.add(maybe_alphabet.error)

  err(errors.max())

proc identifier_tail_spec*(parser: Parser): Result[Token, core.Error] =
  var errors: seq[core.Error]

  let maybe_id_head = parser.expect(identifier_head_spec)
  if maybe_id_head.is_ok: return maybe_id_head
  else: errors.add(maybe_id_head.error)

  let maybe_digits = parser.token_spec_util(TK_DIGITS)
  if maybe_digits.is_ok: return maybe_digits
  else: errors.add(maybe_digits.error)

  err(errors.max())

proc identifier_spec*(parser: Parser): Result[Identifier, core.Error] =
  let id_head = ? parser.expect(identifier_head_spec)
  var name = id_head.value
  var location = id_head.location

  var maybe_id_tail = parser.expect(identifier_tail_spec)
  while maybe_id_tail.is_ok:
    name.add(maybe_id_tail.get.value)
    maybe_id_tail = parser.expect(identifier_tail_spec)

  new_identifier(name, location)
