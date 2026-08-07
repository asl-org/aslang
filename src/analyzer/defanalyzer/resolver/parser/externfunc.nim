import strformat, strutils

import ./tokenizer

import ./identifiers
import ./funcdef

# ============================================================
# ExternFunction
# ============================================================

type ExternFunction* = ref object
  ffi: string
  def: FunctionDef
  loc: Location

proc name*(fn: ExternFunction): Identifier = fn.def.name
proc arity*(fn: ExternFunction): int = fn.def.arity
proc def*(fn: ExternFunction): FunctionDef = fn.def
proc loc*(fn: ExternFunction): Location = fn.loc

proc newExternFunction*(ffi: string, def: FunctionDef, loc: Location): ExternFunction =
  ExternFunction(ffi: ffi, def: def, loc: loc)

proc asl*(fn: ExternFunction, level: int, indentWidth: uint32): seq[string] =
  let indent = " ".repeat(level * indentWidth.int)
  return @[
    fmt"{indent}@extern(""{fn.ffi}"")",
    fmt"{indent}{asl(fn.def)}",
  ]
