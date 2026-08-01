## Phase-A function wrappers — `AnalyzedDefExternFunction` /
## `AnalyzedDefUserFunction` each pair the resolver function with its
## pre-analyzed `AnalyzedFunctionDefinition`, and the tagged
## `AnalyzedDefFunction` (adfkExtern / adfkUser) gives
## `AnalyzedDefModule.functions` one shape with uniform `def` /
## `name` / `arity` accessors dispatching on the kind.

import resolver

import funcdef
import statement

type AnalyzedDefExternFunction* = ref object
  resolved: ResolvedExternFunction
  def: AnalyzedFunctionDefinition

proc newAnalyzedDefExternFunction*(resolved: ResolvedExternFunction, def: AnalyzedFunctionDefinition): AnalyzedDefExternFunction =
  AnalyzedDefExternFunction(resolved: resolved, def: def)

proc name*(function: AnalyzedDefExternFunction): Identifier = function.resolved.name
proc arity*(function: AnalyzedDefExternFunction): int = function.resolved.arity

type AnalyzedDefUserFunction* = ref object
  resolved: ResolvedUserFunction
  def: AnalyzedFunctionDefinition
  statements: seq[AnalyzedDefStatement]

proc newAnalyzedDefUserFunction*(resolved: ResolvedUserFunction, def: AnalyzedFunctionDefinition, statements: seq[AnalyzedDefStatement]): AnalyzedDefUserFunction =
  AnalyzedDefUserFunction(resolved: resolved, def: def, statements: statements)

proc name*(function: AnalyzedDefUserFunction): Identifier = function.resolved.name
proc arity*(function: AnalyzedDefUserFunction): int = function.resolved.arity
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

proc def*(function: AnalyzedDefFunction): AnalyzedFunctionDefinition =
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