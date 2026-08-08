## ResolvedFunctionDef — a resolved function signature (arg defs + return
## type). Depends on ResolvedArgumentDef and ResolvedArgumentType.

import strformat, strutils, hashes

import ./parser
import argtype
import argdef

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
