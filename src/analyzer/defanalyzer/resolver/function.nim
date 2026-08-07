## Function cluster — ResolvedUserFunction wraps a ResolvedFunctionDef
## + statements; ResolvedFunction is the tagged union over user/extern.

import strformat

import ./parser
import funcdef
import externfunc
import statement

type
  ResolvedUserFunction* = ref object
    parsed: UserFunction
    def: ResolvedFunctionDef
    statements: seq[ResolvedStatement]

proc newResolvedUserFunction*(parsed: UserFunction,
    def: ResolvedFunctionDef,
    statements: seq[ResolvedStatement]): ResolvedUserFunction =
  assert(parsed.decorators.len == 0, fmt"{parsed.loc} todo: resolve decorators in user function")
  ResolvedUserFunction(parsed: parsed, def: def, statements: statements)

proc loc*(function: ResolvedUserFunction): Location = function.parsed.loc
proc name*(function: ResolvedUserFunction): Identifier = function.def.name
proc arity*(function: ResolvedUserFunction): int = function.def.arity
proc def*(function: ResolvedUserFunction): ResolvedFunctionDef = function.def
proc statements*(function: ResolvedUserFunction): seq[ResolvedStatement] = function.statements

type
  ResolvedFunctionKind* = enum
    rfkExtern, rfkUser
  ResolvedFunction* = ref object
    case kind: ResolvedFunctionKind
    of rfkExtern: extern: ResolvedExternFunction
    of rfkUser: user: ResolvedUserFunction

proc newResolvedFunction*(extern: ResolvedExternFunction): ResolvedFunction =
  ResolvedFunction(kind: rfkExtern, extern: extern)

proc newResolvedFunction*(user: ResolvedUserFunction): ResolvedFunction =
  ResolvedFunction(kind: rfkUser, user: user)

proc kind*(function: ResolvedFunction): ResolvedFunctionKind = function.kind
proc extern*(function: ResolvedFunction): ResolvedExternFunction =
  assert function.kind == rfkExtern,
    fmt"ResolvedFunction.extern accessed but kind is {function.kind}"
  function.extern
proc user*(function: ResolvedFunction): ResolvedUserFunction =
  assert function.kind == rfkUser,
    fmt"ResolvedFunction.user accessed but kind is {function.kind}"
  function.user

proc def*(function: ResolvedFunction): ResolvedFunctionDef =
  case function.kind:
  of rfkExtern: function.extern.def
  of rfkUser: function.user.def
proc loc*(function: ResolvedFunction): Location =
  case function.kind:
  of rfkExtern: function.extern.loc
  of rfkUser: function.user.loc
