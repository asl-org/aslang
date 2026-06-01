## Module + generic block analysis.

import options, results

import resolver
import argtypes
import funcdefs
import data

# AnalyzedModule
type AnalyzedModule* = ref object
  requires: seq[AnalyzedGenericArgumentType]
  data: Option[AnalyzedData]
  funcDefs: seq[AnalyzedFunctionDefinition]

proc newAnalyzedModule*(requires: seq[AnalyzedGenericArgumentType], data: Option[AnalyzedData], funcDefs: seq[AnalyzedFunctionDefinition]): AnalyzedModule =
  AnalyzedModule(requires: requires, data: data, funcDefs: funcDefs)

proc requires*(m: AnalyzedModule): seq[AnalyzedGenericArgumentType] = m.requires
proc data*(m: AnalyzedModule): Option[AnalyzedData] = m.data
proc funcDefs*(m: AnalyzedModule): seq[AnalyzedFunctionDefinition] = m.funcDefs

proc analyzeModule*(app: ResolvedApp, file: ResolvedFile, fileScope: AnalyzedFileScope, module: ResolvedModule): Result[AnalyzedModule, string] =
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

  ok(newAnalyzedModule(requires, maybeAnalyzedData, analyzedFuncDefs))

# AnalyzedGeneric
type AnalyzedGeneric* = ref object
  resolved: ResolvedGeneric
  funcDefs: seq[AnalyzedFunctionDefinition]

proc newAnalyzedGeneric*(resolved: ResolvedGeneric, funcDefs: seq[AnalyzedFunctionDefinition]): AnalyzedGeneric =
  AnalyzedGeneric(resolved: resolved, funcDefs: funcDefs)

proc resolved*(g: AnalyzedGeneric): ResolvedGeneric = g.resolved
proc funcDefs*(g: AnalyzedGeneric): seq[AnalyzedFunctionDefinition] = g.funcDefs

proc analyzeGeneric*(app: ResolvedApp, file: ResolvedFile, generic: ResolvedGeneric): Result[AnalyzedGeneric, string] =
  var analyzedFuncDefs: seq[AnalyzedFunctionDefinition]
  for funcDef in generic.funcDefs:
    let analyzedFuncDef = ? analyzeFunctionDefinition(app, file, generic, funcDef)
    analyzedFuncDefs.add(analyzedFuncDef)
  ok(newAnalyzedGeneric(generic, analyzedFuncDefs))
