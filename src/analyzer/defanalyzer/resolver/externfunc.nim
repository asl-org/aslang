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

proc parsed*(function: ResolvedExternFunction): ExternFunction = function.parsed
proc def*(function: ResolvedExternFunction): ResolvedFunctionDef = function.def
proc ffi*(function: ResolvedExternFunction): string = function.parsed.ffi
proc loc*(function: ResolvedExternFunction): Location = function.def.loc
