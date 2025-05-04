import sequtils, strutils

import symbol

type Production* = ref object of RootObj
  symbols: seq[Symbol]

proc symbols*(prod: Production): seq[Symbol] = prod.symbols
proc new_production*(symbols: seq[Symbol]): Production = Production(
    symbols: symbols)

proc `$`*(prod: Production): string =
  prod.symbols.map(proc(s: Symbol): string = $(s)).join(" ")
