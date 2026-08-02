import strformat, sequtils

import ./tokenizer

import ./identifiers
import ./argtype
import ./argdef

# ============================================================
# FunctionDef (signature only, no body)
# ============================================================

type FunctionAccess* = enum
  ## What a function lookup may see: `faPublic` = public functions
  ## only (the caller's context is outside the defining module),
  ## `faAll` = every function (the caller IS the defining module).
  ## Derived from a TypeContext one layer up (resolver/typecontext).
  faPublic, faAll


type FunctionDef* = ref object
  public: bool
  name: Identifier
  argDefList: ArgumentDefList
  returns: ArgumentType
  loc: Location

proc newFunctionDef*(public: bool, name: Identifier, argDefList: ArgumentDefList, returns: ArgumentType, loc: Location): FunctionDef =
  FunctionDef(public: public, name: name, argDefList: argDefList, returns: returns, loc: loc)

proc loc*(def: FunctionDef): Location = def.loc
proc public*(def: FunctionDef): bool = def.public
proc name*(def: FunctionDef): Identifier = def.name
proc returns*(def: FunctionDef): ArgumentType = def.returns
proc args*(def: FunctionDef): seq[ArgumentDef] = def.argDefList.argDefs
proc arity*(def: FunctionDef): int = def.argDefList.arity

proc asl*(funcDef: FunctionDef): string =
  let prefix = if funcDef.public: "public func" else: "func"
  fmt"{prefix} {funcDef.name.asl}{funcDef.argDefList.asl}: {funcDef.returns.asl}"

proc filter*(defs: seq[FunctionDef], access: FunctionAccess): seq[FunctionDef] =
  case access:
  of faAll: defs
  of faPublic: defs.filterIt(it.public)