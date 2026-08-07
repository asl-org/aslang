## ResolvedExternFunction — a function whose body lives in FFI-land, wrapping
## a resolved signature.

import ./parser
import funcdef

type ResolvedExternFunction* = ref object
  parsed: ExternFunction
  def: ResolvedFunctionDef

proc newResolvedExternFunction*(parsed: ExternFunction,
    def: ResolvedFunctionDef): ResolvedExternFunction =
  ResolvedExternFunction(parsed: parsed, def: def)

proc loc*(function: ResolvedExternFunction): Location = function.def.loc
proc name*(function: ResolvedExternFunction): Identifier = function.def.name
proc arity*(function: ResolvedExternFunction): int = function.def.arity
proc def*(function: ResolvedExternFunction): ResolvedFunctionDef = function.def
