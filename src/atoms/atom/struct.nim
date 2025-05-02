import hashes

import "../location"
import "../identifier/struct"
import "../numeric_literal/struct"

type
  AtomKind* = enum
    AK_LITERAL, AK_IDENTIFIER
  Atom* = ref object of RootObj
    case kind: AtomKind
    of AK_LITERAL: literal: NumericLiteral
    of AK_IDENTIFIER: identifier: Identifier

proc kind*(atom: Atom): AtomKind = atom.kind
proc literal*(atom: Atom): NumericLiteral = atom.literal
proc identifier*(atom: Atom): Identifier = atom.identifier

proc new_native_literal_argument*(literal: NumericLiteral,
    location: Location): Atom =
  Atom(kind: AK_LITERAL, literal: literal)

proc new_native_identifier_argument*(identifier: Identifier,
    location: Location): Atom =
  Atom(kind: AK_IDENTIFIER, identifier: identifier)

proc `$`*(atom: Atom): string =
  case atom.kind:
  of AK_LITERAL: $(atom.literal)
  of AK_IDENTIFIER: $(atom.identifier)

proc hash*(argument: Atom): Hash =
  let sub_hash =
    case argument.kind:
    of AK_IDENTIFIER: hash(argument.literal)
    of AK_LITERAL: hash(argument.identifier)
  hash(argument.kind) !& sub_hash
