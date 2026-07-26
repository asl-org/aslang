## Phase-A `AnalyzedFunctionDefinition` — a resolver function
## definition paired with its fully-analyzed argument definitions and
## return type. Produced by phase-A `analyzeFunctionDefinition` when
## walking a module's or generic's function list; consumed by phase-B
## overload resolution + body-typing without re-analysis.
##
## `concrete*` substitutes generic slots in every arg + the return
## type via the given `GenericImplMap`, preserving the underlying
## resolver reference. The resolver back-ref (`resolved`) is copied
## as-is to the concrete def; see the same caveat noted on
## `AnalyzedArgumentDefinition.concrete`.

import strutils

import ./resolver
import ./argtype
import ./argdef
import ./genericimplmap

type AnalyzedFunctionDefinition* = ref object
  resolved: ResolvedFunctionDef
  args: seq[AnalyzedArgumentDefinition]
  returns: AnalyzedArgumentType

proc newAnalyzedFunctionDefinition*(resolved: ResolvedFunctionDef,
    args: seq[AnalyzedArgumentDefinition],
    returns: AnalyzedArgumentType): AnalyzedFunctionDefinition =
  AnalyzedFunctionDefinition(resolved: resolved, args: args, returns: returns)

proc resolved*(f: AnalyzedFunctionDefinition): ResolvedFunctionDef = f.resolved
proc public*(f: AnalyzedFunctionDefinition): bool = f.resolved.public
proc name*(f: AnalyzedFunctionDefinition): Identifier = f.resolved.name
proc loc*(f: AnalyzedFunctionDefinition): Location = f.resolved.loc
proc arity*(f: AnalyzedFunctionDefinition): int = f.args.len
proc args*(f: AnalyzedFunctionDefinition): seq[AnalyzedArgumentDefinition] = f.args
proc returns*(f: AnalyzedFunctionDefinition): AnalyzedArgumentType = f.returns

proc asl*(f: AnalyzedFunctionDefinition): string =
  var args: seq[string]
  for arg in f.args:
    args.add(arg.asl)
  "func " & f.name.asl & "(" & args.join(", ") & "): " & f.returns.asl

proc concrete*(f: AnalyzedFunctionDefinition,
    implMap: GenericImplMap): AnalyzedFunctionDefinition =
  ## Substitute generic slots in every arg + the return type via
  ## `implMap`. The resolver back-ref is preserved as-is on the
  ## concretized def — see the caveat on `argdef.concrete`; consider
  ## persisting the (originalDef, implMap) pair separately if
  ## downstream code needs precise source locations for concretized
  ## types.
  var concreteArgs: seq[AnalyzedArgumentDefinition]
  for arg in f.args:
    concreteArgs.add(arg.concrete(implMap))
  let concreteReturns = f.returns.concrete(implMap)
  newAnalyzedFunctionDefinition(f.resolved, concreteArgs, concreteReturns)
