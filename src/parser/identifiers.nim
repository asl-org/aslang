import strformat, strutils, results, hashes

import ../tokenizer/index as tokenizer
import error

# ============================================================
# Identifier
# ============================================================

type Identifier* = ref object
  value: string
  loc: Location

proc newIdentifier*(value: string, loc: Location): Result[Identifier, ParserError] =
  if value.len > 256:
    err(newParserError(fmt"identifier can be of max length 256", loc))
  elif value.startsWith("__asl"):
    err(newParserError(fmt"identifier can not start with '__asl'", loc))
  else:
    ok(Identifier(value: value, loc: loc))

# NOTE: This function will be used for auto generated identifier names.
proc newGeneratedIdentifier*(counter: int, loc: Location): Identifier =
  Identifier(value: fmt"__asl_arg_{counter}", loc: loc)

proc value*(id: Identifier): string = id.value
proc loc*(id: Identifier): Location = id.loc

proc hash*(id: Identifier): Hash = hash(id.value)
proc `==`*(id: Identifier, other: Identifier): bool = hash(id) == hash(other)

proc asl*(identifier: Identifier): string = identifier.value
