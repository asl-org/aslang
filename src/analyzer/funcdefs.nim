## Analyzed argument definitions + function definitions.
## Layers on top of argtypes via analyzeArgumentType.

import results, strformat, strutils

import tokenizer
import parser
import resolver
import argtypes

# AnalyzedArgumentDefinition
type AnalyzedArgumentDefinition* = ref object
  argType: AnalyzedArgumentType
  name: Identifier

proc newAnalyzedArgumentDefinition*(argType: AnalyzedArgumentType, name: Identifier): AnalyzedArgumentDefinition =
  AnalyzedArgumentDefinition(argType: argType, name: name)

proc argType*(d: AnalyzedArgumentDefinition): AnalyzedArgumentType = d.argType
proc name*(d: AnalyzedArgumentDefinition): Identifier = d.name
proc asl*(argDef: AnalyzedArgumentDefinition): string =
  fmt"{argDef.name.asl}: {argDef.argType.asl}"

proc analyzeArgumentDefinition*(app: ResolvedApp, file: ResolvedFile, fileScope: ResolvedFileScope, module: ResolvedModule, argDef: ResolvedArgumentDefinition): Result[AnalyzedArgumentDefinition, string] =
  let analyzedArgType = ? analyzeArgumentType(app, file, fileScope, module, argDef.argType)
  ok(newAnalyzedArgumentDefinition(analyzedArgType, argDef.name))

proc analyzeArgumentDefinition*(app: ResolvedApp, file: ResolvedFile, fileScope: ResolvedFileScope, generic: ResolvedGeneric, argDef: ResolvedArgumentDefinition): Result[AnalyzedArgumentDefinition, string] =
  let analyzedArgType = ? analyzeArgumentType(app, file, fileScope, generic, argDef.argType)
  ok(newAnalyzedArgumentDefinition(analyzedArgType, argDef.name))

# AnalyzedFunctionDefinition
type AnalyzedFunctionDefinition* = ref object
  resolved: ResolvedFunctionDefinition
  args: seq[AnalyzedArgumentDefinition]
  returns: AnalyzedArgumentType

# TODO: Ensure that there are no duplicated generic fields
proc newAnalyzedFunctionDefinition*(resolved: ResolvedFunctionDefinition, args: seq[AnalyzedArgumentDefinition], returns: AnalyzedArgumentType): AnalyzedFunctionDefinition =
  AnalyzedFunctionDefinition(resolved: resolved, args: args, returns: returns)

proc public*(f: AnalyzedFunctionDefinition): bool = f.resolved.public
proc name*(f: AnalyzedFunctionDefinition): Identifier = f.resolved.name
proc loc*(f: AnalyzedFunctionDefinition): Location = f.resolved.loc
proc resolved*(f: AnalyzedFunctionDefinition): ResolvedFunctionDefinition = f.resolved
proc arity*(f: AnalyzedFunctionDefinition): int = f.args.len
proc args*(f: AnalyzedFunctionDefinition): seq[AnalyzedArgumentDefinition] = f.args
proc returns*(f: AnalyzedFunctionDefinition): AnalyzedArgumentType = f.returns
proc asl*(funcDef: AnalyzedFunctionDefinition): string =
  var args: seq[string]
  for arg in funcDef.args:
    args.add(arg.asl)
  let argsJoined = args.join(", ")
  fmt"func {funcDef.name.asl}({argsJoined}): {funcDef.returns.asl}"

proc analyzeFunctionDefinition*(app: ResolvedApp, file: ResolvedFile, fileScope: ResolvedFileScope, module: ResolvedModule, funcDef: ResolvedFunctionDefinition): Result[AnalyzedFunctionDefinition, string] =
  var analyzedArgDefs: seq[AnalyzedArgumentDefinition]
  for arg in funcDef.args:
    let analyzedArgDef = ? analyzeArgumentDefinition(app, file, fileScope, module, arg)
    analyzedArgDefs.add(analyzedArgDef)
  # echo fmt"BEFORE: {funcDef.returns.asl}"
  let analyzedReturns = ? analyzeArgumentType(app, file, fileScope, module, funcDef.returns)
  # echo fmt"AFTER: {analyzedReturns.asl}"
  ok(newAnalyzedFunctionDefinition(funcDef, analyzedArgDefs, analyzedReturns))

proc analyzeFunctionDefinition*(app: ResolvedApp, file: ResolvedFile, fileScope: ResolvedFileScope, generic: ResolvedGeneric, funcDef: ResolvedFunctionDefinition): Result[AnalyzedFunctionDefinition, string] =
  var analyzedArgDefs: seq[AnalyzedArgumentDefinition]
  for arg in funcDef.args:
    let analyzedArgDef = ? analyzeArgumentDefinition(app, file, fileScope, generic, arg)
    analyzedArgDefs.add(analyzedArgDef)

  let analyzedReturns = ? analyzeArgumentType(app, file, fileScope, generic, funcDef.returns)
  ok(newAnalyzedFunctionDefinition(funcDef, analyzedArgDefs, analyzedReturns))
