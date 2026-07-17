import strformat, tables, results

import ./tokenizer
import ./error

import ./identifiers
import ./funcdef
import ./userfunc
import ./externfunc

# ============================================================
# Function (user | extern)
# ============================================================

type
  FunctionKind* = enum
    fkUser, fkExtern
  Function* = ref object
    case kind: FunctionKind
    of fkUser: user: UserFunction
    of fkExtern: extern: ExternFunction

proc newFunction*(user: UserFunction): Function =
  Function(kind: fkUser, user: user)

proc newFunction*(extern: ExternFunction): Function =
  Function(kind: fkExtern, extern: extern)

proc kind*(fn: Function): FunctionKind = fn.kind

proc user*(fn: Function): UserFunction =
  assert fn.kind == fkUser,
    fmt"Function.user accessed but kind is {fn.kind}"
  fn.user

proc extern*(fn: Function): ExternFunction =
  assert fn.kind == fkExtern,
    fmt"Function.extern accessed but kind is {fn.kind}"
  fn.extern

proc loc*(fn: Function): Location =
  case fn.kind:
  of fkUser: fn.user.loc
  of fkExtern: fn.extern.loc

proc name*(fn: Function): Identifier =
  case fn.kind:
  of fkUser: fn.user.name
  of fkExtern: fn.extern.name

proc def*(fn: Function): FunctionDef =
  case fn.kind:
  of fkUser: fn.user.def
  of fkExtern: fn.extern.def

proc arity*(fn: Function): int =
  case fn.kind:
  of fkUser: fn.user.arity
  of fkExtern: fn.extern.arity

proc asl*(fn: Function, level: int, indentWidth: uint32): seq[string] =
  case fn.kind:
  of fkUser: asl(fn.user, level, indentWidth)
  of fkExtern: asl(fn.extern, level, indentWidth)

# ============================================================
# FunctionList
# ============================================================

type FunctionList* = ref object
  functions: seq[Function]
  functionIndex: Table[Identifier, Table[int, seq[int]]]

proc newFunctionList*(functions: seq[Function]): Result[FunctionList, ParserError] =
  var functionIndex: Table[Identifier, Table[int, seq[int]]]
  # TODO: ensure that there no duplicate function signatures
  for index, function in functions:
    if function.name notin functionIndex:
      functionIndex[function.name] = initTable[int, seq[int]]()
    if function.arity notin functionIndex[function.name]:
      functionIndex[function.name][function.arity] = newSeq[int]()
    functionIndex[function.name][function.arity].add(index)
  ok(FunctionList(functions: functions, functionIndex: functionIndex))

proc functions*(fnlist: FunctionList): seq[Function] = fnlist.functions
proc len*(fnlist: FunctionList): int = fnlist.functions.len
