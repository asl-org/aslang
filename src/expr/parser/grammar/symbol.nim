type
  SymbolKind* = enum
    SK_EXACT_ONE, SK_ANY, SK_AT_LEAST_ONE, SK_AT_MOST_ONE

  Symbol* = ref object of RootObj
    name: string
    kind: SymbolKind

proc name*(symbol: Symbol): string = symbol.name
proc kind*(symbol: Symbol): SymbolKind = symbol.kind

proc new_symbol_any*(name: string): Symbol = Symbol(kind: SK_ANY, name: name)
proc new_symbol_at_most_one*(name: string): Symbol = Symbol(
    kind: SK_AT_MOST_ONE, name: name)
proc new_symbol_exact_one*(name: string): Symbol = Symbol(kind: SK_EXACT_ONE, name: name)
proc new_symbol_at_least_one*(name: string): Symbol = Symbol(
    kind: SK_AT_LEAST_ONE, name: name)

proc parse*(symbol: string): Symbol =
  case symbol[^1]:
  of '*': new_symbol_any(symbol[0..<(symbol.len - 1)])
  of '?': new_symbol_at_most_one(symbol[0..<(symbol.len - 1)])
  of '+': new_symbol_at_least_one(symbol[0..<(symbol.len - 1)])
  else: new_symbol_exact_one(symbol)

proc `$`*(symbol: Symbol): string =
  case symbol.kind:
  of SK_ANY: symbol.name & "*"
  of SK_AT_MOST_ONE: symbol.name & "?"
  of SK_EXACT_ONE: symbol.name
  of SK_AT_LEAST_ONE: symbol.name & "+"
