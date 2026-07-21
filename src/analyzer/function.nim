## AnalyzedFunction — tagged union over user/extern functions. Lives
## with its Kind enum in one file: enum + variant type + constructors +
## accessors are all one cohesive unit.

import strformat

import userfunc
import externfunc

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
