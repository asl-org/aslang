import results, strformat, tables, options

## Package façade. Consumers say `import resolver` to get every
## resolved-side type (types, constructors, accessors, and the
## `resolve*` entry point). It does NOT re-export the parser layer it
## builds on: parser is a sibling package under src/, so a consumer
## that also needs parser types imports `parser/index` directly.

import ../parser/index as parser

import ./indexing
export indexing

# ---- argument-type cluster (mutually-recursive tagged union) ----
import ./functioncontext
export functioncontext

import ./argtype
export argtype

# ---- function-def cluster ----
# ---- data-block cluster ----
import ./datadef
export datadef

# ---- body cluster: leaf nodes ----
import ./refs
export refs

# ---- body cluster: mutually-recursive statement/expression web ----
import ./statement
export statement

import ./function
export function

# ---- module / generic / type umbrella ----
import ./types
export types

import ./imports
import ./app
export imports, app


# resolveArgumentType — single proc for both definition contexts; the
# enclosing definition (a `LocalType` — the enclosing module | generic)
# rides along so visibility (`access`) and the generic self-reference
# rule are decided where they apply.
proc resolveArgumentType(file: ResolvedFile, ctxType: LocalType, argType: ArgumentType): Result[ResolvedArgumentType, string]

# resolveModuleArgumentType (below) only POPULATES a module argument
# type's impls — it neither counts them against the module's require
# slots nor checks that each impl satisfies its slot's generic
# constraint. Both are the def analyzer's job
# (analyzeDefModuleArgumentType).
#
# Why they can't run here: both need the module's require slots, and a
# constraint check additionally needs BOTH the contract generic's and
# the impl module's fully resolved function signatures. ASL allows
# cyclic dependencies across modules within a single file and has no
# forward-declaration mechanism, so the resolver can't guarantee those
# signatures are resolved when the check would fire — they may
# themselves depend on the very type being resolved. The def analyzer
# runs after every signature is resolved, so it reads require slots off
# a module's data block and compares concretized signatures without
# hitting a mid-resolution shape. Doing it here would need either
# topological ordering (impossible with cycles) or a signatures-first /
# validate-second split (breaks the single pass-B model).

proc resolveModuleArgumentType(file: ResolvedFile, ctxType: LocalType, argType: ArgumentType, argModule: Module): Result[ResolvedModuleArgumentType, string] =
  # The resolver only POPULATES the impl types here: it looks the module
  # up and resolves each nested argument type in slot order. Impl count
  # (against the module's require slots) and generic-constraint
  # satisfaction are validated one phase later by the def analyzer's
  # `analyzeDefModuleArgumentType`, which reads the require slots off the
  # module's data block. Deferring keeps the resolver from having to
  # derive require slots for a module whose resolved twin may not exist
  # yet (in-file cycles) or hop into an imported module's defining scope.
  if argModule.data.isNone:
    err(fmt"{argType.loc} module `{argType.root.asl}` is not a data module")
  else:
    var impls: seq[ResolvedArgumentType]
    for impl in argType.impls:
      let resolvedImpl = ? resolveArgumentType(file, ctxType, impl)
      impls.add(resolvedImpl)
    ok(newResolvedModuleArgumentType(argModule, impls, argType.loc))

proc resolveGenericArgumentType(ctxType: LocalType, argType: ArgumentType, argGeneric: Generic): Result[ResolvedGenericArgumentType, string] =
  case ctxType.kind:
  of ltkModule:
    if argType.impls.len == 0:
      ok(newResolvedGenericArgumentType(argGeneric, argType.loc))
    else:
      err(fmt"{argGeneric.loc} generic `{argGeneric.name.asl}` is not allowed to have impls")
  of ltkGeneric:
    if argType.impls.len == 0:
      if argGeneric == ctxType.generic:
        ok(newResolvedGenericArgumentType(argGeneric, argType.loc))
      else:
        err(fmt"{argType.loc} type `{argGeneric.name.asl}` is a generic and can not be used within the generic block")
    else:
      err(fmt"{argType.loc} type `{argGeneric.name.asl}` is a generic and does not support further impls")

proc resolveArgumentType(file: ResolvedFile, ctxType: LocalType, argType: ArgumentType): Result[ResolvedArgumentType, string] =
  let typ = ? file.findLocalType(argType.root)
  case typ.kind:
  of ltkGeneric:
    let resolvedGenericType = ? resolveGenericArgumentType(ctxType, argType, typ.generic)
    ok(newResolvedArgumentType(resolvedGenericType))
  of ltkModule:
    let resolvedModuleType = ? resolveModuleArgumentType(file, ctxType, argType, typ.module)
    ok(newResolvedArgumentType(resolvedModuleType))

proc resolveArgumentDef(file: ResolvedFile, ctxType: LocalType, argDef: ArgumentDef): Result[ResolvedArgumentDef, string] =
  let resolvedArgumentType = ? resolveArgumentType(file, ctxType, argDef.argType)
  ok(newResolvedArgumentDef(argDef, resolvedArgumentType))

proc resolveStructDefHeader(file: ResolvedFile, header: StructDefHeader): Result[seq[ResolvedGenericArgumentType], string] =
  var resolvedRequires: seq[ResolvedGenericArgumentType]
  for impl in header.requires:
    let generic = ? file.findGeneric(impl)
    let genericType = newResolvedGenericArgumentType(generic, impl.loc)
    resolvedRequires.add(genericType)
  ok(resolvedRequires)

proc resolveFields(file: ResolvedFile, ctxType: LocalType, fields: seq[ArgumentDef]): Result[seq[ResolvedArgumentDef], string] =
  var resolvedFields: seq[ResolvedArgumentDef]
  for field in fields:
    let resolvedField = ? resolveArgumentDef(file, ctxType, field)
    resolvedFields.add(resolvedField)
  ok(resolvedFields)

proc resolveStructDef(file: ResolvedFile, ctxType: LocalType, struct: StructDef): Result[ResolvedStructDef, string] =
  let resolvedRequires = ? resolveStructDefHeader(file, struct.header)
  let resolvedFields = ? resolveFields(file, ctxType, struct.fields)
  # Explicit-vs-inferred decision + header/field conflict live on the
  # constructor.
  ok(newResolvedStructDef(struct, resolvedRequires, resolvedFields))

proc resolveVariantDef(file: ResolvedFile, ctxType: LocalType, variant: VariantDef): Result[ResolvedVariantDef, string] =
  let resolvedFields = ? resolveFields(file, ctxType, variant.fields)
  ok(newResolvedVariantDef(variant, resolvedFields))

proc resolveUnionDef(file: ResolvedFile, ctxType: LocalType, union: UnionDef): Result[ResolvedUnionDef, string] =
  var resolvedVariants: seq[ResolvedVariantDef]
  for variant in union.variants:
    let resolvedVariant = ? resolveVariantDef(file, ctxType, variant)
    resolvedVariants.add(resolvedVariant)
  ok(newResolvedUnionDef(union, resolvedVariants))

proc resolveDataDef(file: ResolvedFile, ctxType: LocalType, data: DataDef): Result[ResolvedDataDef, string] =
  case data.kind:
  of ddkLiteral:
    let resolvedLiteralDef = ? newResolvedLiteralDef(data.literal)
    ok(newResolvedDataDef(resolvedLiteralDef))
  of ddkStruct:
    let resolvedStructDef = ? resolveStructDef(file, ctxType, data.struct)
    ok(newResolvedDataDef(resolvedStructDef))
  of ddkUnion:
    let resolvedUnionDef = ? resolveUnionDef(file, ctxType, data.union)
    ok(newResolvedDataDef(resolvedUnionDef))

proc resolveFunctionDef(file: ResolvedFile, ctxType: LocalType, def: FunctionDef): Result[ResolvedFunctionDef, string] =
  var resolvedArgDefs: seq[ResolvedArgumentDef]
  for argDef in def.args:
    let resolvedArgDef = ? resolveArgumentDef(file, ctxType, argDef)
    resolvedArgDefs.add(resolvedArgDef)

  let resolvedReturnType = ? resolveArgumentType(file, ctxType, def.returns)
  ok(newResolvedFunctionDef(def, resolvedArgDefs, resolvedReturnType))

proc resolveExternFunction(file: ResolvedFile, ctxType: LocalType, function: ExternFunction): Result[ResolvedExternFunction, string] =
  let resolvedFunctionDef = ? resolveFunctionDef(file, ctxType, function.def)
  ok(newResolvedExternFunction(function, resolvedFunctionDef))

proc resolveLiteral(file: ResolvedFile, literal: Literal): Result[ResolvedLiteral, string] =
  let module = ? file.findModule(literal.defaultType)
  if module.data.isNone:
    err(fmt"{literal.loc} expected module `{literal.defaultType.asl}` to be a literal but found none")
  else:
    let moduleData = module.data.get
    case moduleData.kind:
    of ddkStruct: err(fmt"{literal.loc} expected module `{literal.defaultType.asl}` to be literal but found struct")
    of ddkUnion: err(fmt"{literal.loc} expected module `{literal.defaultType.asl}` to be literal but found union")
    of ddkLiteral: ok(newResolvedLiteral(literal, module, moduleData.literal))

proc resolveVariable(scope: FunctionContext, variable: Identifier): Result[Identifier, string] =
  if variable notin scope:
    err(fmt"{variable.loc} variable `{variable.asl}` is not present in scope")
  else:
    ok(variable)

proc resolveGetter(scope: FunctionContext, getter: Getter): Result[ResolvedGetter, string] =
  discard ? resolveVariable(scope, getter.source)
  ok(newResolvedGetter(getter))

# resolveExpression / resolveStatement form the body-cluster cycle.
proc resolveExpression(file: ResolvedFile, ctxType: LocalType, funcCtx: FunctionContext, expression: Expression): Result[ResolvedExpression, string]
proc resolveStatement(file: ResolvedFile, ctxType: LocalType, funcCtx: FunctionContext, statement: Statement): Result[ResolvedStatement, string]

proc resolveFunctionCall(file: ResolvedFile, ctxType: LocalType, funcCtx: FunctionContext, fncall: FunctionCall): Result[ResolvedFunctionCall, string] =
  let typ = ? file.findLocalType(fncall.root)
  let defs = ? typ.findFunctionDefs(fncall.name, fncall.arity, ctxType)
  assert(defs.len > 0, "[BUG] - findFunctionDefs never returns an empty overload list")
  var resolvedArgs: seq[ResolvedExpression]
  for arg in fncall.args:
    let resolvedArg = ? resolveExpression(file, ctxType, funcCtx, arg)
    resolvedArgs.add(resolvedArg)
  ok(newResolvedFunctionCall(fncall, typ, resolvedArgs))

proc resolveStructRef(file: ResolvedFile, ctxType: LocalType, structRef: StructRef): Result[ResolvedStructRef, string] =
  let structModule = ? file.findModule(structRef.module)
  if structModule.data.isNone:
    err(fmt"{structRef.loc} module `{structModule.name.asl}` does not define a data block")
  else:
    let moduleData = structModule.data.get
    case moduleData.kind:
    of ddkLiteral: err(fmt"{structRef.loc} expected module `{structRef.module.asl}` to be struct but found literal")
    of ddkUnion: err(fmt"{structRef.loc} expected module `{structRef.module.asl}` to be struct but found union")
    of ddkStruct:
      let struct = moduleData.struct
      if structRef.impls.len == 0:
        # Bare-ref legality (no explicit-header phantom params) lives
        # on the constructor.
        newResolvedStructRef(structRef, structModule, struct)
      else:
        let resolvedModuleArgType = ? resolveModuleArgumentType(file, ctxType, structRef.argType, structModule)
        ok(newResolvedStructRef(structRef, resolvedModuleArgType, struct))

proc resolveKeywordArguments(file: ResolvedFile, ctxType: LocalType, funcCtx: FunctionContext, kwargList: KeywordArgumentList): Result[seq[ResolvedKeywordArgument], string] =
  ## Resolves each kwarg's expression, in source order. Field-name
  ## validation, duplicate detection, and canonical ordering live on
  ## the initializer constructors (one shape serves struct + union).
  var resolvedKwargs: seq[ResolvedKeywordArgument]
  for kwarg in kwargList.items:
    let resolvedExpression = ? resolveExpression(file, ctxType, funcCtx, kwarg.expression)
    resolvedKwargs.add(newResolvedKeywordArgument(kwarg, resolvedExpression))
  ok(resolvedKwargs)

proc resolveStructInitializer(file: ResolvedFile, ctxType: LocalType, funcCtx: FunctionContext, init: StructInitializer): Result[ResolvedStructInitializer, string] =
  let resolvedStructRef = ? resolveStructRef(file, ctxType, init.structRef)
  let resolvedKeywordArgs = ? resolveKeywordArguments(file, ctxType, funcCtx, init.kwargList)
  newResolvedStructInitializer(init, resolvedStructRef, resolvedKeywordArgs)

proc resolveUnionRef(file: ResolvedFile, ctxType: LocalType, unionRef: UnionRef): Result[ResolvedUnionRef, string] =
  let unionModule = ? file.findModule(unionRef.module)
  if unionModule.data.isNone:
    err(fmt"{unionRef.loc} expected module `{unionRef.module.asl}` to be union but found none")
  else:
    let moduleData = unionModule.data.get
    case moduleData.kind:
    of ddkLiteral: err(fmt"{unionRef.loc} expected module `{unionRef.module.asl}` to be union but found literal")
    of ddkStruct: err(fmt"{unionRef.loc} expected module `{unionRef.module.asl}` to be union but found struct")
    of ddkUnion:
      let union = moduleData.union
      let variant = ? union.findVariant(unionRef.variant)
      if unionRef.impls.len == 0:
        ok(newResolvedUnionRef(unionRef, unionModule, variant))
      else:
        let resolvedArgType = ? resolveModuleArgumentType(file, ctxType, unionRef.argType, unionModule)
        ok(newResolvedUnionRef(unionRef, resolvedArgType, variant))

proc resolveUnionInitializer(file: ResolvedFile, ctxType: LocalType, funcCtx: FunctionContext, unionInit: UnionInitializer): Result[ResolvedUnionInitializer, string] =
  let resolvedUnionRef = ? resolveUnionRef(file, ctxType, unionInit.unionRef)
  let resolvedKeywordArgs = ? resolveKeywordArguments(file, ctxType, funcCtx, unionInit.kwargList)
  newResolvedUnionInitializer(unionInit, resolvedUnionRef, resolvedKeywordArgs)

proc resolveLiteralInitializer(file: ResolvedFile, ctxType: LocalType, init: LiteralInitializer): Result[ResolvedLiteralInitializer, string] =
  let module = ? file.findModule(init.module)
  if module.data.isNone:
    err(fmt"{init.loc} expected module `{init.module.asl}` to be a literal but found none")
  else:
    let moduleData = module.data.get
    case moduleData.kind:
    of ddkStruct: err(fmt"{init.loc} expected module `{init.module.asl}` to be literal but found struct")
    of ddkUnion: err(fmt"{init.loc} expected module `{init.module.asl}` to be literal but found union")
    of ddkLiteral:
      let resolvedModuleArgType = ? resolveModuleArgumentType(file, ctxType, init.argType, module)
      ok(newResolvedLiteralInitializer(init, resolvedModuleArgType, moduleData.literal))

proc resolveInitializer(file: ResolvedFile, ctxType: LocalType, funcCtx: FunctionContext, initializer: Initializer): Result[ResolvedInitializer, string] =
  case initializer.kind:
  of ikLiteral:
    let resolvedLiteralInit = ? resolveLiteralInitializer(file, ctxType, initializer.literal)
    ok(newResolvedInitializer(resolvedLiteralInit))
  of ikStruct:
    let resolvedStructInit = ? resolveStructInitializer(file, ctxType, funcCtx, initializer.struct)
    ok(newResolvedInitializer(resolvedStructInit))
  of ikUnion:
    let resolvedUnionInit = ? resolveUnionInitializer(file, ctxType, funcCtx, initializer.union)
    ok(newResolvedInitializer(resolvedUnionInit))

proc resolveCasePattern(casePattern: CasePattern): Result[ResolvedCasePattern, string] =
  case casePattern.kind:
  of cpkInteger:
    ok(newResolvedCasePattern(casePattern.intLit))
  of cpkVariable:
    ok(newResolvedCasePattern(casePattern.variable))
  of cpkUnion:
    ok(newResolvedCasePattern(casePattern.variant))

proc resolveCaseBlock(file: ResolvedFile, ctxType: LocalType, funcCtx: FunctionContext, caseBlock: CaseBlock): Result[ResolvedCaseBlock, string] =
  var caseCtx = funcCtx
  let resolvedCasePattern = ? resolveCasePattern(caseBlock.pattern)
  caseCtx = caseCtx.update(resolvedCasePattern)

  var resolvedStatements: seq[ResolvedStatement]
  for statement in caseBlock.statements:
    let resolvedStatement = ? resolveStatement(file, ctxType, caseCtx, statement)
    resolvedStatements.add(resolvedStatement)
    caseCtx = caseCtx.update(resolvedStatement)
  ok(newResolvedCaseBlock(caseBlock, resolvedCasePattern, resolvedStatements))

proc resolveMatchExpression(file: ResolvedFile, ctxType: LocalType, funcCtx: FunctionContext, match: MatchExpression): Result[ResolvedMatchExpression, string] =
  let resolvedSubject = ? resolveExpression(file, ctxType, funcCtx, match.subject)
  var resolvedCaseBlocks: seq[ResolvedCaseBlock]
  for caseBlock in match.cases:
    let resolvedCaseBlock = ? resolveCaseBlock(file, ctxType, funcCtx, caseBlock)
    resolvedCaseBlocks.add(resolvedCaseBlock)
  ok(newResolvedMatchExpression(match, resolvedSubject, resolvedCaseBlocks))

proc resolveExpression(file: ResolvedFile, ctxType: LocalType, funcCtx: FunctionContext, expression: Expression): Result[ResolvedExpression, string] =
  case expression.kind:
  of ekLiteral:
    let resolvedLiteral = ? resolveLiteral(file, expression.literal)
    ok(newResolvedExpression(resolvedLiteral))
  of ekGetter:
    let resolvedGetter = ? resolveGetter(funcCtx, expression.getter)
    ok(newResolvedExpression(resolvedGetter))
  of ekVariable:
    let resolvedVariable = ? resolveVariable(funcCtx, expression.variable)
    ok(newResolvedExpression(resolvedVariable))
  of ekFnCall:
    let resolvedFunctionCall = ? resolveFunctionCall(file, ctxType, funcCtx, expression.fncall)
    ok(newResolvedExpression(resolvedFunctionCall))
  of ekInitializer:
    let resolvedInitializer = ? resolveInitializer(file, ctxType, funcCtx, expression.initializer)
    ok(newResolvedExpression(resolvedInitializer))
  of ekMatch:
    let resolvedMatchExpr = ? resolveMatchExpression(file, ctxType, funcCtx, expression.match)
    ok(newResolvedExpression(resolvedMatchExpr))

proc resolveAssignment(file: ResolvedFile, ctxType: LocalType, funcCtx: FunctionContext, assignment: Assignment): Result[ResolvedAssignment, string] =
  let resolvedExpression = ? resolveExpression(file, ctxType, funcCtx, assignment.expression)
  ok(newResolvedAssignment(assignment, resolvedExpression))

proc resolveSetter(file: ResolvedFile, ctxType: LocalType, funcCtx: FunctionContext, setter: Setter): Result[ResolvedSetter, string] =
  let resolvedGetter = ? resolveGetter(funcCtx, setter.target)
  let resolvedExpression = ? resolveExpression(file, ctxType, funcCtx, setter.expression)
  ok(newResolvedSetter(setter, resolvedGetter, resolvedExpression))

proc resolveStatement(file: ResolvedFile, ctxType: LocalType, funcCtx: FunctionContext, statement: Statement): Result[ResolvedStatement, string] =
  case statement.kind:
  of skExpr:
    let resolvedExpression = ? resolveExpression(file, ctxType, funcCtx, statement.expression)
    ok(newResolvedStatement(resolvedExpression))
  of skAssignment:
    let resolvedAssignment = ? resolveAssignment(file, ctxType, funcCtx, statement.assignment)
    ok(newResolvedStatement(resolvedAssignment))
  of skSetter:
    let resolvedMutation = ? resolveSetter(file, ctxType, funcCtx, statement.setter)
    ok(newResolvedStatement(resolvedMutation))

proc resolveUserFunction(file: ResolvedFile, ctxType: LocalType, function: UserFunction): Result[ResolvedUserFunction, string] =
  let resolvedFuncDef = ? resolveFunctionDef(file, ctxType, function.def)

  var funcCtx = ? newFunctionContext(resolvedFuncDef)
  var resolvedStmts: seq[ResolvedStatement]
  for statement in function.statements:
    let resolvedStatement = ? resolveStatement(file, ctxType, funcCtx, statement)
    resolvedStmts.add(resolvedStatement)
    funcCtx = funcCtx.update(resolvedStatement)

  ok(newResolvedUserFunction(function, resolvedFuncDef, resolvedStmts))

proc resolveFunction(file: ResolvedFile, ctxType: LocalType, function: Function): Result[ResolvedFunction, string] =
  case function.kind:
  of fkUser:
    let userFunc = ? resolveUserFunction(file, ctxType, function.user)
    ok(newResolvedFunction(userFunc))
  of fkExtern:
    let externFunc = ? resolveExternFunction(file, ctxType, function.extern)
    ok(newResolvedFunction(externFunc))
  of fkGenerated:
    let generatedFunc = ? resolveFunctionDef(file, ctxType, function.generated)
    ok(newResolvedFunction(generatedFunc))

proc resolveModule(file: ResolvedFile, module: Module): Result[ResolvedModule, string] =
  let ctxType = newLocalType(module)
  let resolvedData =
    if module.data.isSome:
      let resolvedDataDef = ? resolveDataDef(file, ctxType, module.data.get)
      some(resolvedDataDef)
    else:
      none(ResolvedDataDef)

  var resolvedFunctions: seq[ResolvedFunction]
  for function in module.functions:
    let resolvedFunction = ? resolveFunction(file, ctxType, function)
    resolvedFunctions.add(resolvedFunction)

  # Construction invariants (input-signature uniqueness, public
  # modules require public generics) live on the constructor.
  newResolvedModule(module, resolvedData, resolvedFunctions)

proc resolveGeneric(file: ResolvedFile, generic: Generic): Result[ResolvedGeneric, string] =
  let ctxType = newLocalType(generic)
  var resolvedFuncDefs: seq[ResolvedFunctionDef]
  for def in generic.defs:
    let resolvedFuncDef = ? resolveFunctionDef(file, ctxType, def)
    resolvedFuncDefs.add(resolvedFuncDef)

  # Input-signature uniqueness lives on the constructor.
  newResolvedGeneric(generic, resolvedFuncDefs)

proc resolveType(file: ResolvedFile, typ: LocalType): Result[ResolvedLocalType, string] =
  assert(typ.decorators.len == 0, fmt"{typ.loc} types do not support decorators")
  case typ.kind:
  of ltkGeneric:
    let resolvedGeneric = ? resolveGeneric(file, typ.generic)
    ok(newResolvedLocalType(resolvedGeneric))
  of ltkModule:
    let resolvedModule = ? resolveModule(file, typ.module)
    ok(newResolvedLocalType(resolvedModule))

proc resolveExplicitImport(imp: Import, importedFile: ResolvedFile): Result[seq[ResolvedImportedType], string] =
  var importedTypes: seq[ResolvedImportedType]
  for importedType in imp.names:
    let resolvedImportedType = ? importedFile.findExportedType(importedType)
    importedTypes.add(resolvedImportedType)
  ok(importedTypes)

proc resolveImport(app: ResolvedApp, imp: Import): Result[ResolvedImport, string] =
  let importedFile = app.findImportedFile(imp.absPath)
  let importedTypes =
    case imp.kind:
    of ikShorthand: importedFile.exportedTypes
    of ikExplicit: ? resolveExplicitImport(imp, importedFile)
  ok(newResolvedImport(imp, importedFile.parsed, importedTypes))

proc resolveFile(app: ResolvedApp, file: parser.File): Result[ResolvedFile, string] =
  var resolvedFile = ? newResolvedFile(file)

  for imp in file.imports:
    let resolvedImport = ? resolveImport(app, imp)
    resolvedFile = ? resolvedFile.add(resolvedImport)

  for typ in file.types:
    let resolvedType = ? resolveType(resolvedFile, typ)
    resolvedFile = ? resolvedFile.add(resolvedType)

  ok(resolvedFile)

proc resolve*(app: App): Result[ResolvedApp, string] =
  let resolvedApp = newResolvedApp(app)
  for file in app.files:
    let resolvedFile = ? resolveFile(resolvedApp, file)
    resolvedApp.add(resolvedFile)
  ok(resolvedApp)