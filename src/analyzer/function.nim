## Analyzed function cluster — AnalyzedExternFunction (body-less, just
## the def) + AnalyzedUserFunction (def + analyzed statements) + the
## AnalyzedFunction tagged union over them.

import strformat

import ./defanalyzer
import statement

# ---- AnalyzedExternFunction ----
# An extern function has no body, so the analyzed form is just the
# resolver back-ref + the function def.

type AnalyzedExternFunction* = ref object
  def: AnalyzedDefExternFunction

proc newAnalyzedExternFunction*(def: AnalyzedDefExternFunction): AnalyzedExternFunction =
  AnalyzedExternFunction(def: def)

proc def*(function: AnalyzedExternFunction): AnalyzedFunctionDef = function.def.def
proc loc*(function: AnalyzedExternFunction): Location = function.def.loc

# ---- AnalyzedUserFunction ----
# A user-defined function whose body has been analyzed: the resolver's
# back-ref + the arg/return def + the analyzed statement list.

type AnalyzedUserFunction* = ref object
  def: AnalyzedDefUserFunction
  statements: seq[AnalyzedStatement]

proc newAnalyzedUserFunction*(def: AnalyzedDefUserFunction, statements: seq[AnalyzedStatement]): AnalyzedUserFunction =
  AnalyzedUserFunction(def: def, statements: statements)

proc loc*(function: AnalyzedUserFunction): Location = function.def.loc
proc def*(function: AnalyzedUserFunction): AnalyzedFunctionDef = function.def.def
proc statements*(function: AnalyzedUserFunction): seq[AnalyzedStatement] = function.statements
proc entry(function: AnalyzedUserFunction): bool = function.def.entry

# ---- AnalyzedFunction ----

type
  AnalyzedFunctionKind* = enum
    afkUser, afkExtern
  AnalyzedFunction* = ref object
    case kind: AnalyzedFunctionKind
    of afkUser: user: AnalyzedUserFunction
    of afkExtern: extern: AnalyzedExternFunction

proc newAnalyzedFunction*(user: AnalyzedUserFunction): AnalyzedFunction =
  AnalyzedFunction(kind: afkUser, user: user)

proc newAnalyzedFunction*(extern: AnalyzedExternFunction): AnalyzedFunction =
  AnalyzedFunction(kind: afkExtern, extern: extern)

proc kind*(function: AnalyzedFunction): AnalyzedFunctionKind = function.kind
proc user*(function: AnalyzedFunction): AnalyzedUserFunction =
  assert function.kind == afkUser,
    fmt"AnalyzedFunction.user accessed but kind is {function.kind}"
  function.user
proc extern*(function: AnalyzedFunction): AnalyzedExternFunction =
  assert function.kind == afkExtern,
    fmt"AnalyzedFunction.extern accessed but kind is {function.kind}"
  function.extern
proc loc*(function: AnalyzedFunction): Location =
  case function.kind:
  of afkExtern: function.extern.loc
  of afkUser: function.user.loc
proc def*(function: AnalyzedFunction): AnalyzedFunctionDef =
  case function.kind:
  of afkExtern: def(function.extern)
  of afkUser: def(function.user)
proc entry*(function: AnalyzedFunction): bool =
  case function.kind:
  of afkExtern: false
  of afkUser: function.user.entry