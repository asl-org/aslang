## Function cluster — ResolvedFunctionDef (a resolved signature: arg defs
## + return type) plus the function wrappers: ResolvedExternFunction
## (FFI body) and ResolvedUserFunction (def + statements), unified by the
## ResolvedFunction tagged union over user/extern.

import strformat, strutils, hashes

import ../tokenizer/index as tokenizer
import ../parser/index as parser
import argtype
import argtype
import statement

# ---- ResolvedFunctionDef ----
# A resolved function signature (arg defs + return type).

type ResolvedFunctionDef* = ref object
  parsed: FunctionDef
  args: seq[ResolvedArgumentDef]
  returns: ResolvedArgumentType

proc newResolvedFunctionDef*(parsed: FunctionDef,
    args: seq[ResolvedArgumentDef],
    returns: ResolvedArgumentType): ResolvedFunctionDef =
  ResolvedFunctionDef(parsed: parsed, args: args, returns: returns)

proc args*(funcDef: ResolvedFunctionDef): seq[ResolvedArgumentDef] = funcDef.args
proc returns*(funcDef: ResolvedFunctionDef): ResolvedArgumentType = funcDef.returns
proc public*(funcDef: ResolvedFunctionDef): bool = funcDef.parsed.public
proc name*(funcDef: ResolvedFunctionDef): Identifier = funcDef.parsed.name
proc arity*(funcDef: ResolvedFunctionDef): int = funcDef.parsed.arity
proc loc*(funcDef: ResolvedFunctionDef): Location = funcDef.parsed.loc

proc asl*(funcDef: ResolvedFunctionDef): string =
  var args: seq[string]
  for arg in funcDef.args:
    args.add(arg.asl)
  let argsJoined = args.join(", ")
  fmt"func {funcDef.name.asl}({argsJoined}): {funcDef.returns.asl}"

proc hash*(funcDef: ResolvedFunctionDef): Hash =
  var acc = funcDef.name.hash
  for arg in funcDef.args:
    acc = acc !& arg.hash
  return acc

proc `==`*(a, b: ResolvedFunctionDef): bool = a.hash == b.hash

proc concrete*(funcDef: ResolvedFunctionDef, subst: ResolvedImplMap): ResolvedFunctionDef =
  var concreteArgs: seq[ResolvedArgumentDef]
  for arg in funcDef.args:
    concreteArgs.add(arg.concrete(subst))
  let concreteReturns = funcDef.returns.concrete(subst)
  newResolvedFunctionDef(funcDef.parsed, concreteArgs, concreteReturns)

# ---- ResolvedExternFunction ----
# A function whose body lives in FFI-land, wrapping a resolved signature.

type ResolvedExternFunction* = ref object
  parsed: ExternFunction
  def: ResolvedFunctionDef

proc newResolvedExternFunction*(parsed: ExternFunction,
    def: ResolvedFunctionDef): ResolvedExternFunction =
  ResolvedExternFunction(parsed: parsed, def: def)

proc ffi*(function: ResolvedExternFunction): string = function.parsed.ffi
proc loc*(function: ResolvedExternFunction): Location = function.def.loc
proc name*(function: ResolvedExternFunction): Identifier = function.def.name
proc arity*(function: ResolvedExternFunction): int = function.def.arity
proc def*(function: ResolvedExternFunction): ResolvedFunctionDef = function.def

# ---- ResolvedUserFunction / ResolvedFunction ----

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
proc entry*(function: ResolvedUserFunction): bool = function.parsed.entry
proc name*(function: ResolvedUserFunction): Identifier = function.def.name
proc arity*(function: ResolvedUserFunction): int = function.def.arity
proc def*(function: ResolvedUserFunction): ResolvedFunctionDef = function.def
proc statements*(function: ResolvedUserFunction): seq[ResolvedStatement] = function.statements

type
  ResolvedFunctionKind* = enum
    rfkExtern, rfkUser, rfkGenerated
  ResolvedFunction* = ref object
    case kind: ResolvedFunctionKind
    of rfkExtern: extern: ResolvedExternFunction
    of rfkUser: user: ResolvedUserFunction
    of rfkGenerated: generated: ResolvedFunctionDef

proc newResolvedFunction*(extern: ResolvedExternFunction): ResolvedFunction =
  ResolvedFunction(kind: rfkExtern, extern: extern)

proc newResolvedFunction*(user: ResolvedUserFunction): ResolvedFunction =
  ResolvedFunction(kind: rfkUser, user: user)

proc newResolvedFunction*(generated: ResolvedFunctionDef): ResolvedFunction =
  ResolvedFunction(kind: rfkGenerated, generated: generated)

proc kind*(function: ResolvedFunction): ResolvedFunctionKind = function.kind
proc extern*(function: ResolvedFunction): ResolvedExternFunction =
  assert function.kind == rfkExtern,
    fmt"ResolvedFunction.extern accessed but kind is {function.kind}"
  function.extern
proc user*(function: ResolvedFunction): ResolvedUserFunction =
  assert function.kind == rfkUser,
    fmt"ResolvedFunction.user accessed but kind is {function.kind}"
  function.user
proc generated*(function: ResolvedFunction): ResolvedFunctionDef =
  assert function.kind == rfkGenerated,
    fmt"ResolvedFunction.generated accessed but kind is {function.kind}"
  function.generated

proc def*(function: ResolvedFunction): ResolvedFunctionDef =
  case function.kind:
  of rfkExtern: function.extern.def
  of rfkUser: function.user.def
  of rfkGenerated: function.generated
proc loc*(function: ResolvedFunction): Location =
  case function.kind:
  of rfkExtern: function.extern.loc
  of rfkUser: function.user.loc
  of rfkGenerated: function.generated.loc
