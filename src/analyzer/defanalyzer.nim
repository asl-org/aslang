## Definition-analysis barrel — phase A of the two-pass analyzer.
## Hosts the def-level analyze* procs (analyzeDefGenericArgumentType
## through analyzeDefApp) and re-exports every def-level
## analyzed type plus the resolver layer beneath, so the body layer
## (src/analyzer.nim + src/analyzer/) says `import ./defanalyzer`
## once. Nesting convention: parser ⊂ resolver ⊂ defanalyzer ⊂
## analyzer.

import options, results, sequtils, strformat

import ./defanalyzer/resolver
export resolver

import ./defanalyzer/filecontext
export filecontext

import ./defanalyzer/typecontext
export typecontext

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

# The argtype cluster carries a ResolvedTypeContext for exactly one
# decision: function visibility during the deep constraint-
# satisfaction check (which functions of an impl module the context
# may see). Everything else stays resolver-guaranteed: the generic
# self-reference rule and name/arity/accessibility presence are
# enforced at resolve time (TypeContext there), so a failed lookup
# here is a compiler bug, never a user error — and there are no
# module/generic context twins; one context value, one proc.
proc analyzeDefGenericArgumentType(fileCtx: ResolvedFileContext, genericArgType: ResolvedGenericArgumentType): Result[AnalyzedGenericArgumentType, string] =
  let maybeGeneric = fileCtx.findGeneric(genericArgType.generic, genericArgType.loc)
  assert(maybeGeneric.isOk, "[BUG] - Resolver ensures that the generic referenced by an argument type exists")
  ok(newAnalyzedGenericArgumentType(maybeGeneric.get, genericArgType.loc))

proc analyzeDefArgumentType*(fileCtx: ResolvedFileContext, typeCtx: ResolvedTypeContext, argType: ResolvedArgumentType): Result[AnalyzedArgumentType, string]

proc analyzeDefModuleArgumentType(fileCtx: ResolvedFileContext, typeCtx: ResolvedTypeContext, argType: ResolvedModuleArgumentType): Result[AnalyzedModuleArgumentType, string] =
  let maybeModule = fileCtx.findModule(argType.module, argType.loc)
  assert(maybeModule.isOk, "[BUG] - Resolver ensures that the argument type module exists")
  let module = maybeModule.get
  assert(module.data.isSome, "[BUG] - Resolver ensures that argument type modules are data modules")

  let requires = module.data.get.requires
  assert(requires.len == argType.impls.len, "[BUG] - Resolver ensures impls match the module's require slots")

  var analyzedImpls: seq[AnalyzedArgumentType]
  for (requirement, impl) in zip(requires, argType.impls):
    let analyzedImpl = ? analyzeDefArgumentType(fileCtx, typeCtx, impl)
    analyzedImpls.add(analyzedImpl)
    # The require-slot generic resolves through THIS file's scope — the
    # resolver already found it here by name (inferGenerics), so the
    # identity lookup cannot miss.
    let maybeBaseGeneric = fileCtx.findGeneric(requirement.generic, requirement.loc)
    assert(maybeBaseGeneric.isOk, "[BUG] - Resolver ensures that the require-slot generic is in the file scope")
    let baseGeneric = maybeBaseGeneric.get
    # Contracts compare at DEFINITION level: self-references become the
    # impl's self shape (`Array[Comparable]`, not the site-bound
    # `Array[u8]`) so the concretized defs land in the impl's own
    # vocabulary and the identity probe below can hit its funcDefIndex.
    # The site-bound impls were already validated by the recursive
    # analyzeDefArgumentType call above.
    for def in baseGeneric.concrete(analyzedImpl.self):
      let maybeMatchingDef =
        case analyzedImpl.kind:
        of aatkModule:
          let resolvedImplModule = analyzedImpl.module.module
          resolvedImplModule.findImplDef(def, typeCtx.access(resolvedImplModule))
        of aatkGeneric:
          let resolvedImplGeneric = analyzedImpl.generic.resolved
          resolvedImplGeneric.findImplDef(def, faAll)
      if maybeMatchingDef.isErr:
        return err(fmt"{impl.loc} type `{impl.asl}` does not implement `{def.asl}` to support `{baseGeneric.name.asl}`")

  ok(newAnalyzedModuleArgumentType(argType, module, analyzedImpls))

proc analyzeDefArgumentType*(fileCtx: ResolvedFileContext, typeCtx: ResolvedTypeContext, argType: ResolvedArgumentType): Result[AnalyzedArgumentType, string] =
  case argType.kind:
  of ratkGeneric:
    let analyzedArgType = ? analyzeDefGenericArgumentType(fileCtx, argType.generic)
    ok(newAnalyzedArgumentType(analyzedArgType))
  of ratkModule:
    let analyzedArgType = ? analyzeDefModuleArgumentType(fileCtx, typeCtx, argType.module)
    ok(newAnalyzedArgumentType(analyzedArgType))

# ============================================================
# Phase-A argument / function def analyzers (W2 of
# plans/plan_analyzer_two_pass.md). Ported from the retired
# oldanalyzer.nim.
#
# Def-time constraint checks compare by identity soundly: the deep
# `concrete` grounds every self-reference before the funcDefIndex
# probe, so nested positions like `Array[Any]` arrive fully
# substituted. The hash-vs-unification limitation lives in phase B
# only — see the banner above `analyzeValueTypeAgainstDefType` on
# the body barrel.
# ============================================================

proc analyzeDefArgumentDefinition(fileCtx: ResolvedFileContext, typeCtx: ResolvedTypeContext, argDef: ResolvedArgumentDef): Result[AnalyzedArgumentDefinition, string] =
  let analyzedArgType = ? analyzeDefArgumentType(fileCtx, typeCtx, argDef.argType)
  ok(newAnalyzedArgumentDefinition(argDef, analyzedArgType))

proc analyzeDefFunctionDefinition(fileCtx: ResolvedFileContext, typeCtx: ResolvedTypeContext, funcDef: ResolvedFunctionDef): Result[AnalyzedFunctionDefinition, string] =
  var analyzedArgDefs: seq[AnalyzedArgumentDefinition]
  for arg in funcDef.args:
    let analyzedArgDef = ? analyzeDefArgumentDefinition(fileCtx, typeCtx, arg)
    analyzedArgDefs.add(analyzedArgDef)
  let analyzedReturns = ? analyzeDefArgumentType(fileCtx, typeCtx, funcDef.returns)
  ok(newAnalyzedFunctionDefinition(funcDef, analyzedArgDefs, analyzedReturns))

proc analyzeDefStruct(fileCtx: ResolvedFileContext, typeCtx: ResolvedTypeContext, struct: ResolvedStructDef): Result[AnalyzedStructDef, string] =
  var analyzedFields: seq[AnalyzedArgumentDefinition]
  for field in struct.fields:
    let analyzedField = ? analyzeDefArgumentDefinition(fileCtx, typeCtx, field)
    analyzedFields.add(analyzedField)
  ok(newAnalyzedStructDef(struct, analyzedFields))

proc analyzeDefVariant(fileCtx: ResolvedFileContext, typeCtx: ResolvedTypeContext, variant: ResolvedVariant): Result[AnalyzedVariantDef, string] =
  var analyzedFields: seq[AnalyzedArgumentDefinition]
  for field in variant.fields:
    let analyzedField = ? analyzeDefArgumentDefinition(fileCtx, typeCtx, field)
    analyzedFields.add(analyzedField)
  ok(newAnalyzedVariantDef(variant, analyzedFields))

proc analyzeDefUnion(fileCtx: ResolvedFileContext, typeCtx: ResolvedTypeContext, union: ResolvedUnionDef): Result[AnalyzedUnionDef, string] =
  var analyzedVariants: seq[AnalyzedVariantDef]
  for variant in union.variants:
    let analyzedVariant = ? analyzeDefVariant(fileCtx, typeCtx, variant)
    analyzedVariants.add(analyzedVariant)
  ok(newAnalyzedUnionDef(union, analyzedVariants))

proc analyzeDefData(fileCtx: ResolvedFileContext, typeCtx: ResolvedTypeContext, data: ResolvedData): Result[AnalyzedData, string] =
  case data.kind:
  of rdkLiteral:
    ok(newAnalyzedData(newAnalyzedLiteralDef(data.literal)))
  of rdkStruct:
    let analyzedStruct = ? analyzeDefStruct(fileCtx, typeCtx, data.struct)
    ok(newAnalyzedData(analyzedStruct))
  of rdkUnion:
    let analyzedUnion = ? analyzeDefUnion(fileCtx, typeCtx, data.union)
    ok(newAnalyzedData(analyzedUnion))

proc analyzeDefUnionRef(fileCtx: ResolvedFileContext, typeCtx: ResolvedTypeContext, unionRef: ResolvedUnionRef): Result[AnalyzedDefUnionRef, string] =
  let maybeUnionModule = fileCtx.findModule(unionRef.module, unionRef.loc)
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
    let analyzedArgType = ? analyzeDefModuleArgumentType(fileCtx, typeCtx, unionRef.argType)
    ok(newAnalyzedDefUnionRef(unionRef, analyzedArgType, union, variant))

proc analyzeDefStructRef(fileCtx: ResolvedFileContext, typeCtx: ResolvedTypeContext, structRef: ResolvedStructRef): Result[AnalyzedDefStructRef, string] =
  let maybeStructModule = fileCtx.findModule(structRef.module, structRef.loc)
  assert(maybeStructModule.isOk, "[BUG] - Resolver ensures that the struct ref module exists")
  let structModule = maybeStructModule.get
  assert(structModule.data.isSome, "[BUG] - Resolver ensures that struct ref module has a data block")
  assert(structModule.data.get.kind == rdkStruct, "[BUG] - Resolver ensures that struct ref module has a struct block")
  let struct = structModule.data.get.struct
  if structRef.argType.impls.len == 0:
    ok(newAnalyzedDefStructRef(structRef, structModule, struct))
  else:
    let analyzedArgType = ? analyzeDefModuleArgumentType(fileCtx, typeCtx, structRef.argType)
    ok(newAnalyzedDefStructRef(structRef, analyzedArgType, struct))

proc analyzeDefStatement(fileCtx: ResolvedFileContext, typeCtx: ResolvedTypeContext, statement: ResolvedStatement): Result[AnalyzedDefStatement, string]
proc analyzeDefExpression(fileCtx: ResolvedFileContext, typeCtx: ResolvedTypeContext, expression: ResolvedExpression): Result[AnalyzedDefExpression, string]

proc analyzeDefBareLiteral(fileCtx: ResolvedFileContext, literal: ResolvedLiteral): Result[AnalyzedDefLiteral, string] =
  let maybeLiteralModule = fileCtx.findModule(literal.default, literal.loc)
  assert(maybeLiteralModule.isOk, "[BUG] - Resolver ensures that the literal default module exists")
  let literalModule = maybeLiteralModule.get
  assert(literalModule.data.isSome, "[BUG] - Resolver ensures that literal module has a data block")
  assert(literalModule.data.get.kind == rdkLiteral, "[BUG] - Resolver ensures that literal module has a literal block")
  ok(newAnalyzedDefLiteral(literal, literalModule, literalModule.data.get.literal))

proc analyzeDefCase(fileCtx: ResolvedFileContext, typeCtx: ResolvedTypeContext, caseBlock: ResolvedCaseBlock): Result[AnalyzedDefCase, string] =
  var statements: seq[AnalyzedDefStatement]
  for statement in caseBlock.statements:
    let analyzedDefStatement = ? analyzeDefStatement(fileCtx, typeCtx, statement)
    statements.add(analyzedDefStatement)
  ok(newAnalyzedDefCase(caseBlock, statements))

proc analyzeDefMatch(fileCtx: ResolvedFileContext, typeCtx: ResolvedTypeContext, match: ResolvedMatchExpression): Result[AnalyzedDefMatch, string] =
  let subject = ? analyzeDefExpression(fileCtx, typeCtx, match.subject)

  var cases: seq[AnalyzedDefCase]
  for caseBlock in match.cases:
    let analyzedDefCase = ? analyzeDefCase(fileCtx, typeCtx, caseBlock)
    cases.add(analyzedDefCase)
  ok(newAnalyzedDefMatch(match, subject, cases))

proc analyzeDefFunctionCall(fileCtx: ResolvedFileContext, typeCtx: ResolvedTypeContext, fncall: ResolvedFunctionCall): Result[AnalyzedDefFunctionCall, string] =
  let maybeType = fileCtx.findType(fncall.typ, fncall.loc)
  assert(maybeType.isOk, "[BUG] - Resolver ensures that the function call receiver type exists")
  let resolvedType = maybeType.get
  var args: seq[AnalyzedDefExpression]
  for arg in fncall.args:
    let analyzedDefArg = ? analyzeDefExpression(fileCtx, typeCtx, arg)
    args.add(analyzedDefArg)
  ok(newAnalyzedDefFunctionCall(fncall, resolvedType, args))

proc analyzeDefUnionInitializer(fileCtx: ResolvedFileContext, typeCtx: ResolvedTypeContext, init: ResolvedUnionInitializer): Result[AnalyzedDefUnionInitializer, string] =
  let unionRef = ? analyzeDefUnionRef(fileCtx, typeCtx, init.unionRef)
  var kwargs: seq[AnalyzedDefKeywordArgument]
  for kwarg in init.kwargs:
    let analyzedDefExpr = ? analyzeDefExpression(fileCtx, typeCtx, kwarg.expression)
    let analyzedDefKwarg = newAnalyzedDefKeywordArgument(kwarg, analyzedDefExpr)
    kwargs.add(analyzedDefKwarg)
  ok(newAnalyzedDefUnionInitializer(init, unionRef, kwargs))

proc analyzeDefStructInitializer(fileCtx: ResolvedFileContext, typeCtx: ResolvedTypeContext, init: ResolvedStructInitializer): Result[AnalyzedDefStructInitializer, string] =
  let structRef = ? analyzeDefStructRef(fileCtx, typeCtx, init.structRef)
  var kwargs: seq[AnalyzedDefKeywordArgument]
  for kwarg in init.kwargs:
    let analyzedDefExpr = ? analyzeDefExpression(fileCtx, typeCtx, kwarg.expression)
    let analyzedDefKwarg = newAnalyzedDefKeywordArgument(kwarg, analyzedDefExpr)
    kwargs.add(analyzedDefKwarg)
  ok(newAnalyzedDefStructInitializer(init, structRef, kwargs))

proc analyzeDefLiteralInitializer(fileCtx: ResolvedFileContext, typeCtx: ResolvedTypeContext, init: ResolvedLiteralInitializer): Result[AnalyzedDefLiteralInitializer, string] =
  let argType = ? analyzeDefModuleArgumentType(fileCtx, typeCtx, init.argType)
  assert(argType.module.data.isSome, "[BUG] - Resolver ensures that literal module has a data block")
  assert(argType.module.data.get.kind == rdkLiteral, "[BUG] - Resolver ensures that literal module has a literal block")
  ok(newAnalyzedDefLiteralInitializer(init, argType, argType.module.data.get.literal))

proc analyzeDefInitializer(fileCtx: ResolvedFileContext, typeCtx: ResolvedTypeContext, init: ResolvedInitializer): Result[AnalyzedDefInitializer, string] =
  case init.kind:
  of rikLiteral:
    let literalInit = ? analyzeDefLiteralInitializer(fileCtx, typeCtx, init.literal)
    ok(newAnalyzedDefInitializer(literalInit))
  of rikStruct:
    let structInit = ? analyzeDefStructInitializer(fileCtx, typeCtx, init.struct)
    ok(newAnalyzedDefInitializer(structInit))
  of rikUnion:
    let unionInit = ? analyzeDefUnionInitializer(fileCtx, typeCtx, init.union)
    ok(newAnalyzedDefInitializer(unionInit))

proc analyzeDefExpression(fileCtx: ResolvedFileContext, typeCtx: ResolvedTypeContext, expression: ResolvedExpression): Result[AnalyzedDefExpression, string] =
  case expression.kind:
  # Variables and getters touch only function-scope names and struct
  # fields — nothing def-level to analyze, so they wrap as-is; phase B
  # checks the field path (see the matching note in analyzeDefSetter).
  of rekVariable:
    ok(newAnalyzedDefExpression(expression.variable))
  of rekGetter:
    ok(newAnalyzedDefExpression(expression.getter))
  of rekLiteral:
    let literal = ? analyzeDefBareLiteral(fileCtx, expression.literal)
    ok(newAnalyzedDefExpression(literal))
  of rekFunctionCall:
    let fncall = ? analyzeDefFunctionCall(fileCtx, typeCtx, expression.fncall)
    ok(newAnalyzedDefExpression(fncall))
  of rekInitializer:
    let init = ? analyzeDefInitializer(fileCtx, typeCtx, expression.init)
    ok(newAnalyzedDefExpression(init))
  of rekMatchExpr:
    let match = ? analyzeDefMatch(fileCtx, typeCtx, expression.match)
    ok(newAnalyzedDefExpression(match))

proc analyzeDefAssignment(fileCtx: ResolvedFileContext, typeCtx: ResolvedTypeContext, assignment: ResolvedAssignment): Result[AnalyzedDefAssignment, string] =
  let expression = ? analyzeDefExpression(fileCtx, typeCtx, assignment.expression)
  ok(newAnalyzedDefAssignment(assignment, expression))

proc analyzeDefSetter(fileCtx: ResolvedFileContext, typeCtx: ResolvedTypeContext, setter: ResolvedSetter): Result[AnalyzedDefSetter, string] =
  # The getter side is skipped on purpose — same rationale as the
  # rekGetter arm in analyzeDefExpression.
  let expression = ? analyzeDefExpression(fileCtx, typeCtx, setter.expression)
  ok(newAnalyzedDefSetter(setter, expression))

proc analyzeDefStatement(fileCtx: ResolvedFileContext, typeCtx: ResolvedTypeContext, statement: ResolvedStatement): Result[AnalyzedDefStatement, string] =
  case statement.kind:
  of rskAssignment:
    let assignment = ? analyzeDefAssignment(fileCtx, typeCtx, statement.assignment)
    ok(newAnalyzedDefStatement(assignment))
  of rskExpr:
    let expression = ? analyzeDefExpression(fileCtx, typeCtx, statement.expression)
    ok(newAnalyzedDefStatement(expression))
  of rskSetter:
    let setter = ? analyzeDefSetter(fileCtx, typeCtx, statement.setter)
    ok(newAnalyzedDefStatement(setter))

proc analyzeDefUserFunction(fileCtx: ResolvedFileContext, typeCtx: ResolvedTypeContext, function: ResolvedUserFunction): Result[AnalyzedDefUserFunction, string] =
  let funcDef = ? analyzeDefFunctionDefinition(fileCtx, typeCtx, function.def)
  var statements: seq[AnalyzedDefStatement]
  for statement in function.statements:
    let analyzedDefStatement = ? analyzeDefStatement(fileCtx, typeCtx, statement)
    statements.add(analyzedDefStatement)
  ok(newAnalyzedDefUserFunction(function, funcDef, statements))

proc analyzeDefExternFunction(fileCtx: ResolvedFileContext, typeCtx: ResolvedTypeContext, function: ResolvedExternFunction): Result[AnalyzedDefExternFunction, string] =
  let analyzedFuncDef = ? analyzeDefFunctionDefinition(fileCtx, typeCtx, function.def)
  ok(newAnalyzedDefExternFunction(function, analyzedFuncDef))

proc analyzeDefFunction(fileCtx: ResolvedFileContext, typeCtx: ResolvedTypeContext, function: ResolvedFunction): Result[AnalyzedDefFunction, string] =
  case function.kind:
  of rfkExtern:
    let analyzedExternFunction = ? analyzeDefExternFunction(fileCtx, typeCtx, function.extern)
    ok(newAnalyzedDefFunction(analyzedExternFunction))
  of rfkUser:
    let analyzedUserFunction = ? analyzeDefUserFunction(fileCtx, typeCtx, function.user)
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

proc analyzeDefModule(fileCtx: ResolvedFileContext, module: ResolvedModule): Result[AnalyzedDefModule, string] =
  let typeCtx = newResolvedTypeContext(module)
  var requires: seq[AnalyzedGenericArgumentType]
  var maybeAnalyzedData: Option[AnalyzedData]
  if module.data.isSome:
    for genericArgType in module.data.get.requires:
      let analyzedArgType = ? analyzeDefGenericArgumentType(fileCtx, genericArgType)
      requires.add(analyzedArgType)
    let analyzedData = ? analyzeDefData(fileCtx, typeCtx, module.data.get)
    maybeAnalyzedData = some(analyzedData)

  var analyzedDefFuncs: seq[AnalyzedDefFunction]
  for function in module.functions:
    let analyzedDefFunc = ? analyzeDefFunction(fileCtx, typeCtx, function)
    analyzedDefFuncs.add(analyzedDefFunc)

  ok(newAnalyzedDefModule(module, requires, maybeAnalyzedData, analyzedDefFuncs))

proc analyzeDefGeneric(fileCtx: ResolvedFileContext, generic: ResolvedGeneric): Result[AnalyzedGeneric, string] =
  let typeCtx = newResolvedTypeContext(generic)
  var analyzedFuncDefs: seq[AnalyzedFunctionDefinition]
  for funcDef in generic.funcDefs:
    let analyzedFuncDef = ? analyzeDefFunctionDefinition(fileCtx, typeCtx, funcDef)
    analyzedFuncDefs.add(analyzedFuncDef)
  ok(newAnalyzedGeneric(generic, analyzedFuncDefs))

# ============================================================
# Phase-A defined-type dispatcher (W5 of plan_analyzer_two_pass.md).
# ============================================================

proc analyzeDefType(fileCtx: ResolvedFileContext, typ: ResolvedType): Result[AnalyzedType, string] =
  case typ.kind:
  of rtkGeneric:
    let analyzedGeneric = ? analyzeDefGeneric(fileCtx, typ.generic)
    ok(newAnalyzedType(analyzedGeneric))
  of rtkModule:
    let analyzedModule = ? analyzeDefModule(fileCtx, typ.module)
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

  let maybeFileCtx = newResolvedFileContext(analyzedImports, file.types)
  assert(maybeFileCtx.isOk, "[BUG] - Resolver ensures per-file type bindings are conflict-free")
  let fileCtx = maybeFileCtx.get
  var analyzedTypes: seq[AnalyzedType]
  for typ in file.types:
    let analyzedType = ? analyzeDefType(fileCtx, typ)
    analyzedTypes.add(analyzedType)
  ok(newAnalyzedDefFile(file, analyzedImports, analyzedTypes, fileCtx))

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
