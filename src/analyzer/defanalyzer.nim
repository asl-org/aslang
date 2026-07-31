## Definition-analysis barrel — phase A of the two-pass analyzer.
## Hosts the def-level analyze* procs (analyzeDefGenericArgumentType
## through analyzeDefApp) and re-exports every def-level
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

import ./defanalyzer/statement
export statement

import ./defanalyzer/function
export function

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

proc analyzeDefGenericArgumentType*(fileScope: ResolvedFileScope, generic: ResolvedGeneric, genericArgType: ResolvedGenericArgumentType): Result[AnalyzedGenericArgumentType, string] =
  let genericArg = ? fileScope.findGeneric(genericArgType.parsed, genericArgType.loc)
  if genericArg != generic:
    err(fmt"{genericArgType.loc} generic `{genericArgType.parsed.name.asl}` does not exist")
  else:
    ok(newAnalyzedGenericArgumentType(genericArg, genericArgType.loc))

proc analyzeDefGenericArgumentType*(fileScope: ResolvedFileScope, genericArgType: ResolvedGenericArgumentType): Result[AnalyzedGenericArgumentType, string] =
  let genericArg = ? fileScope.findGeneric(genericArgType.parsed, genericArgType.loc)
  ok(newAnalyzedGenericArgumentType(genericArg, genericArgType.loc))

proc analyzeDefArgumentType*(fileScope: ResolvedFileScope, module: ResolvedModule, argType: ResolvedArgumentType): Result[AnalyzedArgumentType, string]
proc analyzeDefArgumentType*(fileScope: ResolvedFileScope, generic: ResolvedGeneric, argType: ResolvedArgumentType): Result[AnalyzedArgumentType, string]

proc analyzeDefModuleArgumentType*(fileScope: ResolvedFileScope, module: ResolvedModule, argType: ResolvedModuleArgumentType): Result[AnalyzedModuleArgumentType, string] =
  let typeModule = ? fileScope.findModule(argType.module, argType.loc)
  var analyzedImpls: seq[AnalyzedArgumentType]
  for impl in argType.impls:
    let analyzedImpl = ? analyzeDefArgumentType(fileScope, module, impl)
    analyzedImpls.add(analyzedImpl)
  ok(newAnalyzedModuleArgumentType(argType, typeModule, analyzedImpls))

proc analyzeDefModuleArgumentType*(fileScope: ResolvedFileScope, generic: ResolvedGeneric, argType: ResolvedModuleArgumentType): Result[AnalyzedModuleArgumentType, string] =
  let typeModule = ? fileScope.findModule(argType.module, argType.loc)
  var analyzedImpls: seq[AnalyzedArgumentType]
  for impl in argType.impls:
    let analyzedImpl = ? analyzeDefArgumentType(fileScope, generic, impl)
    analyzedImpls.add(analyzedImpl)
  ok(newAnalyzedModuleArgumentType(argType, typeModule, analyzedImpls))

proc analyzeDefArgumentType*(fileScope: ResolvedFileScope, module: ResolvedModule, argType: ResolvedArgumentType): Result[AnalyzedArgumentType, string] =
  case argType.kind:
  of ratkGeneric:
    let analyzedArgType = ? analyzeDefGenericArgumentType(fileScope, argType.generic)
    ok(newAnalyzedArgumentType(analyzedArgType))
  of ratkModule:
    let analyzedArgType = ? analyzeDefModuleArgumentType(fileScope, module, argType.module)
    ok(newAnalyzedArgumentType(analyzedArgType))

proc analyzeDefArgumentType*(fileScope: ResolvedFileScope, generic: ResolvedGeneric, argType: ResolvedArgumentType): Result[AnalyzedArgumentType, string] =
  case argType.kind:
  of ratkGeneric:
    let analyzedArgType = ? analyzeDefGenericArgumentType(fileScope, generic, argType.generic)
    ok(newAnalyzedArgumentType(analyzedArgType))
  of ratkModule:
    let analyzedArgType = ? analyzeDefModuleArgumentType(fileScope, generic, argType.module)
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

proc analyzeDefArgumentDefinition*(fileScope: ResolvedFileScope, module: ResolvedModule, argDef: ResolvedArgumentDef): Result[AnalyzedArgumentDefinition, string] =
  let analyzedArgType = ? analyzeDefArgumentType(fileScope, module, argDef.argType)
  ok(newAnalyzedArgumentDefinition(argDef, analyzedArgType))

proc analyzeDefArgumentDefinition*(fileScope: ResolvedFileScope, generic: ResolvedGeneric, argDef: ResolvedArgumentDef): Result[AnalyzedArgumentDefinition, string] =
  let analyzedArgType = ? analyzeDefArgumentType(fileScope, generic, argDef.argType)
  ok(newAnalyzedArgumentDefinition(argDef, analyzedArgType))

proc analyzeDefFunctionDefinition*(fileScope: ResolvedFileScope, module: ResolvedModule, funcDef: ResolvedFunctionDef): Result[AnalyzedFunctionDefinition, string] =
  var analyzedArgDefs: seq[AnalyzedArgumentDefinition]
  for arg in funcDef.args:
    let analyzedArgDef = ? analyzeDefArgumentDefinition(fileScope, module, arg)
    analyzedArgDefs.add(analyzedArgDef)
  let analyzedReturns = ? analyzeDefArgumentType(fileScope, module, funcDef.returns)
  ok(newAnalyzedFunctionDefinition(funcDef, analyzedArgDefs, analyzedReturns))

proc analyzeDefFunctionDefinition*(fileScope: ResolvedFileScope, generic: ResolvedGeneric, funcDef: ResolvedFunctionDef): Result[AnalyzedFunctionDefinition, string] =
  var analyzedArgDefs: seq[AnalyzedArgumentDefinition]
  for arg in funcDef.args:
    let analyzedArgDef = ? analyzeDefArgumentDefinition(fileScope, generic, arg)
    analyzedArgDefs.add(analyzedArgDef)
  let analyzedReturns = ? analyzeDefArgumentType(fileScope, generic, funcDef.returns)
  ok(newAnalyzedFunctionDefinition(funcDef, analyzedArgDefs, analyzedReturns))

proc analyzeDefStruct*(fileScope: ResolvedFileScope, module: ResolvedModule, struct: ResolvedStructDef): Result[AnalyzedStructDef, string] =
  var analyzedFields: seq[AnalyzedArgumentDefinition]
  for field in struct.fields:
    let analyzedField = ? analyzeDefArgumentDefinition(fileScope, module, field)
    analyzedFields.add(analyzedField)
  ok(newAnalyzedStructDef(struct, analyzedFields))

proc analyzeDefVariant*(fileScope: ResolvedFileScope, module: ResolvedModule, variant: ResolvedVariant): Result[AnalyzedVariantDef, string] =
  var analyzedFields: seq[AnalyzedArgumentDefinition]
  for field in variant.fields:
    let analyzedField = ? analyzeDefArgumentDefinition(fileScope, module, field)
    analyzedFields.add(analyzedField)
  ok(newAnalyzedVariantDef(variant, analyzedFields))

proc analyzeDefUnion*(fileScope: ResolvedFileScope, module: ResolvedModule, union: ResolvedUnionDef): Result[AnalyzedUnionDef, string] =
  var analyzedVariants: seq[AnalyzedVariantDef]
  for variant in union.variants:
    let analyzedVariant = ? analyzeDefVariant(fileScope, module, variant)
    analyzedVariants.add(analyzedVariant)
  ok(newAnalyzedUnionDef(union, analyzedVariants))

proc analyzeDefData*(fileScope: ResolvedFileScope, module: ResolvedModule, data: ResolvedData): Result[AnalyzedData, string] =
  case data.kind:
  of rdkLiteral:
    ok(newAnalyzedData(newAnalyzedLiteralDef(data.literal)))
  of rdkStruct:
    let analyzedStruct = ? analyzeDefStruct(fileScope, module, data.struct)
    ok(newAnalyzedData(analyzedStruct))
  of rdkUnion:
    let analyzedUnion = ? analyzeDefUnion(fileScope, module, data.union)
    ok(newAnalyzedData(analyzedUnion))

proc analyzeDefStatement(fileScope: ResolvedFileScope, module: ResolvedModule, statement: ResolvedStatement): Result[void, string]
proc analyzeDefExpression(fileScope: ResolvedFileScope, module: ResolvedModule, expression: ResolvedExpression): Result[void, string]

proc analyzeDefBareLiteral(fileScope: ResolvedFileScope, module: ResolvedModule, literal: ResolvedLiteral): Result[void, string] =
  let defaultLiteralResolvedModule = ? fileScope.findModule(literal.default, literal.loc)
  ok()

proc analyzeDefCasePattern(fileScope: ResolvedFileScope, module: ResolvedModule, pattern: ResolvedCasePattern): Result[void, string] =
  ## Deliberately empty — validating a union pattern's variant/field
  ## names needs the match subject's union type, which only phase B
  ## computes (the subject is an expression whose type isn't known at
  ## def level). `analyzeUnionCasePattern` on the body barrel owns
  ## that check.
  ok()

proc analyzeDefCase(fileScope: ResolvedFileScope, module: ResolvedModule, caseBlock: ResolvedCaseBlock): Result[void, string] =
  ? analyzeDefCasePattern(fileScope, module, caseBlock.pattern)
  for statement in caseBlock.statements:
    ? analyzeDefStatement(fileScope, module, statement)
  ok()

proc analyzeDefMatch(fileScope: ResolvedFileScope, module: ResolvedModule, match: ResolvedMatchExpression): Result[void, string] =
  ? analyzeDefExpression(fileScope, module, match.subject)
  for caseBlock in match.cases:
    ? analyzeDefCase(fileScope, module, caseBlock)
  ok()

proc analyzeDefFunctionCall(fileScope: ResolvedFileScope, module: ResolvedModule, fncall: ResolvedFunctionCall): Result[void, string] =
  let resolvedType = ? fileScope.findType(fncall.typ, fncall.loc)
  for arg in fncall.args:
    ? analyzeDefExpression(fileScope, module, arg)
  ok()

proc analyzeDefUnionRef(fileScope: ResolvedFileScope, module: ResolvedModule, unionRef: ResolvedUnionRef): Result[AnalyzedDefUnionRef, string] =
  let unionModule = ? fileScope.findModule(unionRef.module, unionRef.loc)
  assert(unionModule.data.isSome, "[BUG] - Resolver ensures that union ref module has a data block")
  assert(unionModule.data.get.kind == rdkUnion, "[BUG] - Resolver ensures that union ref module has a union block")
  let union = unionModule.data.get.union
  # The resolver already located this variant on the parser-side
  # union; the same name cannot miss on the resolved twin.
  let maybeVariant = union.findVariant(unionRef.variant.name)
  assert(maybeVariant.isOk, "[BUG] - Resolver ensures that the union ref variant exists")
  let variant = maybeVariant.get
  if unionRef.argType.impls.len == 0:
    ok(newAnalyzedDefUnionRef(unionRef, unionModule, union, variant))
  else:
    let analyzedArgType = ? analyzeDefModuleArgumentType(fileScope, module, unionRef.argType)
    ok(newAnalyzedDefUnionRef(unionRef, analyzedArgType, union, variant))

proc analyzeDefStructRef(fileScope: ResolvedFileScope, module: ResolvedModule, structRef: ResolvedStructRef): Result[AnalyzedDefStructRef, string] =
  let structModule = ? fileScope.findModule(structRef.module, structRef.loc)
  assert(structModule.data.isSome, "[BUG] - Resolver ensures that struct ref module has a data block")
  assert(structModule.data.get.kind == rdkStruct, "[BUG] - Resolver ensures that struct ref module has a struct block")
  let struct = structModule.data.get.struct
  if structRef.argType.impls.len == 0:
    ok(newAnalyzedDefStructRef(structRef, structModule, struct))
  else:
    let analyzedArgType = ? analyzeDefModuleArgumentType(fileScope, module, structRef.argType)
    ok(newAnalyzedDefStructRef(structRef, analyzedArgType, struct))

proc analyzeDefUnionInitializer(fileScope: ResolvedFileScope, module: ResolvedModule, init: ResolvedUnionInitializer): Result[void, string] =
  let analyzedDefUnionRef = ? analyzeDefUnionRef(fileScope, module, init.unionRef)
  for kwarg in init.kwargs:
    ? analyzeDefExpression(fileScope, module, kwarg.expression)
  ok()

proc analyzeDefStructInitializer(fileScope: ResolvedFileScope, module: ResolvedModule, init: ResolvedStructInitializer): Result[void, string] =
  let analyzedDefStructRef = ? analyzeDefStructRef(fileScope, module, init.structRef)
  for kwarg in init.kwargs:
    ? analyzeDefExpression(fileScope, module, kwarg.expression)
  ok()

proc analyzeDefLiteralInitializer(fileScope: ResolvedFileScope, module: ResolvedModule, init: ResolvedLiteralInitializer): Result[void, string] =
  let analyzedArgType = ? analyzeDefModuleArgumentType(fileScope, module, init.argType)
  ok()

proc analyzeDefInitializer(fileScope: ResolvedFileScope, module: ResolvedModule, init: ResolvedInitializer): Result[void, string] =
  case init.kind:
  of rikLiteral: analyzeDefLiteralInitializer(fileScope, module, init.literal)
  of rikStruct: analyzeDefStructInitializer(fileScope, module, init.struct)
  of rikUnion: analyzeDefUnionInitializer(fileScope, module, init.union)

proc analyzeDefExpression(fileScope: ResolvedFileScope, module: ResolvedModule, expression: ResolvedExpression): Result[void, string] =
  case expression.kind:
  # Variables and getters touch only function-scope names and struct
  # fields — nothing def-level to validate; phase B checks the field
  # path (see the matching skip in analyzeDefSetter).
  of rekVariable, rekGetter: ok()
  of rekLiteral: analyzeDefBareLiteral(fileScope, module, expression.literal)
  of rekFunctionCall: analyzeDefFunctionCall(fileScope, module, expression.fncall)
  of rekInitializer: analyzeDefInitializer(fileScope, module, expression.init)
  of rekMatchExpr: analyzeDefMatch(fileScope, module, expression.match)

proc analyzeDefAssignment(fileScope: ResolvedFileScope, module: ResolvedModule, assignment: ResolvedAssignment): Result[void, string] =
  ? analyzeDefExpression(fileScope, module, assignment.expression)
  ok()

proc analyzeDefSetter(fileScope: ResolvedFileScope, module: ResolvedModule, setter: ResolvedSetter): Result[void, string] =
  # The getter side is skipped on purpose — same rationale as the
  # rekGetter arm in analyzeDefExpression.
  ? analyzeDefExpression(fileScope, module, setter.expression)
  ok()

proc analyzeDefStatement(fileScope: ResolvedFileScope, module: ResolvedModule, statement: ResolvedStatement): Result[void, string] =
  case statement.kind:
  of rskAssignment: analyzeDefAssignment(fileScope, module, statement.assignment)
  of rskExpr: analyzeDefExpression(fileScope, module, statement.expression)
  of rskSetter: analyzeDefSetter(fileScope, module, statement.setter)

proc analyzeDefUserFunction(fileScope: ResolvedFileScope, module: ResolvedModule, function: ResolvedUserFunction): Result[AnalyzedDefUserFunction, string] =
  let analyzedFuncDef = ? analyzeDefFunctionDefinition(fileScope, module, function.def)
  for statement in function.statements:
    ? analyzeDefStatement(fileScope, module, statement)
  ok(newAnalyzedDefUserFunction(function, analyzedFuncDef))

proc analyzeDefExternFunction(fileScope: ResolvedFileScope, module: ResolvedModule, function: ResolvedExternFunction): Result[AnalyzedDefExternFunction, string] =
  let analyzedFuncDef = ? analyzeDefFunctionDefinition(fileScope, module, function.def)
  ok(newAnalyzedDefExternFunction(function, analyzedFuncDef))

proc analyzeDefFunction(fileScope: ResolvedFileScope, module: ResolvedModule, function: ResolvedFunction): Result[AnalyzedDefFunction, string] =
  case function.kind:
  of rfkExtern:
    let analyzedExternFunction = ? analyzeDefExternFunction(fileScope, module, function.extern)
    ok(newAnalyzedDefFunction(analyzedExternFunction))
  of rfkUser:
    let analyzedUserFunction = ? analyzeDefUserFunction(fileScope, module, function.user)
    ok(newAnalyzedDefFunction(analyzedUserFunction))


# ============================================================
# Phase-A module + generic analyzers (W4 of plan_analyzer_two_pass.md).
# Ported from oldanalyzer.nim:763 (analyzeDefModule) and :811
# (analyzeGeneric).
#
# Note: `analyzeDefModule`'s requires walk reads
# `module.data.get.requires` (post the resolver's struct-header merge)
# rather than the retired module-level `requires` clause. Modules
# without a data block carry an empty requires seq.
# ============================================================

proc analyzeDefModule*(fileScope: ResolvedFileScope, module: ResolvedModule): Result[AnalyzedDefModule, string] =
  var requires: seq[AnalyzedGenericArgumentType]
  if module.data.isSome:
    for genericArgType in module.data.get.requires:
      let analyzedArgType = ? analyzeDefGenericArgumentType(fileScope, genericArgType)
      requires.add(analyzedArgType)

  var maybeAnalyzedData: Option[AnalyzedData]
  if module.data.isSome:
    let analyzedData = ? analyzeDefData(fileScope, module, module.data.get)
    maybeAnalyzedData = some(analyzedData)

  var analyzedDefFuncs: seq[AnalyzedDefFunction]
  for function in module.functions:
    let analyzedDefFunc = ? analyzeDefFunction(fileScope, module, function)
    analyzedDefFuncs.add(analyzedDefFunc)

  ok(newAnalyzedDefModule(module, requires, maybeAnalyzedData, analyzedDefFuncs))

proc analyzeDefGeneric*(fileScope: ResolvedFileScope, generic: ResolvedGeneric): Result[AnalyzedGeneric, string] =
  var analyzedFuncDefs: seq[AnalyzedFunctionDefinition]
  for funcDef in generic.funcDefs:
    let analyzedFuncDef = ? analyzeDefFunctionDefinition(fileScope, generic, funcDef)
    analyzedFuncDefs.add(analyzedFuncDef)
  ok(newAnalyzedGeneric(generic, analyzedFuncDefs))

# ============================================================
# Phase-A defined-type dispatcher (W5 of plan_analyzer_two_pass.md).
# Ported from oldanalyzer.nim:847.
# ============================================================

proc analyzeDefType*(fileScope: ResolvedFileScope, definedType: ResolvedType): Result[AnalyzedType, string] =
  case definedType.kind:
  of rtkGeneric:
    let analyzedGeneric = ? analyzeDefGeneric(fileScope, definedType.generic)
    ok(newAnalyzedType(analyzedGeneric))
  of rtkModule:
    let analyzedModule = ? analyzeDefModule(fileScope, definedType.module)
    ok(newAnalyzedType(analyzedModule))

proc analyzeDefImportedType*(impFile: ResolvedFile, impType: ResolvedImportedType): Result[AnalyzedDefImportedType, string] =
  let resolvedImpType = ? impFile.findType(impType.typ, impType.loc)
  ok(newAnalyzedDefImportedType(impType, resolvedImpType))

proc analyzeDefImport*(app: ResolvedApp, imp: ResolvedImport): Result[AnalyzedDefImport, string] =
  let impFile = ? app.findFile(imp.impFile)
  var analyzedImpTypes: seq[AnalyzedDefImportedType]
  for impType in imp.importedTypes:
    let analyzedImportedType = ? analyzeDefImportedType(impFile, impType)
    analyzedImpTypes.add(analyzedImportedType)
  ok(newAnalyzedDefImport(imp, analyzedImpTypes))

proc analyzeDefFile*(app: ResolvedApp, file: ResolvedFile): Result[AnalyzedDefFile, string] =
  var analyzedImports: seq[AnalyzedDefImport]
  for imp in file.imports:
    let analyzedImport = ? analyzeDefImport(app, imp)
    analyzedImports.add(analyzedImport)

  let fileScope = ? newResolvedFileScope(analyzedImports, file.types)
  var analyzedTypes: seq[AnalyzedType]
  for typ in file.types:
    let analyzedType = ? analyzeDefType(fileScope, typ)
    analyzedTypes.add(analyzedType)
  ok(newAnalyzedDefFile(file, analyzedImports, analyzedTypes, fileScope))

# ============================================================
# Phase-A app dispatcher (W7 of plan_analyzer_two_pass.md).
# Ported from oldanalyzer.nim:987. Walks every file, produces the
# per-app definition bundle. Not yet consumed by the top-level
# `analyze*` entry — that switches to two-pass orchestration at W8.
# ============================================================

proc analyzeDefApp*(app: ResolvedApp): Result[AnalyzedDefApp, string] =
  var analyzedFileDefinitions: seq[AnalyzedDefFile]
  for file in app.files:
    let analyzedFileDefinition = ? analyzeDefFile(app, file)
    analyzedFileDefinitions.add(analyzedFileDefinition)
  ok(newAnalyzedDefApp(app, analyzedFileDefinitions))
