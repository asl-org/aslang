## Phase-A function cluster — `AnalyzedFunctionDef` (a resolver function
## definition + its fully-analyzed args/return, the phase-B overload &
## body-typing input) plus the function wrappers: `AnalyzedDefExtern-
## Function` / `AnalyzedDefUserFunction` pair the resolver function with
## its `AnalyzedFunctionDef`, and the tagged `AnalyzedDefFunction`
## (adfkExtern / adfkUser) gives `AnalyzedDefModule.functions` one shape
## with uniform `def` / `name` / `arity` accessors.

import strformat, strutils, sequtils

import resolver
import argtype
import statement

# ---- AnalyzedFunctionDef ----
# A resolver function definition paired with its fully-analyzed argument
# definitions and return type. Produced by phase-A when walking a
# module's/generic's function list; consumed by phase-B overload
# resolution + body-typing without re-analysis.

type AnalyzedFunctionDef* = ref object
  resolved: ResolvedFunctionDef
  args: seq[AnalyzedArgumentDef]
  returns: AnalyzedArgumentType

proc newAnalyzedFunctionDef*(resolved: ResolvedFunctionDef,
    args: seq[AnalyzedArgumentDef],
    returns: AnalyzedArgumentType): AnalyzedFunctionDef =
  AnalyzedFunctionDef(resolved: resolved, args: args, returns: returns)

proc resolved*(f: AnalyzedFunctionDef): ResolvedFunctionDef = f.resolved
proc public*(f: AnalyzedFunctionDef): bool = f.resolved.public
proc name*(f: AnalyzedFunctionDef): Identifier = f.resolved.name
proc loc*(f: AnalyzedFunctionDef): Location = f.resolved.loc
proc arity*(f: AnalyzedFunctionDef): int = f.args.len
proc args*(f: AnalyzedFunctionDef): seq[AnalyzedArgumentDef] = f.args
proc returns*(f: AnalyzedFunctionDef): AnalyzedArgumentType = f.returns

proc asl*(f: AnalyzedFunctionDef): string =
  var args: seq[string]
  for arg in f.args:
    args.add(arg.asl)
  "func " & f.name.asl & "(" & args.join(", ") & "): " & f.returns.asl

proc filter*(defs: seq[AnalyzedFunctionDef], access: FunctionAccess): seq[AnalyzedFunctionDef] =
  case access:
  of faAll: defs
  of faPublic: defs.filterIt(it.public)

# ---- function wrappers ----

type AnalyzedDefExternFunction* = ref object
  resolved: ResolvedExternFunction
  def: AnalyzedFunctionDef

proc newAnalyzedDefExternFunction*(resolved: ResolvedExternFunction, def: AnalyzedFunctionDef): AnalyzedDefExternFunction =
  AnalyzedDefExternFunction(resolved: resolved, def: def)

proc name*(function: AnalyzedDefExternFunction): Identifier = function.resolved.name
proc arity*(function: AnalyzedDefExternFunction): int = function.resolved.arity

type AnalyzedDefUserFunction* = ref object
  resolved: ResolvedUserFunction
  def: AnalyzedFunctionDef
  statements: seq[AnalyzedDefStatement]

proc newAnalyzedDefUserFunction*(resolved: ResolvedUserFunction, def: AnalyzedFunctionDef, statements: seq[AnalyzedDefStatement]): AnalyzedDefUserFunction =
  AnalyzedDefUserFunction(resolved: resolved, def: def, statements: statements)

proc loc*(function: AnalyzedDefUserFunction): Location = function.resolved.loc
proc name*(function: AnalyzedDefUserFunction): Identifier = function.resolved.name
proc arity*(function: AnalyzedDefUserFunction): int = function.resolved.arity
proc def*(function: AnalyzedDefUserFunction): AnalyzedFunctionDef = function.def
proc statements*(function: AnalyzedDefUserFunction): seq[AnalyzedDefStatement] = function.statements

type
  AnalyzedDefFunctionKind* = enum
    adfkExtern, adfkUser
  AnalyzedDefFunction* = ref object
    case kind: AnalyzedDefFunctionKind
    of adfkExtern: extern: AnalyzedDefExternFunction
    of adfkUser: user: AnalyzedDefUserFunction

proc newAnalyzedDefFunction*(extern: AnalyzedDefExternFunction): AnalyzedDefFunction =
  AnalyzedDefFunction(kind: adfkExtern, extern: extern)

proc newAnalyzedDefFunction*(user: AnalyzedDefUserFunction): AnalyzedDefFunction =
  AnalyzedDefFunction(kind: adfkUser, user: user)

proc kind*(function: AnalyzedDefFunction): AnalyzedDefFunctionKind = function.kind
proc extern*(function: AnalyzedDefFunction): AnalyzedDefExternFunction =
  assert function.kind == adfkExtern,
    fmt"AnalyzedDefFunction.extern accessed but kind is {function.kind}"
  function.extern
proc user*(function: AnalyzedDefFunction): AnalyzedDefUserFunction =
  assert function.kind == adfkUser,
    fmt"AnalyzedDefFunction.user accessed but kind is {function.kind}"
  function.user

proc def*(function: AnalyzedDefFunction): AnalyzedFunctionDef =
  case function.kind:
  of adfkExtern: function.extern.def
  of adfkUser: function.user.def

proc name*(function: AnalyzedDefFunction): Identifier =
  case function.kind:
  of adfkExtern: function.extern.name
  of adfkUser: function.user.name

proc arity*(function: AnalyzedDefFunction): int =
  case function.kind:
  of adfkExtern: function.extern.arity
  of adfkUser: function.user.arity