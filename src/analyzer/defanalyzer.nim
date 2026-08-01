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

import ./defanalyzer/structref
export structref

import ./defanalyzer/unionref
export unionref

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

# The whole argtype cluster is context-free on purpose — no
# module/generic context parameters and no context twins. The resolver
# already enforces every context-sensitive rule at resolve time: a
# generic block may only reference its own type parameter
# (resolveGenericArgumentType errs on any other generic), and module
# argument types are validated against the file scope when resolved.
# So by the time phase A walks a def, every reference is known-valid —
# re-deriving the analyzed binding needs only the file scope, and a
# failed lookup is a compiler bug, never a user error.
proc analyzeDefGenericArgumentType(fileScope: ResolvedFileScope, genericArgType: ResolvedGenericArgumentType): Result[AnalyzedGenericArgumentType, string] =
  let maybeGeneric = fileScope.findGeneric(genericArgType.parsed, genericArgType.loc)
  assert(maybeGeneric.isOk, "[BUG] - Resolver ensures that the generic referenced by an argument type exists")
  ok(newAnalyzedGenericArgumentType(maybeGeneric.get, genericArgType.loc))

proc analyzeDefArgumentType*(fileScope: ResolvedFileScope, argType: ResolvedArgumentType): Result[AnalyzedArgumentType, string]

proc analyzeDefModuleArgumentType(fileScope: ResolvedFileScope, argType: ResolvedModuleArgumentType): Result[AnalyzedModuleArgumentType, string] =
  let maybeModule = fileScope.findModule(argType.module, argType.loc)
  assert(maybeModule.isOk, "[BUG] - Resolver ensures that the argument type module exists")
  var analyzedImpls: seq[AnalyzedArgumentType]
  for impl in argType.impls:
    let analyzedImpl = ? analyzeDefArgumentType(fileScope, impl)
    analyzedImpls.add(analyzedImpl)
  ok(newAnalyzedModuleArgumentType(argType, maybeModule.get, analyzedImpls))

proc analyzeDefArgumentType*(fileScope: ResolvedFileScope, argType: ResolvedArgumentType): Result[AnalyzedArgumentType, string] =
  case argType.kind:
  of ratkGeneric:
    let analyzedArgType = ? analyzeDefGenericArgumentType(fileScope, argType.generic)
    ok(newAnalyzedArgumentType(analyzedArgType))
  of ratkModule:
    let analyzedArgType = ? analyzeDefModuleArgumentType(fileScope, argType.module)
    ok(newAnalyzedArgumentType(analyzedArgType))

# ============================================================
# Phase-A argument / function def analyzers (W2 of
# plans/plan_analyzer_two_pass.md). Ported from the retired
# oldanalyzer.nim.
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

proc analyzeDefArgumentDefinition(fileScope: ResolvedFileScope, argDef: ResolvedArgumentDef): Result[AnalyzedArgumentDefinition, string] =
  let analyzedArgType = ? analyzeDefArgumentType(fileScope, argDef.argType)
  ok(newAnalyzedArgumentDefinition(argDef, analyzedArgType))

proc analyzeDefFunctionDefinition(fileScope: ResolvedFileScope, funcDef: ResolvedFunctionDef): Result[AnalyzedFunctionDefinition, string] =
  var analyzedArgDefs: seq[AnalyzedArgumentDefinition]
  for arg in funcDef.args:
    let analyzedArgDef = ? analyzeDefArgumentDefinition(fileScope, arg)
    analyzedArgDefs.add(analyzedArgDef)
  let analyzedReturns = ? analyzeDefArgumentType(fileScope, funcDef.returns)
  ok(newAnalyzedFunctionDefinition(funcDef, analyzedArgDefs, analyzedReturns))

proc analyzeDefStruct(fileScope: ResolvedFileScope, struct: ResolvedStructDef): Result[AnalyzedStructDef, string] =
  var analyzedFields: seq[AnalyzedArgumentDefinition]
  for field in struct.fields:
    let analyzedField = ? analyzeDefArgumentDefinition(fileScope, field)
    analyzedFields.add(analyzedField)
  ok(newAnalyzedStructDef(struct, analyzedFields))

proc analyzeDefVariant(fileScope: ResolvedFileScope, variant: ResolvedVariant): Result[AnalyzedVariantDef, string] =
  var analyzedFields: seq[AnalyzedArgumentDefinition]
  for field in variant.fields:
    let analyzedField = ? analyzeDefArgumentDefinition(fileScope, field)
    analyzedFields.add(analyzedField)
  ok(newAnalyzedVariantDef(variant, analyzedFields))

proc analyzeDefUnion(fileScope: ResolvedFileScope, union: ResolvedUnionDef): Result[AnalyzedUnionDef, string] =
  var analyzedVariants: seq[AnalyzedVariantDef]
  for variant in union.variants:
    let analyzedVariant = ? analyzeDefVariant(fileScope, variant)
    analyzedVariants.add(analyzedVariant)
  ok(newAnalyzedUnionDef(union, analyzedVariants))

proc analyzeDefData(fileScope: ResolvedFileScope, data: ResolvedData): Result[AnalyzedData, string] =
  case data.kind:
  of rdkLiteral:
    ok(newAnalyzedData(newAnalyzedLiteralDef(data.literal)))
  of rdkStruct:
    let analyzedStruct = ? analyzeDefStruct(fileScope, data.struct)
    ok(newAnalyzedData(analyzedStruct))
  of rdkUnion:
    let analyzedUnion = ? analyzeDefUnion(fileScope, data.union)
    ok(newAnalyzedData(analyzedUnion))

proc analyzeDefUnionRef(fileScope: ResolvedFileScope, unionRef: ResolvedUnionRef): Result[AnalyzedDefUnionRef, string] =
  let maybeUnionModule = fileScope.findModule(unionRef.module, unionRef.loc)
  assert(maybeUnionModule.isOk, "[BUG] - Resolver ensures that the union ref module exists")
  let unionModule = maybeUnionModule.get
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
    let analyzedArgType = ? analyzeDefModuleArgumentType(fileScope, unionRef.argType)
    ok(newAnalyzedDefUnionRef(unionRef, analyzedArgType, union, variant))

proc analyzeDefStructRef(fileScope: ResolvedFileScope, structRef: ResolvedStructRef): Result[AnalyzedDefStructRef, string] =
  let maybeStructModule = fileScope.findModule(structRef.module, structRef.loc)
  assert(maybeStructModule.isOk, "[BUG] - Resolver ensures that the struct ref module exists")
  let structModule = maybeStructModule.get
  assert(structModule.data.isSome, "[BUG] - Resolver ensures that struct ref module has a data block")
  assert(structModule.data.get.kind == rdkStruct, "[BUG] - Resolver ensures that struct ref module has a struct block")
  let struct = structModule.data.get.struct
  if structRef.argType.impls.len == 0:
    ok(newAnalyzedDefStructRef(structRef, structModule, struct))
  else:
    let analyzedArgType = ? analyzeDefModuleArgumentType(fileScope, structRef.argType)
    ok(newAnalyzedDefStructRef(structRef, analyzedArgType, struct))

proc analyzeDefStatement(fileScope: ResolvedFileScope, statement: ResolvedStatement): Result[AnalyzedDefStatement, string]
proc analyzeDefExpression(fileScope: ResolvedFileScope, expression: ResolvedExpression): Result[AnalyzedDefExpression, string]

proc analyzeDefBareLiteral(fileScope: ResolvedFileScope, literal: ResolvedLiteral): Result[AnalyzedDefLiteral, string] =
  let maybeLiteralModule = fileScope.findModule(literal.default, literal.loc)
  assert(maybeLiteralModule.isOk, "[BUG] - Resolver ensures that the literal default module exists")
  let literalModule = maybeLiteralModule.get
  assert(literalModule.data.isSome, "[BUG] - Resolver ensures that literal module has a data block")
  assert(literalModule.data.get.kind == rdkLiteral, "[BUG] - Resolver ensures that literal module has a literal block")
  ok(newAnalyzedDefLiteral(literal, literalModule, literalModule.data.get.literal))

proc analyzeDefCase(fileScope: ResolvedFileScope, caseBlock: ResolvedCaseBlock): Result[AnalyzedDefCase, string] =
  var statements: seq[AnalyzedDefStatement]
  for statement in caseBlock.statements:
    let analyzedDefStatement = ? analyzeDefStatement(fileScope, statement)
    statements.add(analyzedDefStatement)
  ok(newAnalyzedDefCase(caseBlock, statements))

proc analyzeDefMatch(fileScope: ResolvedFileScope, match: ResolvedMatchExpression): Result[AnalyzedDefMatch, string] =
  let subject = ? analyzeDefExpression(fileScope, match.subject)

  var cases: seq[AnalyzedDefCase]
  for caseBlock in match.cases:
    let analyzedDefCase = ? analyzeDefCase(fileScope, caseBlock)
    cases.add(analyzedDefCase)
  ok(newAnalyzedDefMatch(match, subject, cases))

proc analyzeDefFunctionCall(fileScope: ResolvedFileScope, fncall: ResolvedFunctionCall): Result[AnalyzedDefFunctionCall, string] =
  let maybeType = fileScope.findType(fncall.typ, fncall.loc)
  assert(maybeType.isOk, "[BUG] - Resolver ensures that the function call receiver type exists")
  let resolvedType = maybeType.get
  var args: seq[AnalyzedDefExpression]
  for arg in fncall.args:
    let analyzedDefArg = ? analyzeDefExpression(fileScope, arg)
    args.add(analyzedDefArg)
  ok(newAnalyzedDefFunctionCall(fncall, resolvedType, args))

proc analyzeDefUnionInitializer(fileScope: ResolvedFileScope, init: ResolvedUnionInitializer): Result[AnalyzedDefUnionInitializer, string] =
  let unionRef = ? analyzeDefUnionRef(fileScope, init.unionRef)
  var kwargs: seq[AnalyzedDefKeywordArgument]
  for kwarg in init.kwargs:
    let analyzedDefExpr = ? analyzeDefExpression(fileScope, kwarg.expression)
    let analyzedDefKwarg = newAnalyzedDefKeywordArgument(kwarg, analyzedDefExpr)
    kwargs.add(analyzedDefKwarg)
  ok(newAnalyzedDefUnionInitializer(init, unionRef, kwargs))

proc analyzeDefStructInitializer(fileScope: ResolvedFileScope, init: ResolvedStructInitializer): Result[AnalyzedDefStructInitializer, string] =
  let structRef = ? analyzeDefStructRef(fileScope, init.structRef)
  var kwargs: seq[AnalyzedDefKeywordArgument]
  for kwarg in init.kwargs:
    let analyzedDefExpr = ? analyzeDefExpression(fileScope, kwarg.expression)
    let analyzedDefKwarg = newAnalyzedDefKeywordArgument(kwarg, analyzedDefExpr)
    kwargs.add(analyzedDefKwarg)
  ok(newAnalyzedDefStructInitializer(init, structRef, kwargs))

proc analyzeDefLiteralInitializer(fileScope: ResolvedFileScope, init: ResolvedLiteralInitializer): Result[AnalyzedDefLiteralInitializer, string] =
  let argType = ? analyzeDefModuleArgumentType(fileScope, init.argType)
  assert(argType.module.data.isSome, "[BUG] - Resolver ensures that literal module has a data block")
  assert(argType.module.data.get.kind == rdkLiteral, "[BUG] - Resolver ensures that literal module has a literal block")
  ok(newAnalyzedDefLiteralInitializer(init, argType, argType.module.data.get.literal))

proc analyzeDefInitializer(fileScope: ResolvedFileScope, init: ResolvedInitializer): Result[AnalyzedDefInitializer, string] =
  case init.kind:
  of rikLiteral:
    let literalInit = ? analyzeDefLiteralInitializer(fileScope, init.literal)
    ok(newAnalyzedDefInitializer(literalInit))
  of rikStruct:
    let structInit = ? analyzeDefStructInitializer(fileScope, init.struct)
    ok(newAnalyzedDefInitializer(structInit))
  of rikUnion:
    let unionInit = ? analyzeDefUnionInitializer(fileScope, init.union)
    ok(newAnalyzedDefInitializer(unionInit))

proc analyzeDefExpression(fileScope: ResolvedFileScope, expression: ResolvedExpression): Result[AnalyzedDefExpression, string] =
  case expression.kind:
  # Variables and getters touch only function-scope names and struct
  # fields — nothing def-level to analyze, so they wrap as-is; phase B
  # checks the field path (see the matching note in analyzeDefSetter).
  of rekVariable:
    ok(newAnalyzedDefExpression(expression.variable))
  of rekGetter:
    ok(newAnalyzedDefExpression(expression.getter))
  of rekLiteral:
    let literal = ? analyzeDefBareLiteral(fileScope, expression.literal)
    ok(newAnalyzedDefExpression(literal))
  of rekFunctionCall:
    let fncall = ? analyzeDefFunctionCall(fileScope, expression.fncall)
    ok(newAnalyzedDefExpression(fncall))
  of rekInitializer:
    let init = ? analyzeDefInitializer(fileScope, expression.init)
    ok(newAnalyzedDefExpression(init))
  of rekMatchExpr:
    let match = ? analyzeDefMatch(fileScope, expression.match)
    ok(newAnalyzedDefExpression(match))

proc analyzeDefAssignment(fileScope: ResolvedFileScope, assignment: ResolvedAssignment): Result[AnalyzedDefAssignment, string] =
  let expression = ? analyzeDefExpression(fileScope, assignment.expression)
  ok(newAnalyzedDefAssignment(assignment, expression))

proc analyzeDefSetter(fileScope: ResolvedFileScope, setter: ResolvedSetter): Result[AnalyzedDefSetter, string] =
  # The getter side is skipped on purpose — same rationale as the
  # rekGetter arm in analyzeDefExpression.
  let expression = ? analyzeDefExpression(fileScope, setter.expression)
  ok(newAnalyzedDefSetter(setter, expression))

proc analyzeDefStatement(fileScope: ResolvedFileScope, statement: ResolvedStatement): Result[AnalyzedDefStatement, string] =
  case statement.kind:
  of rskAssignment:
    let assignment = ? analyzeDefAssignment(fileScope, statement.assignment)
    ok(newAnalyzedDefStatement(assignment))
  of rskExpr:
    let expression = ? analyzeDefExpression(fileScope, statement.expression)
    ok(newAnalyzedDefStatement(expression))
  of rskSetter:
    let setter = ? analyzeDefSetter(fileScope, statement.setter)
    ok(newAnalyzedDefStatement(setter))

proc analyzeDefUserFunction(fileScope: ResolvedFileScope, function: ResolvedUserFunction): Result[AnalyzedDefUserFunction, string] =
  let funcDef = ? analyzeDefFunctionDefinition(fileScope, function.def)
  var statements: seq[AnalyzedDefStatement]
  for statement in function.statements:
    let analyzedDefStatement = ? analyzeDefStatement(fileScope, statement)
    statements.add(analyzedDefStatement)
  ok(newAnalyzedDefUserFunction(function, funcDef, statements))

proc analyzeDefExternFunction(fileScope: ResolvedFileScope, function: ResolvedExternFunction): Result[AnalyzedDefExternFunction, string] =
  let analyzedFuncDef = ? analyzeDefFunctionDefinition(fileScope, function.def)
  ok(newAnalyzedDefExternFunction(function, analyzedFuncDef))

proc analyzeDefFunction(fileScope: ResolvedFileScope, function: ResolvedFunction): Result[AnalyzedDefFunction, string] =
  case function.kind:
  of rfkExtern:
    let analyzedExternFunction = ? analyzeDefExternFunction(fileScope, function.extern)
    ok(newAnalyzedDefFunction(analyzedExternFunction))
  of rfkUser:
    let analyzedUserFunction = ? analyzeDefUserFunction(fileScope, function.user)
    ok(newAnalyzedDefFunction(analyzedUserFunction))


# ============================================================
# Phase-A module + generic analyzers (W4 of plan_analyzer_two_pass.md).
# Ported from the retired oldanalyzer.nim.
#
# Note: `analyzeDefModule`'s requires walk reads
# `module.data.get.requires` (post the resolver's struct-header merge)
# rather than the retired module-level `requires` clause. Modules
# without a data block carry an empty requires seq.
# ============================================================

proc analyzeDefModule(fileScope: ResolvedFileScope, module: ResolvedModule): Result[AnalyzedDefModule, string] =
  var requires: seq[AnalyzedGenericArgumentType]
  if module.data.isSome:
    for genericArgType in module.data.get.requires:
      let analyzedArgType = ? analyzeDefGenericArgumentType(fileScope, genericArgType)
      requires.add(analyzedArgType)

  var maybeAnalyzedData: Option[AnalyzedData]
  if module.data.isSome:
    let analyzedData = ? analyzeDefData(fileScope, module.data.get)
    maybeAnalyzedData = some(analyzedData)

  var analyzedDefFuncs: seq[AnalyzedDefFunction]
  for function in module.functions:
    let analyzedDefFunc = ? analyzeDefFunction(fileScope, function)
    analyzedDefFuncs.add(analyzedDefFunc)

  ok(newAnalyzedDefModule(module, requires, maybeAnalyzedData, analyzedDefFuncs))

proc analyzeDefGeneric(fileScope: ResolvedFileScope, generic: ResolvedGeneric): Result[AnalyzedGeneric, string] =
  var analyzedFuncDefs: seq[AnalyzedFunctionDefinition]
  for funcDef in generic.funcDefs:
    let analyzedFuncDef = ? analyzeDefFunctionDefinition(fileScope, funcDef)
    analyzedFuncDefs.add(analyzedFuncDef)
  ok(newAnalyzedGeneric(generic, analyzedFuncDefs))

# ============================================================
# Phase-A defined-type dispatcher (W5 of plan_analyzer_two_pass.md).
# ============================================================

proc analyzeDefType(fileScope: ResolvedFileScope, definedType: ResolvedType): Result[AnalyzedType, string] =
  case definedType.kind:
  of rtkGeneric:
    let analyzedGeneric = ? analyzeDefGeneric(fileScope, definedType.generic)
    ok(newAnalyzedType(analyzedGeneric))
  of rtkModule:
    let analyzedModule = ? analyzeDefModule(fileScope, definedType.module)
    ok(newAnalyzedType(analyzedModule))

proc analyzeDefImportedType(impFile: ResolvedFile, impType: ResolvedImportedType): Result[AnalyzedDefImportedType, string] =
  let maybeImpType = impFile.findType(impType.typ, impType.loc)
  assert(maybeImpType.isOk, "[BUG] - Resolver ensures that the imported type exists in the imported file")
  ok(newAnalyzedDefImportedType(impType, maybeImpType.get))

proc analyzeDefImport(app: ResolvedApp, imp: ResolvedImport): Result[AnalyzedDefImport, string] =
  let maybeImpFile = app.findFile(imp.impFile)
  assert(maybeImpFile.isOk, "[BUG] - Resolver ensures that the imported file exists in the app")
  let impFile = maybeImpFile.get
  var analyzedImpTypes: seq[AnalyzedDefImportedType]
  for impType in imp.importedTypes:
    let analyzedImportedType = ? analyzeDefImportedType(impFile, impType)
    analyzedImpTypes.add(analyzedImportedType)
  ok(newAnalyzedDefImport(imp, analyzedImpTypes))

proc analyzeDefFile(app: ResolvedApp, file: ResolvedFile): Result[AnalyzedDefFile, string] =
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
# Walks every file, produces the per-app definition bundle. Consumed
# by the top-level `analyze*` entry on the body barrel, which runs
# analyzeDefApp first and then walks the bundle for phase B.
# ============================================================

proc analyzeDefApp*(app: ResolvedApp): Result[AnalyzedDefApp, string] =
  var analyzedFileDefinitions: seq[AnalyzedDefFile]
  for file in app.files:
    let analyzedFileDefinition = ? analyzeDefFile(app, file)
    analyzedFileDefinitions.add(analyzedFileDefinition)
  ok(newAnalyzedDefApp(app, analyzedFileDefinitions))
