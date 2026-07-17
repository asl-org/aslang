import strformat, strutils, sequtils

import ./tokenizer

import ./identifiers

# ============================================================
# Requires
# ============================================================

type Requires* = ref object
  generics: seq[Identifier]
  loc: Location

proc generics*(r: Requires): seq[Identifier] = r.generics
proc loc*(r: Requires): Location = r.loc

proc newRequires*(generics: seq[Identifier], loc: Location): Requires =
  Requires(generics: generics, loc: loc)

proc asl*(r: Requires): string =
  var content: string
  let inner = r.generics.mapIt(asl(it)).join(", ")
  content.add(fmt"requires({inner})")
  content
