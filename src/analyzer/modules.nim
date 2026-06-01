## Module + generic block analysis.

import options, results

import parser
import resolver
import argtypes
import funcdefs
import data

# AnalyzedModuleDefinition
type AnalyzedModuleDefinition* = ref object
  resolved: ResolvedModule
  requires: seq[AnalyzedGenericArgumentType]
  data: Option[AnalyzedData]
  funcDefs: seq[AnalyzedFunctionDefinition]

proc newAnalyzedModuleDefinition*(resolved: ResolvedModule, requires: seq[AnalyzedGenericArgumentType], data: Option[AnalyzedData], funcDefs: seq[AnalyzedFunctionDefinition]): AnalyzedModuleDefinition =
  AnalyzedModuleDefinition(resolved: resolved, requires: requires, data: data, funcDefs: funcDefs)

proc requires*(m: AnalyzedModuleDefinition): seq[AnalyzedGenericArgumentType] = m.requires
proc data*(m: AnalyzedModuleDefinition): Option[AnalyzedData] = m.data
proc funcDefs*(m: AnalyzedModuleDefinition): seq[AnalyzedFunctionDefinition] = m.funcDefs
proc name*(m: AnalyzedModuleDefinition): Identifier = m.resolved.name

proc analyzeModuleDefinition*(app: ResolvedApp, file: ResolvedFile, fileScope: AnalyzedFileScope, module: ResolvedModule): Result[AnalyzedModuleDefinition, string] =
  var requires: seq[AnalyzedGenericArgumentType]
  for genericArgType in module.requires:
    let analyzedArgType = ? analyzeGenericArgumentType(app, file, module, genericArgType)
    requires.add(analyzedArgType)

  var maybeAnalyzedData: Option[AnalyzedData]
  if module.data.isSome:
    let analyzedData = ? analyzeData(app, file, fileScope, module, module.data.get)
    maybeAnalyzedData = some(analyzedData)

  var analyzedFuncDefs: seq[AnalyzedFunctionDefinition]
  for function in module.functions:
    let analyzedFuncDef = ? analyzeFunctionDefinition(app, file, fileScope, module, function.def)
    analyzedFuncDefs.add(analyzedFuncDef)

  ok(newAnalyzedModuleDefinition(module, requires, maybeAnalyzedData, analyzedFuncDefs))

# AnalyzedGeneric
type AnalyzedGeneric* = ref object
  resolved: ResolvedGeneric
  funcDefs: seq[AnalyzedFunctionDefinition]

proc newAnalyzedGeneric*(resolved: ResolvedGeneric, funcDefs: seq[AnalyzedFunctionDefinition]): AnalyzedGeneric =
  AnalyzedGeneric(resolved: resolved, funcDefs: funcDefs)

proc name*(g: AnalyzedGeneric): Identifier = g.resolved.name
proc resolved*(g: AnalyzedGeneric): ResolvedGeneric = g.resolved
proc funcDefs*(g: AnalyzedGeneric): seq[AnalyzedFunctionDefinition] = g.funcDefs

proc analyzeGeneric*(app: ResolvedApp, file: ResolvedFile, generic: ResolvedGeneric): Result[AnalyzedGeneric, string] =
  var analyzedFuncDefs: seq[AnalyzedFunctionDefinition]
  for funcDef in generic.funcDefs:
    let analyzedFuncDef = ? analyzeFunctionDefinition(app, file, generic, funcDef)
    analyzedFuncDefs.add(analyzedFuncDef)
  ok(newAnalyzedGeneric(generic, analyzedFuncDefs))
