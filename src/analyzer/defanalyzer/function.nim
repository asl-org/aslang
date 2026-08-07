## Phase-A function wrappers — `AnalyzedDefExternFunction` /
## `AnalyzedDefUserFunction` each pair the resolver function with its
## pre-analyzed `AnalyzedFunctionDef`, and the tagged
## `AnalyzedDefFunction` (adfkExtern / adfkUser) gives
## `AnalyzedDefModule.functions` one shape with uniform `def` /
## `name` / `arity` accessors dispatching on the kind.

import resolver, strformat

import funcdef
import statement

type AnalyzedDefExternFunction* = ref object
  resolved: ResolvedExternFunction
  def: AnalyzedFunctionDef

proc newAnalyzedDefExternFunction*(resolved: ResolvedExternFunction, def: AnalyzedFunctionDef): AnalyzedDefExternFunction =
  AnalyzedDefExternFunction(resolved: resolved, def: def)

proc name*(function: AnalyzedDefExternFunction): Identifier = function.resolved.name
proc arity*(function: AnalyzedDefExternFunction): int = function.resolved.arity
proc resolved*(function: AnalyzedDefExternFunction): ResolvedExternFunction = function.resolved

type AnalyzedDefUserFunction* = ref object
  resolved: ResolvedUserFunction
  def: AnalyzedFunctionDef
  statements: seq[AnalyzedDefStatement]

proc newAnalyzedDefUserFunction*(resolved: ResolvedUserFunction, def: AnalyzedFunctionDef, statements: seq[AnalyzedDefStatement]): AnalyzedDefUserFunction =
  AnalyzedDefUserFunction(resolved: resolved, def: def, statements: statements)

proc loc*(function: AnalyzedDefUserFunction): Location = function.resolved.loc
proc name*(function: AnalyzedDefUserFunction): Identifier = function.resolved.name
proc arity*(function: AnalyzedDefUserFunction): int = function.resolved.arity
proc resolved*(function: AnalyzedDefUserFunction): ResolvedUserFunction = function.resolved
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