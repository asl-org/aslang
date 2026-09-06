## Analyzed function cluster — AnalyzedExternFunction (body-less, just
## the def) + AnalyzedUserFunction (def + analyzed statements) + the
## AnalyzedFunction tagged union over them.

import strformat

import ../tokenizer/main as tokenizer
import ../parser/main as parser
import ../resolver/main as resolver
import ../defanalyzer/main as defanalyzer
import statement

# ---- AnalyzedUserFunction ----
# A user-defined function whose body has been analyzed: the resolver's
# back-ref + the arg/return def + the analyzed statement list.

type AnalyzedUserFunction* = ref object
  def: AnalyzedDefUserFunction
  statements: seq[AnalyzedStatement]

proc newAnalyzedUserFunction*(def: AnalyzedDefUserFunction, statements: seq[AnalyzedStatement]): AnalyzedUserFunction =
  AnalyzedUserFunction(def: def, statements: statements)

proc loc*(function: AnalyzedUserFunction): Location = function.def.loc
proc name*(function: AnalyzedUserFunction): Identifier = function.def.def.name
proc generics*(function: AnalyzedUserFunction): seq[ResolvedGeneric] = function.def.def.generics
proc def*(function: AnalyzedUserFunction): AnalyzedFunctionDef = function.def.def
proc statements*(function: AnalyzedUserFunction): seq[AnalyzedStatement] = function.statements
proc entry(function: AnalyzedUserFunction): bool = function.def.entry

# ---- AnalyzedFunction ----

type
  AnalyzedFunctionKind* = enum
    afkUser, afkExtern, afkGenerated
  AnalyzedFunction* = ref object
    case kind: AnalyzedFunctionKind
    of afkUser: user: AnalyzedUserFunction
    of afkExtern: extern: AnalyzedExternFunction
    of afkGenerated: generated: AnalyzedFunctionDef

proc newAnalyzedFunction*(user: AnalyzedUserFunction): AnalyzedFunction =
  AnalyzedFunction(kind: afkUser, user: user)

proc newAnalyzedFunction*(extern: AnalyzedExternFunction): AnalyzedFunction =
  AnalyzedFunction(kind: afkExtern, extern: extern)

proc newAnalyzedFunction*(generated: AnalyzedFunctionDef): AnalyzedFunction =
  AnalyzedFunction(kind: afkGenerated, generated: generated)

proc kind*(function: AnalyzedFunction): AnalyzedFunctionKind = function.kind
proc user*(function: AnalyzedFunction): AnalyzedUserFunction =
  assert function.kind == afkUser,
    fmt"AnalyzedFunction.user accessed but kind is {function.kind}"
  function.user
proc extern*(function: AnalyzedFunction): AnalyzedExternFunction =
  assert function.kind == afkExtern,
    fmt"AnalyzedFunction.extern accessed but kind is {function.kind}"
  function.extern
proc generated*(function: AnalyzedFunction): AnalyzedFunctionDef =
  assert function.kind == afkGenerated,
    fmt"AnalyzedFunction.generated accessed but kind is {function.kind}"
  function.generated
proc loc*(function: AnalyzedFunction): Location =
  case function.kind:
  of afkExtern: function.extern.loc
  of afkUser: function.user.loc
  of afkGenerated: function.generated.loc
proc def*(function: AnalyzedFunction): AnalyzedFunctionDef =
  case function.kind:
  of afkExtern: def(function.extern)
  of afkUser: def(function.user)
  of afkGenerated: function.generated
proc name*(function: AnalyzedFunction): Identifier =
  case function.kind:
  of afkExtern: function.extern.name
  of afkUser: function.user.name
  of afkGenerated: function.generated.name
proc entry*(function: AnalyzedFunction): bool =
  case function.kind:
  of afkUser: function.user.entry
  of afkExtern, afkGenerated: false