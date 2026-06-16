## Module + generic block analysis.

import options, results, tables, sequtils, strformat

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
  funcNameArityIndex: Table[Identifier, Table[int, seq[int]]]
  funcDefIndex: Table[ResolvedFunctionDefinition, int]

proc buildFuncNameArityIndex(funcDefs: seq[AnalyzedFunctionDefinition]): Table[Identifier, Table[int, seq[int]]] =
  for id, funcDef in funcDefs:
    if funcDef.name notin result:
      result[funcDef.name] = initTable[int, seq[int]]()
    if funcDef.arity notin result[funcDef.name]:
      result[funcDef.name][funcDef.arity] = newSeq[int]()
    result[funcDef.name][funcDef.arity].add(id)

proc newAnalyzedModuleDefinition*(resolved: ResolvedModule, requires: seq[AnalyzedGenericArgumentType], data: Option[AnalyzedData], funcDefs: seq[AnalyzedFunctionDefinition]): AnalyzedModuleDefinition =
  var funcDefIndex: Table[ResolvedFunctionDefinition, int]
  for id, funcDef in funcDefs:
    funcDefIndex[funcDef.resolved] = id
  AnalyzedModuleDefinition(resolved: resolved, requires: requires, data: data, funcDefs: funcDefs, funcNameArityIndex: buildFuncNameArityIndex(funcDefs), funcDefIndex: funcDefIndex)

proc resolved*(m: AnalyzedModuleDefinition): ResolvedModule = m.resolved
proc requires*(m: AnalyzedModuleDefinition): seq[AnalyzedGenericArgumentType] = m.requires
proc data*(m: AnalyzedModuleDefinition): Option[AnalyzedData] = m.data
proc funcDefs*(m: AnalyzedModuleDefinition): seq[AnalyzedFunctionDefinition] = m.funcDefs
proc name*(m: AnalyzedModuleDefinition): Identifier = m.resolved.name

proc findFunctionDefs*(module: AnalyzedModuleDefinition, name: Identifier, arity: int, public: bool): Result[seq[AnalyzedFunctionDefinition], string] =
  # TODO: Ensure public access modifier is considered while looking up the function
  if name notin module.funcNameArityIndex:
    err(fmt"{name.loc} module `{module.name.asl}` does not have a function named `{name.asl}`")
  elif arity notin module.funcNameArityIndex[name]:
    err(fmt"{name.loc} module `{module.name.asl}` does not have a function named `{name.asl}` with arity `{arity}`")
  else:
    let funcDefs = module.funcNameArityIndex[name][arity].mapIt(module.funcDefs[it])
    ok(if public: funcDefs.filterIt(it.public) else: funcDefs)

proc findFunctionDef*(module: AnalyzedModuleDefinition, funcDef: ResolvedFunctionDefinition): Result[AnalyzedFunctionDefinition, string] =
  if funcDef notin module.funcDefIndex:
    err(fmt"{funcDef.loc} module `{module.name.asl}` does not have a function with name `{funcDef.name.asl}`")
  else:
    ok(module.funcDefs[module.funcDefIndex[funcDef]])

proc analyzeModuleDefinition*(app: ResolvedApp, file: ResolvedFile, fileScope: ResolvedFileScope, module: ResolvedModule): Result[AnalyzedModuleDefinition, string] =
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
  funcNameArityIndex: Table[Identifier, Table[int, seq[int]]]

proc newAnalyzedGeneric*(resolved: ResolvedGeneric, funcDefs: seq[AnalyzedFunctionDefinition]): AnalyzedGeneric =
  AnalyzedGeneric(resolved: resolved, funcDefs: funcDefs, funcNameArityIndex: buildFuncNameArityIndex(funcDefs))

proc name*(g: AnalyzedGeneric): Identifier = g.resolved.name
proc resolved*(g: AnalyzedGeneric): ResolvedGeneric = g.resolved
proc funcDefs*(g: AnalyzedGeneric): seq[AnalyzedFunctionDefinition] = g.funcDefs

# NOTE: generic does not require the function defs to be marked public explicitly
proc findFunctionDefs*(generic: AnalyzedGeneric, name: Identifier, arity: int): Result[seq[AnalyzedFunctionDefinition], string] =
  if name notin generic.funcNameArityIndex:
    err(fmt"{name.loc} generic `{generic.name.asl}` does not have a function named `{name.asl}`")
  elif arity notin generic.funcNameArityIndex[name]:
    err(fmt"{name.loc} generic `{generic.name.asl}` does not have a function named `{name.asl}` with arity `{arity}`")
  else:
    let funcDefs = generic.funcNameArityIndex[name][arity].mapIt(generic.funcDefs[it])
    ok(funcDefs)

proc analyzeGeneric*(app: ResolvedApp, file: ResolvedFile, fileScope: ResolvedFileScope, generic: ResolvedGeneric): Result[AnalyzedGeneric, string] =
  var analyzedFuncDefs: seq[AnalyzedFunctionDefinition]
  for funcDef in generic.funcDefs:
    let analyzedFuncDef = ? analyzeFunctionDefinition(app, file, fileScope, generic, funcDef)
    analyzedFuncDefs.add(analyzedFuncDef)
  ok(newAnalyzedGeneric(generic, analyzedFuncDefs))

# AnalyzedDefinedType — umbrella over module and generic definitions.
# Lives in modules.nim (not decls.nim) so funcs.nim can use it for
# AnalyzedDefinedTypeScope without creating a circular import with decls.
type
  AnalyzedDefinedTypeKind* = enum
    adtkModule, adtkGeneric
  AnalyzedDefinedType* = ref object
    case kind: AnalyzedDefinedTypeKind
    of adtkModule: module: AnalyzedModuleDefinition
    of adtkGeneric: generic: AnalyzedGeneric

proc newAnalyzedDefinedType*(module: AnalyzedModuleDefinition): AnalyzedDefinedType =
  AnalyzedDefinedType(kind: adtkModule, module: module)

proc newAnalyzedDefinedType*(generic: AnalyzedGeneric): AnalyzedDefinedType =
  AnalyzedDefinedType(kind: adtkGeneric, generic: generic)

proc kind*(d: AnalyzedDefinedType): AnalyzedDefinedTypeKind = d.kind
proc module*(d: AnalyzedDefinedType): AnalyzedModuleDefinition =
  assert d.kind == adtkModule,
    fmt"AnalyzedDefinedType.module accessed but kind is {d.kind}"
  d.module
proc generic*(d: AnalyzedDefinedType): AnalyzedGeneric =
  assert d.kind == adtkGeneric,
    fmt"AnalyzedDefinedType.generic accessed but kind is {d.kind}"
  d.generic
proc name*(d: AnalyzedDefinedType): Identifier =
  case d.kind:
  of adtkModule: d.module.name
  of adtkGeneric: d.generic.name

proc findFunctionDefs*(definedType: AnalyzedDefinedType, name: Identifier, arity: int, public: bool): Result[seq[AnalyzedFunctionDefinition], string] =
  case definedType.kind:
  of adtkModule: definedType.module.findFunctionDefs(name, arity, public)
  of adtkGeneric: definedType.generic.findFunctionDefs(name, arity)

proc analyzeDefinedType*(app: ResolvedApp, file: ResolvedFile, fileScope: ResolvedFileScope, definedType: ResolvedDefinedType): Result[AnalyzedDefinedType, string] =
  case definedType.kind:
  of rdtkGeneric:
    let analyzedGeneric = ? analyzeGeneric(app, file, fileScope, definedType.generic)
    ok(newAnalyzedDefinedType(analyzedGeneric))
  of rdtkModule:
    let analyzedModule = ? analyzeModuleDefinition(app, file, fileScope, definedType.module)
    ok(newAnalyzedDefinedType(analyzedModule))
