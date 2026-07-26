import strformat

import ./tokenizer

import ./identifiers

# ============================================================
# Getter
# ============================================================

type Getter* = ref object
  source: Identifier
  property: Identifier
  loc: Location

proc newGetter*(source: Identifier, property: Identifier, loc: Location): Getter =
  Getter(source: source, property: property, loc: loc)

proc source*(g: Getter): Identifier = g.source
proc property*(g: Getter): Identifier = g.property
proc loc*(g: Getter): Location = g.loc

proc asl*(getter: Getter): string =
  fmt"{asl(getter.source)}.{asl(getter.property)}"
