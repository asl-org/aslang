## Definition-analysis barrel — phase A of the two-pass analyzer.
## Hosts the def-level analyze* procs (analyzeGenericArgumentType
## through analyzeAppDefinition) and re-exports every def-level
## analyzed type plus the resolver layer beneath, so the body layer
## (src/analyzer.nim + src/analyzer/) says `import ./defanalyzer`
## once. Nesting convention: parser ⊂ resolver ⊂ defanalyzer ⊂
## analyzer.

import options, results, strformat

import ./defanalyzer/resolver
export resolver

import ./defanalyzer/filescope
export filescope

import ./defanalyzer/argtype
export argtype

import ./defanalyzer/genericargtype
export genericargtype

import ./defanalyzer/genericimplmap
export genericimplmap

import ./defanalyzer/argdef
export argdef

import ./defanalyzer/funcdef
export funcdef

import ./defanalyzer/literaldef
export literaldef

import ./defanalyzer/structdef
export structdef

import ./defanalyzer/variantdef
export variantdef

import ./defanalyzer/uniondef
export uniondef

import ./defanalyzer/datadef
export datadef

import ./defanalyzer/moduledef
export moduledef

import ./defanalyzer/generic
export generic

import ./defanalyzer/types
export types

import ./defanalyzer/filedef
export filedef

import ./defanalyzer/appdef
export appdef

import ./defanalyzer/importedtypedef
export importedtypedef

import ./defanalyzer/importdef
export importdef

proc analyzeGenericArgumentType*(fileScope: ResolvedFileScope, generic: ResolvedGeneric, genericArgType: ResolvedGenericArgumentType): Result[AnalyzedGenericArgumentType, string] =
  let genericArg = ? fileScope.findGeneric(genericArgType.parsed, genericArgType.loc)
  if genericArg != generic:
    err(fmt"{genericArgType.loc} generic `{genericArgType.parsed.name.asl}` does not exist")
  else:
    ok(newAnalyzedGenericArgumentType(genericArg, genericArgType.loc))

proc analyzeGenericArgumentType*(fileScope: ResolvedFileScope, genericArgType: ResolvedGenericArgumentType): Result[AnalyzedGenericArgumentType, string] =
  let genericArg = ? fileScope.findGeneric(genericArgType.parsed, genericArgType.loc)
  ok(newAnalyzedGenericArgumentType(genericArg, genericArgType.loc))

proc analyzeArgumentType*(fileScope: ResolvedFileScope, module: ResolvedModule, argType: ResolvedArgumentType): Result[AnalyzedArgumentType, string]
proc analyzeArgumentType*(fileScope: ResolvedFileScope, generic: ResolvedGeneric, argType: ResolvedArgumentType): Result[AnalyzedArgumentType, string]

proc analyzeModuleArgumentType*(fileScope: ResolvedFileScope, module: ResolvedModule, argType: ResolvedModuleArgumentType): Result[AnalyzedModuleArgumentType, string] =
  let typeModule = ? fileScope.findModule(argType.module, argType.loc)
  var analyzedImpls: seq[AnalyzedArgumentType]
  for impl in argType.impls:
    let analyzedImpl = ? analyzeArgumentType(fileScope, module, impl)
    analyzedImpls.add(analyzedImpl)
  ok(newAnalyzedModuleArgumentType(argType, typeModule, analyzedImpls))

proc analyzeModuleArgumentType*(fileScope: ResolvedFileScope, generic: ResolvedGeneric, argType: ResolvedModuleArgumentType): Result[AnalyzedModuleArgumentType, string] =
  let typeModule = ? fileScope.findModule(argType.module, argType.loc)
  var analyzedImpls: seq[AnalyzedArgumentType]
  for impl in argType.impls:
    let analyzedImpl = ? analyzeArgumentType(fileScope, generic, impl)
    analyzedImpls.add(analyzedImpl)
  ok(newAnalyzedModuleArgumentType(argType, typeModule, analyzedImpls))

proc analyzeArgumentType*(fileScope: ResolvedFileScope, module: ResolvedModule, argType: ResolvedArgumentType): Result[AnalyzedArgumentType, string] =
  case argType.kind:
  of ratkGeneric:
    let analyzedArgType = ? analyzeGenericArgumentType(fileScope, argType.generic)
    ok(newAnalyzedArgumentType(analyzedArgType))
  of ratkModule:
    let analyzedArgType = ? analyzeModuleArgumentType(fileScope, module, argType.module)
    ok(newAnalyzedArgumentType(analyzedArgType))

proc analyzeArgumentType*(fileScope: ResolvedFileScope, generic: ResolvedGeneric, argType: ResolvedArgumentType): Result[AnalyzedArgumentType, string] =
  case argType.kind:
  of ratkGeneric:
    let analyzedArgType = ? analyzeGenericArgumentType(fileScope, generic, argType.generic)
    ok(newAnalyzedArgumentType(analyzedArgType))
  of ratkModule:
    let analyzedArgType = ? analyzeModuleArgumentType(fileScope, generic, argType.module)
    ok(newAnalyzedArgumentType(analyzedArgType))

# ============================================================
# Phase-A argument / function def analyzers (W2 of
# plans/plan_analyzer_two_pass.md). Ported from oldanalyzer.nim:479
# (analyzeArgumentDefinition) and :522 (analyzeFunctionDefinition).
#
# ⚠ KNOWN LIMITATION — SIGNATURE-PARITY IS HASH-EQUALITY, NOT
#   UNIFICATION.
#
# The impl-satisfies-base signature check (currently done at
# `analyzeValueTypeAgainstDefType` on the facade + `checkImplSatisfiesGeneric`
# on the resolver) uses hash-based `==` for AnalyzedArgumentType
# comparison. That works for fully-bound-vs-fully-bound comparisons
# but not for cases where either side carries free generics
# (post leave-as-is inference).
#
# What breaks: an impl providing `byte_size(items: Array[u8])` where
# the base generic mandates `byte_size(items: Array[Any])` — hash
# equality treats these as different types when a unification pass
# would bind `Any → u8` and accept the impl. Dormant today because
# every fixture in the test suite uses fully-bound impl types at the
# base-generic satisfaction boundary; the bug lies waiting until
# someone writes an impl whose funcDef references a partially-generic
# argument type.
#
# The fix requires routing every assignability check through
# `analyzeValueTypeAgainstDefType` + `merge` with eager chain-
# collapsing in `merge` (so `Sample → K, K → u8` collapses to
# `Sample → u8`). See `plans/plan_deferred_typing.md` §
# "Equality vs unification for analyzed types" — that plan owns the
# fix; this port preserves current behavior and does not introduce
# any new use of `==`.
# ============================================================

proc analyzeArgumentDefinition*(fileScope: ResolvedFileScope, module: ResolvedModule, argDef: ResolvedArgumentDef): Result[AnalyzedArgumentDefinition, string] =
  let analyzedArgType = ? analyzeArgumentType(fileScope, module, argDef.argType)
  ok(newAnalyzedArgumentDefinition(argDef, analyzedArgType))

proc analyzeArgumentDefinition*(fileScope: ResolvedFileScope, generic: ResolvedGeneric, argDef: ResolvedArgumentDef): Result[AnalyzedArgumentDefinition, string] =
  let analyzedArgType = ? analyzeArgumentType(fileScope, generic, argDef.argType)
  ok(newAnalyzedArgumentDefinition(argDef, analyzedArgType))

proc analyzeFunctionDefinition*(fileScope: ResolvedFileScope, module: ResolvedModule, funcDef: ResolvedFunctionDef): Result[AnalyzedFunctionDefinition, string] =
  var analyzedArgDefs: seq[AnalyzedArgumentDefinition]
  for arg in funcDef.args:
    let analyzedArgDef = ? analyzeArgumentDefinition(fileScope, module, arg)
    analyzedArgDefs.add(analyzedArgDef)
  let analyzedReturns = ? analyzeArgumentType(fileScope, module, funcDef.returns)
  ok(newAnalyzedFunctionDefinition(funcDef, analyzedArgDefs, analyzedReturns))

proc analyzeFunctionDefinition*(fileScope: ResolvedFileScope, generic: ResolvedGeneric, funcDef: ResolvedFunctionDef): Result[AnalyzedFunctionDefinition, string] =
  var analyzedArgDefs: seq[AnalyzedArgumentDefinition]
  for arg in funcDef.args:
    let analyzedArgDef = ? analyzeArgumentDefinition(fileScope, generic, arg)
    analyzedArgDefs.add(analyzedArgDef)
  let analyzedReturns = ? analyzeArgumentType(fileScope, generic, funcDef.returns)
  ok(newAnalyzedFunctionDefinition(funcDef, analyzedArgDefs, analyzedReturns))

proc analyzeStruct*(fileScope: ResolvedFileScope, module: ResolvedModule, struct: ResolvedStructDef): Result[AnalyzedStructDef, string] =
  var analyzedFields: seq[AnalyzedArgumentDefinition]
  for field in struct.fields:
    let analyzedField = ? analyzeArgumentDefinition(fileScope, module, field)
    analyzedFields.add(analyzedField)
  ok(newAnalyzedStructDef(struct, analyzedFields))

proc analyzeVariant*(fileScope: ResolvedFileScope, module: ResolvedModule, variant: ResolvedVariant): Result[AnalyzedVariant, string] =
  var analyzedFields: seq[AnalyzedArgumentDefinition]
  for field in variant.fields:
    let analyzedField = ? analyzeArgumentDefinition(fileScope, module, field)
    analyzedFields.add(analyzedField)
  ok(newAnalyzedVariant(variant, analyzedFields))

proc analyzeUnion*(fileScope: ResolvedFileScope, module: ResolvedModule, union: ResolvedUnionDef): Result[AnalyzedUnion, string] =
  var analyzedVariants: seq[AnalyzedVariant]
  for variant in union.variants:
    let analyzedVariant = ? analyzeVariant(fileScope, module, variant)
    analyzedVariants.add(analyzedVariant)
  ok(newAnalyzedUnion(union, analyzedVariants))

proc analyzeData*(fileScope: ResolvedFileScope, module: ResolvedModule, data: ResolvedData): Result[AnalyzedData, string] =
  case data.kind:
  of rdkLiteral:
    ok(newAnalyzedData(newAnalyzedLiteralDef(data.literal)))
  of rdkStruct:
    let analyzedStruct = ? analyzeStruct(fileScope, module, data.struct)
    ok(newAnalyzedData(analyzedStruct))
  of rdkUnion:
    let analyzedUnion = ? analyzeUnion(fileScope, module, data.union)
    ok(newAnalyzedData(analyzedUnion))

# ============================================================
# Phase-A module + generic analyzers (W4 of plan_analyzer_two_pass.md).
# Ported from oldanalyzer.nim:763 (analyzeModuleDefinition) and :811
# (analyzeGeneric).
#
# Note: `analyzeModuleDefinition`'s requires walk reads
# `module.data.get.requires` (post the resolver's struct-header merge)
# rather than the retired module-level `requires` clause. Modules
# without a data block carry an empty requires seq.
# ============================================================

proc analyzeModuleDefinition*(fileScope: ResolvedFileScope, module: ResolvedModule): Result[AnalyzedDefModule, string] =
  var requires: seq[AnalyzedGenericArgumentType]
  if module.data.isSome:
    for genericArgType in module.data.get.requires:
      let analyzedArgType = ? analyzeGenericArgumentType(fileScope, genericArgType)
      requires.add(analyzedArgType)

  var maybeAnalyzedData: Option[AnalyzedData]
  if module.data.isSome:
    let analyzedData = ? analyzeData(fileScope, module, module.data.get)
    maybeAnalyzedData = some(analyzedData)

  var analyzedFuncDefs: seq[AnalyzedFunctionDefinition]
  for function in module.functions:
    let analyzedFuncDef = ? analyzeFunctionDefinition(fileScope, module, function.def)
    analyzedFuncDefs.add(analyzedFuncDef)

  ok(newAnalyzedDefModule(module, requires, maybeAnalyzedData, analyzedFuncDefs))

proc analyzeGeneric*(fileScope: ResolvedFileScope, generic: ResolvedGeneric): Result[AnalyzedGeneric, string] =
  var analyzedFuncDefs: seq[AnalyzedFunctionDefinition]
  for funcDef in generic.funcDefs:
    let analyzedFuncDef = ? analyzeFunctionDefinition(fileScope, generic, funcDef)
    analyzedFuncDefs.add(analyzedFuncDef)
  ok(newAnalyzedGeneric(generic, analyzedFuncDefs))

# ============================================================
# Phase-A defined-type dispatcher (W5 of plan_analyzer_two_pass.md).
# Ported from oldanalyzer.nim:847.
# ============================================================

proc analyzeType*(fileScope: ResolvedFileScope, definedType: ResolvedType): Result[AnalyzedType, string] =
  case definedType.kind:
  of rtkGeneric:
    let analyzedGeneric = ? analyzeGeneric(fileScope, definedType.generic)
    ok(newAnalyzedType(analyzedGeneric))
  of rtkModule:
    let analyzedModule = ? analyzeModuleDefinition(fileScope, definedType.module)
    ok(newAnalyzedType(analyzedModule))

proc analyzeImportedType*(impFile: ResolvedFile, impType: ResolvedImportedType): Result[AnalyzedDefImportedType, string] =
  let resolvedImpType = ? impFile.findType(impType.typ, impType.loc)
  ok(newAnalyzedDefImportedType(impType, resolvedImpType))

proc analyzeImportDefinition*(app: ResolvedApp, imp: ResolvedImport): Result[AnalyzedDefImport, string] =
  let impFile = ? app.findFile(imp.impFile)
  var analyzedImpTypes: seq[AnalyzedDefImportedType]
  for impType in imp.importedTypes:
    let analyzedImportedType = ? analyzeImportedType(impFile, impType)
    analyzedImpTypes.add(analyzedImportedType)
  ok(newAnalyzedDefImport(imp, analyzedImpTypes))

proc analyzeFileDefinition*(app: ResolvedApp, file: ResolvedFile): Result[AnalyzedDefFile, string] =
  var analyzedImports: seq[AnalyzedDefImport]
  for imp in file.imports:
    let analyzedImport = ? analyzeImportDefinition(app, imp)
    analyzedImports.add(analyzedImport)

  let fileScope = ? newResolvedFileScope(analyzedImports, file.types)
  var analyzedTypes: seq[AnalyzedType]
  for typ in file.types:
    let analyzedType = ? analyzeType(fileScope, typ)
    analyzedTypes.add(analyzedType)
  ok(newAnalyzedDefFile(file, analyzedImports, analyzedTypes, fileScope))

# ============================================================
# Phase-A app dispatcher (W7 of plan_analyzer_two_pass.md).
# Ported from oldanalyzer.nim:987. Walks every file, produces the
# per-app definition bundle. Not yet consumed by the top-level
# `analyze*` entry — that switches to two-pass orchestration at W8.
# ============================================================

proc analyzeAppDefinition*(app: ResolvedApp): Result[AnalyzedDefApp, string] =
  var analyzedFileDefinitions: seq[AnalyzedDefFile]
  for file in app.files:
    let analyzedFileDefinition = ? analyzeFileDefinition(app, file)
    analyzedFileDefinitions.add(analyzedFileDefinition)
  ok(newAnalyzedDefApp(app, analyzedFileDefinitions))
