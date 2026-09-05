## Parser function cluster — FunctionDef (signature, no body) + the
## ExternFunction / UserFunction wrappers + the Function tagged union
## over them and the FunctionList index.

import strformat, strutils, sequtils, tables, results

import ./tokenizer/index
import ./error

import ./identifiers
import ./argtype
import ./decorator
import ./statement

# ============================================================
# FunctionDef (signature only, no body)
# ============================================================

type FunctionAccess* = enum
  ## What a function lookup may see: `faPublic` = public functions
  ## only (the caller's context is outside the defining module),
  ## `faAll` = every function (the caller IS the defining module).
  ## Derived from the enclosing definition via `LocalType.access`.
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
proc entry*(def: FunctionDef): bool =
  def.public and def.name.asl == "start" and def.arity == 0 and def.returns.asl == "i32"

proc asl*(funcDef: FunctionDef): string =
  let prefix = if funcDef.public: "public func" else: "func"
  fmt"{prefix} {funcDef.name.asl}{funcDef.argDefList.asl}: {funcDef.returns.asl}"

proc filter*(defs: seq[FunctionDef], access: FunctionAccess): seq[FunctionDef] =
  case access:
  of faAll: defs
  of faPublic: defs.filterIt(it.public)

# ============================================================
# ExternFunction
# ============================================================

type ExternFunction* = ref object
  ffi: string
  def: FunctionDef
  loc: Location

proc name*(fn: ExternFunction): Identifier = fn.def.name
proc arity*(fn: ExternFunction): int = fn.def.arity
proc def*(fn: ExternFunction): FunctionDef = fn.def
proc loc*(fn: ExternFunction): Location = fn.loc
proc ffi*(fn: ExternFunction): string = fn.ffi

proc newExternFunction*(ffi: string, def: FunctionDef, loc: Location): ExternFunction =
  ExternFunction(ffi: ffi, def: def, loc: loc)

proc asl*(fn: ExternFunction, level: int, indentWidth: uint32): seq[string] =
  let indent = " ".repeat(level * indentWidth.int)
  return @[
    fmt"{indent}@extern(""{fn.ffi}"")",
    fmt"{indent}{asl(fn.def)}",
  ]

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
proc arity*(fn: UserFunction): int = fn.def.arity
proc entry*(fn: UserFunction): bool = fn.def.entry
proc def*(fn: UserFunction): FunctionDef = fn.def
proc statements*(fn: UserFunction): seq[Statement] = fn.statementList.statements
proc decorators*(fn: UserFunction): seq[Decorator] = fn.decorators

proc asl*(fn: UserFunction, level: int, indentWidth: uint32): seq[string] =
  let indent = " ".repeat(level * indentWidth.int)
  var lines: seq[string]
  for d in fn.decorators:
    lines.add(fmt"{indent}{asl(d)}")
  lines.add(fmt"{indent}{asl(fn.def)}")
  for stmt in fn.statementList.statements:
    for line in asl(stmt, level + 1, indentWidth):
      lines.add(line)
  lines

# ============================================================
# Function (user | extern)
# ============================================================

type
  FunctionKind* = enum
    fkUser, fkExtern, fkGenerated
  Function* = ref object
    case kind: FunctionKind
    of fkUser: user: UserFunction
    of fkExtern: extern: ExternFunction
    of fkGenerated: generated: FunctionDef

proc newFunction*(user: UserFunction): Function =
  Function(kind: fkUser, user: user)

proc newFunction*(extern: ExternFunction): Function =
  Function(kind: fkExtern, extern: extern)

proc newFunction*(generated: FunctionDef): Function =
  Function(kind: fkGenerated, generated: generated)

proc kind*(fn: Function): FunctionKind = fn.kind

proc user*(fn: Function): UserFunction =
  assert fn.kind == fkUser,
    fmt"Function.user accessed but kind is {fn.kind}"
  fn.user

proc extern*(fn: Function): ExternFunction =
  assert fn.kind == fkExtern,
    fmt"Function.extern accessed but kind is {fn.kind}"
  fn.extern

proc generated*(fn: Function): FunctionDef =
  assert fn.kind == fkGenerated,
    fmt"Function.generated accessed but kind is {fn.kind}"
  fn.generated

proc loc*(fn: Function): Location =
  case fn.kind:
  of fkUser: fn.user.loc
  of fkExtern: fn.extern.loc
  of fkGenerated: fn.generated.loc

proc name*(fn: Function): Identifier =
  case fn.kind:
  of fkUser: fn.user.name
  of fkExtern: fn.extern.name
  of fkGenerated: fn.generated.name

proc def*(fn: Function): FunctionDef =
  case fn.kind:
  of fkUser: fn.user.def
  of fkExtern: fn.extern.def
  of fkGenerated: fn.generated

proc arity*(fn: Function): int =
  case fn.kind:
  of fkUser: fn.user.arity
  of fkExtern: fn.extern.arity
  of fkGenerated: fn.generated.arity

proc asl*(fn: Function, level: int, indentWidth: uint32): seq[string] =
  case fn.kind:
  of fkUser: asl(fn.user, level, indentWidth)
  of fkExtern: asl(fn.extern, level, indentWidth)
  of fkGenerated: @[]

proc byteSizeBuiltinFunction*(loc: Location): Function =
  let maybeName = newIdentifier("byte_size", loc)
  assert(maybeName.isOk, "[BUG] - failed to create function name identifier")
  let name = maybeName.get

  let maybeReturnTypeName = newIdentifier("u64", loc)
  assert(maybeReturnTypeName.isOk, "[BUG] - failed to create function return type identifier")
  let returnTypeName = maybeReturnTypeName.get
  let returnType = newArgumentType(returnTypeName)

  let maybeArgDefList = newArgumentDefList(@[], loc)
  assert(maybeArgDefList.isOk, "[BUG] - failed to create function argument definition list")
  let argDefList = maybeArgDefList.get

  let funcDef = newFunctionDef(true, name, argDefList, returnType, loc)
  return newFunction(funcDef)

# ============================================================
# FunctionList
# ============================================================

type FunctionList* = ref object
  functions: seq[Function]
  functionIndex: Table[Identifier, Table[int, seq[int]]]

proc newFunctionList*(functions: seq[Function]): Result[FunctionList, ParserError] =
  var functionIndex: Table[Identifier, Table[int, seq[int]]]
  # Duplicate input signatures are NOT checked here — the parser
  # cannot compare argument types by identity. resolveModule /
  # resolveGeneric own that check (input-signature uniqueness).
  for index, function in functions:
    if function.name notin functionIndex:
      functionIndex[function.name] = initTable[int, seq[int]]()
    if function.arity notin functionIndex[function.name]:
      functionIndex[function.name][function.arity] = newSeq[int]()
    functionIndex[function.name][function.arity].add(index)
  ok(FunctionList(functions: functions, functionIndex: functionIndex))

proc functions*(fnlist: FunctionList): seq[Function] = fnlist.functions
proc len*(fnlist: FunctionList): int = fnlist.functions.len
proc add*(fnlist: FunctionList, function: Function): Result[FunctionList, ParserError] =
  var functions = fnlist.functions
  functions.add(function)
  newFunctionList(functions)