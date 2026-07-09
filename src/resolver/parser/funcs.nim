import strformat, strutils, tables, results

import ./tokenizer
import ./combinators
import ./identifiers
import ./literals
import ./argtypes
import ./body

# ============================================================
# FunctionDef (signature only, no body)
# ============================================================

type FunctionDef* = ref object
  public: bool
  name: Identifier
  argDefList: ArgumentDefList
  returns: ArgumentType
  loc: Location

proc public*(fd: FunctionDef): bool = fd.public
proc name*(fd: FunctionDef): Identifier = fd.name
proc args*(fd: FunctionDef): seq[
    ArgumentDef] = fd.argDefList.argDefs
proc returns*(fd: FunctionDef): ArgumentType = fd.returns
proc loc*(fd: FunctionDef): Location = fd.loc
proc arity*(fd: FunctionDef): int = fd.argDefList.arity

proc newFunctionDef*(public: bool, name: Identifier,
    argDefList: ArgumentDefList, returns: ArgumentType,
    loc: Location): FunctionDef =
  FunctionDef(public: public, name: name, argDefList: argDefList,
      returns: returns, loc: loc)

proc asl*(funcDef: FunctionDef): string =
  let prefix = if funcDef.public: "public func" else: "func"
  fmt"{prefix} {asl(funcDef.name)}{asl(funcDef.argDefList)}: {asl(funcDef.returns)}"

let functionDefSpec* = Spec[FunctionDef](
  name: "function_definition",
  parseFn: proc(parser: Parser): Result[FunctionDef, ParserError] =
  let public = ? parser.run(presence(keywordSpec("public")))
  if public: discard ? parser.run(ws1)

  let funcLoc = ? parser.run(keywordSpec("func"))
  discard ? parser.run(ws1)
  let funcName = ? parser.run(identifierSpec)
  discard parser.run(ws0)
  let argDefList = ? parser.run(argumentDefListSpec)
  discard ? parser.run(colonWithSpacesSpec)
  let returnType = ? parser.run(argumentTypeSpec)
  ok(newFunctionDef(public, funcName, argDefList, returnType, funcLoc))
)

# Function definition line: indentation + function signature + newline
# Used by genericSpec via functionDefListSpec.
let functionDefLineSpec* = indentedLine(functionDefSpec)

let functionDefListSpec* = atLeastOne(functionDefLineSpec)

# ============================================================
# UserFunction
# ============================================================

type UserFunction* = ref object
  decorators: seq[Decorator]
  def: FunctionDef
  statementList: StatementList

proc newUserFunction*(decorators: seq[Decorator], def: FunctionDef,
    statementList: StatementList): UserFunction =
  UserFunction(decorators: decorators, def: def, statementList: statementList)

proc loc*(fn: UserFunction): Location = fn.def.loc
proc name*(fn: UserFunction): Identifier = fn.def.name
proc def*(fn: UserFunction): FunctionDef = fn.def
proc statements*(fn: UserFunction): seq[Statement] = fn.statementList.statements
proc decorators*(fn: UserFunction): seq[Decorator] = fn.decorators
proc arity*(fn: UserFunction): int = fn.def.arity

proc asl(fn: UserFunction, indentWidth: uint32): seq[string] =
  for d in fn.decorators:
    result.add(asl(d))
  result.add(asl(fn.def))
  let indent = " ".repeat(indentWidth)
  for stmt in fn.statementList.statements:
    for line in aslBlock(stmt, indentWidth):
      result.add(fmt"{indent}{line}")

let userFunctionSpec = decoratedBlockSpec("user_function", functionDefSpec,
  statementListSpec,
  proc(d: seq[Decorator], h: FunctionDef, b: StatementList): UserFunction =
  newUserFunction(d, h, b))

# ============================================================
# ExternFunction
# ============================================================

type ExternFunction* = ref object
  ffi: string
  def: FunctionDef
  loc: Location

proc ffi*(fn: ExternFunction): string = fn.ffi
proc name*(fn: ExternFunction): Identifier = fn.def.name
proc def*(fn: ExternFunction): FunctionDef = fn.def
proc arity*(fn: ExternFunction): int = fn.def.arity
proc loc*(fn: ExternFunction): Location = fn.loc

proc newExternFunction*(ffi: string, def: FunctionDef,
    loc: Location): ExternFunction =
  ExternFunction(ffi: ffi, def: def, loc: loc)

proc asl(fn: ExternFunction, indentWidth: uint32): seq[string] =
  result.add(fmt"@extern(""{fn.ffi}"")")
  result.add(asl(fn.def))

# @extern("symbol")
# public func name(args): ReturnType
let externFunctionSpec = Spec[ExternFunction](
  name: "extern_function",
  parseFn: proc(parser: Parser): Result[ExternFunction, ParserError] =
  discard ? parser.run(indentationSpec)
  discard ? parser.run(punctuationSpec("@"))
  discard ? parser.run(keywordSpec("extern"))
  discard parser.run(ws0)
  let loc = parser.loc
  let symbol = ? parser.run(contained("extern_symbol", "(", stringLiteralSpec, ")"))
  discard ? parser.run(ignorableLineSpec)
  discard ? parser.run(indentationSpec)
  let def = ? parser.run(functionDefSpec)
  discard ? parser.run(ignorableLineSpec)
  ok(newExternFunction(symbol.value, def, loc))
)

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

proc asl*(fn: Function, indentWidth: uint32): seq[string] =
  case fn.kind:
  of fkUser: asl(fn.user, indentWidth)
  of fkExtern: asl(fn.extern, indentWidth)

# Each function block skips leading ignorable lines then parses a function.
# any() backtracks the ignorable line consumption if no function follows.
let functionSpec = Spec[Function](
  name: "function_block",
  parseFn: proc(parser: Parser): Result[Function, ParserError] =
  discard parser.run(blankLines)
  let f = parser.run(externFunctionSpec)
  if f.isOk: return ok(newFunction(f.get))
  let u = ? parser.run(userFunctionSpec)
  ok(newFunction(u))
)

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

let functionListSpec* = any(functionSpec).map("function_list",
  proc(fns: seq[Function]): Result[FunctionList, ParserError] = newFunctionList(fns))
