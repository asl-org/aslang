## Phase-A `AnalyzedFunctionDef` — a resolver function
## definition paired with its fully-analyzed argument definitions and
## return type. Produced by phase-A `analyzeFunctionDefinition` when
## walking a module's or generic's function list; consumed by phase-B
## overload resolution + body-typing without re-analysis.
##
## `concrete*` substitutes generic slots in every arg + the return
## type via the given `GenericImplMap`, preserving the underlying
## resolver reference. The resolver back-ref (`resolved`) is copied
## as-is to the concrete def; see the same caveat noted on
## `AnalyzedArgumentDef.concrete`.

import strutils, sequtils

import ./resolver
import ./argtype
import ./argdef
import ./genericimplmap

type AnalyzedFunctionDef* = ref object
  resolved: ResolvedFunctionDef
  args: seq[AnalyzedArgumentDef]
  returns: AnalyzedArgumentType

proc newAnalyzedFunctionDef*(resolved: ResolvedFunctionDef,
    args: seq[AnalyzedArgumentDef],
    returns: AnalyzedArgumentType): AnalyzedFunctionDef =
  AnalyzedFunctionDef(resolved: resolved, args: args, returns: returns)

proc resolved*(f: AnalyzedFunctionDef): ResolvedFunctionDef = f.resolved
proc public*(f: AnalyzedFunctionDef): bool = f.resolved.public
proc name*(f: AnalyzedFunctionDef): Identifier = f.resolved.name
proc loc*(f: AnalyzedFunctionDef): Location = f.resolved.loc
proc arity*(f: AnalyzedFunctionDef): int = f.args.len
proc args*(f: AnalyzedFunctionDef): seq[AnalyzedArgumentDef] = f.args
proc returns*(f: AnalyzedFunctionDef): AnalyzedArgumentType = f.returns

proc asl*(f: AnalyzedFunctionDef): string =
  var args: seq[string]
  for arg in f.args:
    args.add(arg.asl)
  "func " & f.name.asl & "(" & args.join(", ") & "): " & f.returns.asl

proc filter*(defs: seq[AnalyzedFunctionDef], access: FunctionAccess): seq[AnalyzedFunctionDef] =
  case access:
  of faAll: defs
  of faPublic: defs.filterIt(it.public)

proc concrete*(f: AnalyzedFunctionDef,
    implMap: GenericImplMap): AnalyzedFunctionDef =
  ## Substitute generic slots in every arg + the return type via
  ## `implMap`. The resolver back-ref is preserved as-is on the
  ## concretized def — see the caveat on `argdef.concrete`; consider
  ## persisting the (originalDef, implMap) pair separately if
  ## downstream code needs precise source locations for concretized
  ## types.
  var concreteArgs: seq[AnalyzedArgumentDef]
  for arg in f.args:
    concreteArgs.add(arg.concrete(implMap))
  let concreteReturns = f.returns.concrete(implMap)
  newAnalyzedFunctionDef(f.resolved, concreteArgs, concreteReturns)
