## Analyzed argument definitions + function definitions.
## Layers on top of argtypes via analyzeArgumentType.

import results

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

proc analyzeArgumentDefinition*(app: ResolvedApp, file: ResolvedFile, fileScope: AnalyzedFileScope, module: ResolvedModule, argDef: ResolvedArgumentDefinition): Result[AnalyzedArgumentDefinition, string] =
  let analyzedArgType = ? analyzeArgumentType(app, file, fileScope, module, argDef.argType)
  ok(newAnalyzedArgumentDefinition(analyzedArgType, argDef.name))

proc analyzeArgumentDefinition*(app: ResolvedApp, file: ResolvedFile, fileScope: AnalyzedFileScope, generic: ResolvedGeneric, argDef: ResolvedArgumentDefinition): Result[AnalyzedArgumentDefinition, string] =
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

proc analyzeFunctionDefinition*(app: ResolvedApp, file: ResolvedFile, fileScope: AnalyzedFileScope, module: ResolvedModule, funcDef: ResolvedFunctionDefinition): Result[AnalyzedFunctionDefinition, string] =
  var analyzedArgDefs: seq[AnalyzedArgumentDefinition]
  for arg in funcDef.args:
    let analyzedArgDef = ? analyzeArgumentDefinition(app, file, fileScope, module, arg)
    analyzedArgDefs.add(analyzedArgDef)

  let analyzedReturns = ? analyzeArgumentType(app, file, fileScope, module, funcDef.returns)
  ok(newAnalyzedFunctionDefinition(funcDef, analyzedArgDefs, analyzedReturns))

proc analyzeFunctionDefinition*(app: ResolvedApp, file: ResolvedFile, fileScope: AnalyzedFileScope, generic: ResolvedGeneric, funcDef: ResolvedFunctionDefinition): Result[AnalyzedFunctionDefinition, string] =
  var analyzedArgDefs: seq[AnalyzedArgumentDefinition]
  for arg in funcDef.args:
    let analyzedArgDef = ? analyzeArgumentDefinition(app, file, fileScope, generic, arg)
    analyzedArgDefs.add(analyzedArgDef)

  let analyzedReturns = ? analyzeArgumentType(app, file, fileScope, generic, funcDef.returns)
  ok(newAnalyzedFunctionDefinition(funcDef, analyzedArgDefs, analyzedReturns))
