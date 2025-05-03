import hashes

import "../location"
import identifier, numeric_literal

type
  ArgumentKind* = enum
    AK_LITERAL, AK_IDENTIFIER
  Argument* = ref object of RootObj
    location: Location
    case kind: ArgumentKind
    of AK_LITERAL: literal: NumericLiteral
    of AK_IDENTIFIER: identifier: Identifier

proc `$`*(argument: Argument): string =
  case argument.kind:
  of AK_LITERAL: $(argument.literal)
  of AK_IDENTIFIER: $(argument.identifier)

proc kind*(arg: Argument): ArgumentKind = arg.kind
proc literal*(arg: Argument): NumericLiteral = arg.literal
proc identifier*(arg: Argument): Identifier = arg.identifier

proc new_literal_argument*(literal: NumericLiteral,
    location: Location): Argument =
  Argument(kind: AK_LITERAL, literal: literal, location: location)

proc new_identifier_argument*(identifier: Identifier,
    location: Location): Argument =
  Argument(kind: AK_IDENTIFIER, identifier: identifier,
      location: location)

proc hash*(argument: Argument): Hash =
  let sub_hash =
    case argument.kind:
    of AK_IDENTIFIER: hash(argument.literal)
    of AK_LITERAL: hash(argument.identifier)
  hash(argument.kind) !& sub_hash
