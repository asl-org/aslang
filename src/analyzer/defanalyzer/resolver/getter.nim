## ResolvedGetter — a resolved dotted access (`source.property`). Leaf
## node in the body cluster: nothing above it in the recursion cycle,
## so it lives on its own.

import parser

type ResolvedGetter* = ref object
  parsed: Getter

proc newResolvedGetter*(parsed: Getter): ResolvedGetter =
  ResolvedGetter(parsed: parsed)

proc source*(getter: ResolvedGetter): Identifier = getter.parsed.source
proc property*(getter: ResolvedGetter): Identifier = getter.parsed.property
proc loc*(getter: ResolvedGetter): Location = getter.parsed.loc
