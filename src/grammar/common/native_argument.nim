import hashes

import "../location"
import identifier, native_literal

type
  NativeArgumentKind* = enum
    AK_LITERAL, AK_IDENTIFIER
  NativeArgument* = ref object of RootObj
    location: Location
    case kind: NativeArgumentKind
    of AK_LITERAL: literal: NativeLiteral
    of AK_IDENTIFIER: identifier: Identifier

proc `$`*(argument: NativeArgument): string =
  case argument.kind:
  of AK_LITERAL: $(argument.literal)
  of AK_IDENTIFIER: $(argument.identifier)

proc kind*(arg: NativeArgument): NativeArgumentKind = arg.kind
proc literal*(arg: NativeArgument): NativeLiteral = arg.literal
proc identifier*(arg: NativeArgument): Identifier = arg.identifier

proc new_native_literal_argument*(literal: NativeLiteral,
    location: Location): NativeArgument =
  NativeArgument(kind: AK_LITERAL, literal: literal, location: location)

proc new_native_identifier_argument*(identifier: Identifier,
    location: Location): NativeArgument =
  NativeArgument(kind: AK_IDENTIFIER, identifier: identifier,
      location: location)

proc hash*(argument: NativeArgument): Hash =
  let sub_hash =
    case argument.kind:
    of AK_IDENTIFIER: hash(argument.literal)
    of AK_LITERAL: hash(argument.identifier)
  hash(argument.kind) !& sub_hash
