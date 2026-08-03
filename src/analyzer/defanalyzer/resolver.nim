import results, sequtils, sets, strformat, tables, options

## Package façade. Consumers say `import resolver` to get every
## resolved-side type PLUS the parser layer that resolver builds on
## (types, constructors, accessors, and the `parse*` entry point).
##
## Parser combinators (Spec[T] machinery, oneOf / pair / prefixed /
## etc.) stay private to the parser layer — analyzer, cli, and asl.nim
## never touch them, and re-exporting them here would leak internal
## parser scaffolding through the resolver's API. Callers that need
## the combinator layer directly (parser tests) import
## `resolver/parser/combinators` explicitly.

import ./resolver/parser
export parser

import ./resolver/literaldef
export literaldef

import ./resolver/patterns
export patterns

# ---- argument-type cluster (mutually-recursive tagged union) ----
import ./resolver/typecontext
export typecontext

import ./resolver/filecontext
export filecontext

import ./resolver/functioncontext
export functioncontext

import ./resolver/argtype
export argtype

import ./resolver/moduleargtype
export moduleargtype

import ./resolver/genericargtype
export genericargtype

# ---- function-def cluster ----
import ./resolver/argdef
export argdef

import ./resolver/funcdef
export funcdef

import ./resolver/externfunc
export externfunc

# ---- data-block cluster ----
import ./resolver/structdef
export structdef

import ./resolver/variantdef
export variantdef

import ./resolver/uniondef
export uniondef

import ./resolver/datadef
export datadef

# ---- body cluster: leaf nodes ----
import ./resolver/getter
export getter

import ./resolver/literalinit
export literalinit

import ./resolver/structref
export structref

import ./resolver/unionref
export unionref

# ---- body cluster: mutually-recursive statement/expression web ----
import ./resolver/statement
export statement

import ./resolver/function
export function

# ---- module / generic / type umbrella ----
import ./resolver/module
export module

import ./resolver/generic
export generic

import ./resolver/types
export types

import ./resolver/imports
import ./resolver/files
import ./resolver/app
export imports, files, app


# resolveArgumentType — single proc for both definition contexts; the
# `TypeContext` (enclosing module | enclosing generic) rides along so
# visibility and the generic self-reference rule are decided where
# they apply.
proc resolveArgumentType(fileCtx: FileContext, typeCtx: TypeContext, argType: ArgumentType): Result[ResolvedArgumentType, string]

# Constraint-satisfaction check: does `impl` provide every funcDef
# the required generic `base` mandates? Retired the analyzer's
# equivalent def-time check and moved it here so
# ResolvedModuleArgumentType.impls is a provably valid value by the
# time it leaves the resolver.
#
# Verification is deliberately SHALLOW — by `(name, arity)` plus
# accessibility (a private function only satisfies a constraint from
# inside its own module; see TypeContext.access) at the parser
# level, not by concretized-signature comparison. Signature-
# parity (e.g. impl provides `byte_size(items: u16)` where the base
# generic mandates `byte_size(items: u32)`) is left to the analyzer's
# value-vs-defType walk at use sites
# (`analyzeValueTypeAgainstDefType` on the analyzer facade), which
# already runs the strict check every time a value is type-checked
# against a definition.
#
# Why shallow-here and deep-there: a deep signature check would need
# BOTH the base generic's and the impl module's fully resolved
# function signatures. ASL allows cyclic dependencies across modules
# within a single file and has no forward-declaration mechanism, so
# the resolver can't guarantee an impl module's signatures are
# resolved when the check would fire (they may themselves depend on
# the type currently being resolved). The analyzer runs after every
# signature is fully resolved, so it can compare types without
# hitting a mid-resolution shape. Attempting the deep check in the
# resolver would require either topological ordering (impossible
# with cycles) or a two-pass signatures-first / satisfaction-second
# split (breaks the single pass B model).
#
# The def-time check here catches the "impl is missing the method
# entirely" case — the common regression path — using the parser-
# level `findFunctionDefs` API directly, no resolver-side lookup
# needed. Signature parity is checked one phase later by the def
# def analyzer's deep constraint check (analyzeDefModuleArgumentType
# concretizes the contract's funcDefs and probes the impl's
# funcDefIndex via findImplDef), which runs after every signature is
# resolved.

proc resolveModuleArgumentType(fileCtx: FileContext, typeCtx: TypeContext, argType: ArgumentType, argModule: Module, dataDef: DataDef): Result[ResolvedModuleArgumentType, string] =
  let requires = ? fileCtx.inferGenerics(dataDef)
  if argType.impls.len != requires.len:
    err(fmt"{argType.loc} type `{argModule.name.asl}` expects {requires.len} impls but found {argType.impls.len}")
  else:
    var impls: seq[ResolvedArgumentType]
    for (base, impl) in zip(requires, argType.impls):
      let resolvedImpl = ? resolveArgumentType(fileCtx, typeCtx, impl)
      ? resolvedImpl.satisfies(base, typeCtx)
      impls.add(resolvedImpl)
    ok(newResolvedModuleArgumentType(argModule, impls, argType.loc))

proc resolveGenericArgumentType(typeCtx: TypeContext, argType: ArgumentType, argGeneric: Generic): Result[ResolvedGenericArgumentType, string] =
  case typeCtx.kind:
  of tckModule:
    if argType.impls.len == 0:
      ok(newResolvedGenericArgumentType(argGeneric, argType.loc))
    else:
      err(fmt"{argGeneric.loc} generic `{argGeneric.name.asl}` is not allowed to have impls")
  of tckGeneric:
    if argType.impls.len == 0:
      if argGeneric == typeCtx.generic:
        ok(newResolvedGenericArgumentType(argGeneric, argType.loc))
      else:
        err(fmt"{argType.loc} type `{argGeneric.name.asl}` is a generic and can not be used within the generic block")
    else:
      err(fmt"{argType.loc} type `{argGeneric.name.asl}` is a generic and does not support further impls")

proc resolveArgumentType(fileCtx: FileContext, typeCtx: TypeContext, argType: ArgumentType): Result[ResolvedArgumentType, string] =
  let typ = ? fileCtx.findType(argType.root)
  case typ.kind:
  of tkGeneric:
    let resolvedGenericType = ? resolveGenericArgumentType(typeCtx, argType, typ.generic)
    ok(newResolvedArgumentType(resolvedGenericType))
  of tkModule:
    if typ.module.data.isNone:
      err(fmt"{argType.loc} module `{argType.root.asl}` is not a data module")
    else:
      let resolvedModuleType = ? resolveModuleArgumentType(fileCtx, typeCtx, argType, typ.module, typ.module.data.get)
      ok(newResolvedArgumentType(resolvedModuleType))

proc resolveArgumentDef(fileCtx: FileContext, typeCtx: TypeContext, argDef: ArgumentDef): Result[ResolvedArgumentDef, string] =
  let resolvedArgumentType = ? resolveArgumentType(fileCtx, typeCtx, argDef.argType)
  ok(newResolvedArgumentDef(argDef, resolvedArgumentType))

proc resolveStructDefHeader(fileCtx: FileContext, header: StructDefHeader): Result[seq[ResolvedGenericArgumentType], string] =
  var resolvedRequires: seq[ResolvedGenericArgumentType]
  for index, impl in header.requires:
    let generic = ? fileCtx.findGeneric(impl)
    let genericType = newResolvedGenericArgumentType(generic, impl.loc)
    resolvedRequires.add(genericType)
  ok(resolvedRequires)

proc resolveFields(fileCtx: FileContext, typeCtx: TypeContext, fields: seq[ArgumentDef]): Result[seq[ResolvedArgumentDef], string] =
  var resolvedFields: seq[ResolvedArgumentDef]
  for field in fields:
    let resolvedField = ? resolveArgumentDef(fileCtx, typeCtx, field)
    resolvedFields.add(resolvedField)
  ok(resolvedFields)

proc resolveStructDef(fileCtx: FileContext, typeCtx: TypeContext, struct: StructDef): Result[ResolvedStructDef, string] =
  let resolvedRequires = ? resolveStructDefHeader(fileCtx, struct.header)
  let resolvedFields = ? resolveFields(fileCtx, typeCtx, struct.fields)

  var genericFields: OrderedSet[ResolvedGenericArgumentType]
  for field in resolvedFields:
    case field.argType.kind:
    of ratkModule: discard
    of ratkGeneric: genericFields.incl(field.argType.generic)

  if resolvedRequires.len > 0:
    if genericFields.len > 0:
      err(fmt"{struct.loc} struct with explicit generic requirements does not support generic fields")
    else:
      ok(newResolvedStructDef(struct, resolvedRequires, resolvedFields))
  else:
    ok(newResolvedStructDef(struct, genericFields.toSeq, resolvedFields))

proc resolveVariantDef(fileCtx: FileContext, typeCtx: TypeContext, variant: VariantDef): Result[ResolvedVariant, string] =
  let resolvedFields = ? resolveFields(fileCtx, typeCtx, variant.fields)
  ok(newResolvedVariantDef(variant, resolvedFields))

proc resolveUnionDef(fileCtx: FileContext, typeCtx: TypeContext, union: UnionDef): Result[ResolvedUnionDef, string] =
  var resolvedVariants: seq[ResolvedVariant]
  for variant in union.variants:
    let resolvedVariant = ? resolveVariantDef(fileCtx, typeCtx, variant)
    resolvedVariants.add(resolvedVariant)
  ok(newResolvedUnionDef(union, resolvedVariants))

proc resolveDataDef(fileCtx: FileContext, typeCtx: TypeContext, data: DataDef): Result[ResolvedData, string] =
  case data.kind:
  of ddkLiteral:
    let resolvedLiteralDef = ? newResolvedLiteralDef(data.literal)
    ok(newResolvedData(resolvedLiteralDef))
  of ddkStruct:
    let resolvedStructDef = ? resolveStructDef(fileCtx, typeCtx, data.struct)
    ok(newResolvedData(resolvedStructDef))
  of ddkUnion:
    let resolvedUnionDef = ? resolveUnionDef(fileCtx, typeCtx, data.union)
    ok(newResolvedData(resolvedUnionDef))

proc resolveFunctionDef(fileCtx: FileContext, typeCtx: TypeContext, def: FunctionDef): Result[ResolvedFunctionDef, string] =
  var resolvedArgDefs: seq[ResolvedArgumentDef]
  for argDef in def.args:
    let resolvedArgDef = ? resolveArgumentDef(fileCtx, typeCtx, argDef)
    resolvedArgDefs.add(resolvedArgDef)

  let resolvedReturnType = ? resolveArgumentType(fileCtx, typeCtx, def.returns)
  ok(newResolvedFunctionDef(def, resolvedArgDefs, resolvedReturnType))

proc resolveExternFunction(fileCtx: FileContext, typeCtx: TypeContext, function: ExternFunction): Result[ResolvedExternFunction, string] =
  let resolvedFunctionDef = ? resolveFunctionDef(fileCtx, typeCtx, function.def)
  ok(newResolvedExternFunction(function, resolvedFunctionDef))

proc resolveLiteral(fileCtx: FileContext, literal: Literal): Result[ResolvedLiteral, string] =
  let module = ? fileCtx.findModule(literal.defaultType)
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
proc resolveExpression(fileCtx: FileContext, typeCtx: TypeContext, funcCtx: FunctionContext, expression: Expression): Result[ResolvedExpression, string]
proc resolveStatement(fileCtx: FileContext, typeCtx: TypeContext, funcCtx: FunctionContext, statement: Statement): Result[ResolvedStatement, string]

proc resolveFunctionCall(fileCtx: FileContext, typeCtx: TypeContext, funcCtx: FunctionContext, fncall: FunctionCall): Result[ResolvedFunctionCall, string] =
  let typ = ? fileCtx.findType(fncall.root)
  let access =
    case typ.kind:
    of tkModule: typeCtx.access(typ.module)
    # Generic funcDefs are implicitly public — access is vacuous.
    of tkGeneric: faPublic
  let defs = ? typ.findFunctionDefs(fncall.name, fncall.arity, access)
  assert(defs.len > 0, "[BUG] - findFunctionDefs never returns an empty overload list")
  var resolvedArgs: seq[ResolvedExpression]
  for arg in fncall.args:
    let resolvedArg = ? resolveExpression(fileCtx, typeCtx, funcCtx, arg)
    resolvedArgs.add(resolvedArg)
  ok(newResolvedFunctionCall(fncall, typ, resolvedArgs))

proc resolveStructRef(fileCtx: FileContext, typeCtx: TypeContext, structRef: StructRef): Result[ResolvedStructRef, string] =
  let structModule = ? fileCtx.findModule(structRef.module)
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
        if struct.header.requires.len == 0:
          ok(newResolvedStructRef(structRef, structModule, struct))
        else:
          err(fmt"{structRef.loc} module `{structRef.module.asl}` expects {struct.header.requires.len} impls")
      else:
        let resolvedModuleArgType = ? resolveModuleArgumentType(fileCtx, typeCtx, structRef.argType, structModule, moduleData)
        ok(newResolvedStructRef(structRef, resolvedModuleArgType, struct))

proc resolveKeywordArguments(fileCtx: FileContext, typeCtx: TypeContext, funcCtx: FunctionContext, struct: StructDef, kwargList: KeywordArgumentList): Result[seq[ResolvedKeywordArgument], string] =
  var resolvedKwargs = newSeq[ResolvedKeywordArgument](struct.fields.len)
  var fieldMap: Table[int, Location]
  for kwarg in kwargList.items:
    let fieldId = ? struct.findFieldId(kwarg.name)
    if fieldId in fieldMap:
      let loc = fieldMap[fieldId]
      return err(fmt"{kwarg.loc} duplicate field `{kwarg.name.asl}` encountered, see previous instance at {loc}")
    else:
      let resolvedExpression = ? resolveExpression(fileCtx, typeCtx, funcCtx, kwarg.expression)
      resolvedKwargs[fieldId] = newResolvedKeywordArgument(kwarg, resolvedExpression)
      fieldMap[fieldId] = kwarg.loc

  if fieldMap.len != struct.fields.len:
    err(fmt"{kwargList.loc} expected `{struct.fields.len}` fields but `{fieldMap.len}` were given")
  else:
    ok(resolvedKwargs)

proc resolveStructInitializer(fileCtx: FileContext, typeCtx: TypeContext, funcCtx: FunctionContext, init: StructInitializer): Result[ResolvedStructInitializer, string] =
  let resolvedStructRef = ? resolveStructRef(fileCtx, typeCtx, init.structRef)
  let resolvedKeywordArgs = ? resolveKeywordArguments(fileCtx, typeCtx, funcCtx, resolvedStructRef.struct, init.kwargList)
  ok(newResolvedStructInitializer(init, resolvedStructRef, resolvedKeywordArgs))

proc resolveUnionRef(fileCtx: FileContext, typeCtx: TypeContext, unionRef: UnionRef): Result[ResolvedUnionRef, string] =
  let unionModule = ? fileCtx.findModule(unionRef.module)
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
        let resolvedArgType = ? resolveModuleArgumentType(fileCtx, typeCtx, unionRef.argType, unionModule, moduleData)
        ok(newResolvedUnionRef(unionRef, resolvedArgType, variant))

proc resolveKeywordArguments(fileCtx: FileContext, typeCtx: TypeContext, funcCtx: FunctionContext, variant: VariantDef, kwargList: KeywordArgumentList): Result[seq[ResolvedKeywordArgument], string] =
  var resolvedKwargs = newSeq[ResolvedKeywordArgument](variant.fields.len)
  var fieldMap: Table[int, Location]
  for kwarg in kwargList.items:
    let fieldId = ? variant.findFieldId(kwarg.name)
    if fieldId in fieldMap:
      let loc = fieldMap[fieldId]
      return err(fmt"{kwarg.loc} duplicate field `{kwarg.name.asl}` encountered, see previous instance at {loc}")
    else:
      let resolvedExpression = ? resolveExpression(fileCtx, typeCtx, funcCtx, kwarg.expression)
      resolvedKwargs[fieldId] = newResolvedKeywordArgument(kwarg, resolvedExpression)
      fieldMap[fieldId] = kwarg.loc

  if fieldMap.len != variant.fields.len:
    err(fmt"{kwargList.loc} expected `{variant.fields.len}` fields but `{fieldMap.len}` were given")
  else:
    ok(resolvedKwargs)

proc resolveUnionInitializer(fileCtx: FileContext, typeCtx: TypeContext, funcCtx: FunctionContext, unionInit: UnionInitializer): Result[ResolvedUnionInitializer, string] =
  let resolvedUnionRef = ? resolveUnionRef(fileCtx, typeCtx, unionInit.unionRef)
  let resolvedKeywordArgs = ? resolveKeywordArguments(fileCtx, typeCtx, funcCtx, resolvedUnionRef.variant, unionInit.kwargList)
  ok(newResolvedUnionInitializer(unionInit, resolvedUnionRef, resolvedKeywordArgs))

proc resolveLiteralInitializer(fileCtx: FileContext, typeCtx: TypeContext, init: LiteralInitializer): Result[ResolvedLiteralInitializer, string] =
  let module = ? fileCtx.findModule(init.module)
  if module.data.isNone:
    err(fmt"{init.loc} expected module `{init.module.asl}` to be a literal but found none")
  else:
    let moduleData = module.data.get
    case moduleData.kind:
    of ddkStruct: err(fmt"{init.loc} expected module `{init.module.asl}` to be literal but found struct")
    of ddkUnion: err(fmt"{init.loc} expected module `{init.module.asl}` to be literal but found union")
    of ddkLiteral:
      let resolvedModuleArgType = ? resolveModuleArgumentType(fileCtx, typeCtx, init.argType, module, moduleData)
      ok(newResolvedLiteralInitializer(init, resolvedModuleArgType, moduleData.literal))

proc resolveInitializer(fileCtx: FileContext, typeCtx: TypeContext, funcCtx: FunctionContext, initializer: Initializer): Result[ResolvedInitializer, string] =
  case initializer.kind:
  of ikLiteral:
    let resolvedLiteralInit = ? resolveLiteralInitializer(fileCtx, typeCtx, initializer.literal)
    ok(newResolvedInitializer(resolvedLiteralInit))
  of ikStruct:
    let resolvedStructInit = ? resolveStructInitializer(fileCtx, typeCtx, funcCtx, initializer.struct)
    ok(newResolvedInitializer(resolvedStructInit))
  of ikUnion:
    let resolvedUnionInit = ? resolveUnionInitializer(fileCtx, typeCtx, funcCtx, initializer.union)
    ok(newResolvedInitializer(resolvedUnionInit))

proc resolveCasePattern(casePattern: CasePattern): Result[ResolvedCasePattern, string] =
  case casePattern.kind:
  of cpkInteger:
    ok(newResolvedCasePattern(casePattern.intLit))
  of cpkVariable:
    ok(newResolvedCasePattern(casePattern.variable))
  of cpkUnion:
    ok(newResolvedCasePattern(casePattern.variant))

proc resolveCaseBlock(fileCtx: FileContext, typeCtx: TypeContext, funcCtx: FunctionContext, caseBlock: CaseBlock): Result[ResolvedCaseBlock, string] =
  var caseCtx = funcCtx
  let resolvedCasePattern = ? resolveCasePattern(caseBlock.pattern)
  caseCtx = caseCtx.update(resolvedCasePattern)

  var resolvedStatements: seq[ResolvedStatement]
  for statement in caseBlock.statements:
    let resolvedStatement = ? resolveStatement(fileCtx, typeCtx, caseCtx, statement)
    resolvedStatements.add(resolvedStatement)
    caseCtx = caseCtx.update(resolvedStatement)
  ok(newResolvedCaseBlock(caseBlock, resolvedCasePattern, resolvedStatements))

proc resolveMatchExpression(fileCtx: FileContext, typeCtx: TypeContext, funcCtx: FunctionContext, match: MatchExpression): Result[ResolvedMatchExpression, string] =
  let resolvedSubject = ? resolveExpression(fileCtx, typeCtx, funcCtx, match.subject)
  var resolvedCaseBlocks: seq[ResolvedCaseBlock]
  for caseBlock in match.cases:
    let resolvedCaseBlock = ? resolveCaseBlock(fileCtx, typeCtx, funcCtx, caseBlock)
    resolvedCaseBlocks.add(resolvedCaseBlock)
  ok(newResolvedMatchExpression(match, resolvedSubject, resolvedCaseBlocks))

proc resolveExpression(fileCtx: FileContext, typeCtx: TypeContext, funcCtx: FunctionContext, expression: Expression): Result[ResolvedExpression, string] =
  case expression.kind:
  of ekLiteral:
    let resolvedLiteral = ? resolveLiteral(fileCtx, expression.literal)
    ok(newResolvedExpression(resolvedLiteral))
  of ekGetter:
    let resolvedGetter = ? resolveGetter(funcCtx, expression.getter)
    ok(newResolvedExpression(resolvedGetter))
  of ekVariable:
    let resolvedVariable = ? resolveVariable(funcCtx, expression.variable)
    ok(newResolvedExpression(resolvedVariable))
  of ekFnCall:
    let resolvedFunctionCall = ? resolveFunctionCall(fileCtx, typeCtx, funcCtx, expression.fncall)
    ok(newResolvedExpression(resolvedFunctionCall))
  of ekInitializer:
    let resolvedInitializer = ? resolveInitializer(fileCtx, typeCtx, funcCtx, expression.initializer)
    ok(newResolvedExpression(resolvedInitializer))
  of ekMatch:
    let resolvedMatchExpr = ? resolveMatchExpression(fileCtx, typeCtx, funcCtx, expression.match)
    ok(newResolvedExpression(resolvedMatchExpr))

proc resolveAssignment(fileCtx: FileContext, typeCtx: TypeContext, funcCtx: FunctionContext, assignment: Assignment): Result[ResolvedAssignment, string] =
  let resolvedExpression = ? resolveExpression(fileCtx, typeCtx, funcCtx, assignment.expression)
  ok(newResolvedAssignment(assignment, resolvedExpression))

proc resolveSetter(fileCtx: FileContext, typeCtx: TypeContext, funcCtx: FunctionContext, setter: Setter): Result[ResolvedSetter, string] =
  let resolvedGetter = ? resolveGetter(funcCtx, setter.target)
  let resolvedExpression = ? resolveExpression(fileCtx, typeCtx, funcCtx, setter.expression)
  ok(newResolvedSetter(setter, resolvedGetter, resolvedExpression))

proc resolveStatement(fileCtx: FileContext, typeCtx: TypeContext, funcCtx: FunctionContext, statement: Statement): Result[ResolvedStatement, string] =
  case statement.kind:
  of skExpr:
    let resolvedExpression = ? resolveExpression(fileCtx, typeCtx, funcCtx, statement.expression)
    ok(newResolvedStatement(resolvedExpression))
  of skAssignment:
    let resolvedAssignment = ? resolveAssignment(fileCtx, typeCtx, funcCtx, statement.assignment)
    ok(newResolvedStatement(resolvedAssignment))
  of skSetter:
    let resolvedMutation = ? resolveSetter(fileCtx, typeCtx, funcCtx, statement.setter)
    ok(newResolvedStatement(resolvedMutation))

proc resolveUserFunction(fileCtx: FileContext, typeCtx: TypeContext, function: UserFunction): Result[ResolvedUserFunction, string] =
  assert(function.decorators.len == 0, fmt"{function.loc} todo: resolve decorators in user function")
  let resolvedFuncDef = ? resolveFunctionDef(fileCtx, typeCtx, function.def)

  var funcCtx = ? newFunctionContext(resolvedFuncDef)
  var resolvedStmts: seq[ResolvedStatement]
  for statement in function.statements:
    let resolvedStatement = ? resolveStatement(fileCtx, typeCtx, funcCtx, statement)
    resolvedStmts.add(resolvedStatement)
    funcCtx = funcCtx.update(resolvedStatement)

  ok(newResolvedUserFunction(function, resolvedFuncDef, resolvedStmts))

proc resolveFunction(fileCtx: FileContext, typeCtx: TypeContext, function: Function): Result[ResolvedFunction, string] =
  case function.kind:
  of fkUser:
    let resolvedUserFunction = ? resolveUserFunction(fileCtx, typeCtx, function.user)
    ok(newResolvedFunction(resolvedUserFunction))
  of fkExtern:
    let resolvedExternFunction = ? resolveExternFunction(fileCtx, typeCtx, function.extern)
    ok(newResolvedFunction(resolvedExternFunction))

proc resolveModule(fileCtx: FileContext, module: Module): Result[ResolvedModule, string] =
  let typeCtx = newTypeContext(module)
  let resolvedData =
    if module.data.isSome:
      let resolvedDataDef = ? resolveDataDef(fileCtx, typeCtx, module.data.get)
      some(resolvedDataDef)
    else:
      none(ResolvedData)

  var resolvedFunctions: seq[ResolvedFunction]
  for function in module.functions:
    let resolvedFunction = ? resolveFunction(fileCtx, typeCtx, function)
    resolvedFunctions.add(resolvedFunction)

  ok(newResolvedModule(module, resolvedData, resolvedFunctions))

proc resolveGeneric(fileCtx: FileContext, generic: Generic): Result[ResolvedGeneric, string] =
  let typeCtx = newTypeContext(generic)
  var resolvedFuncDefs: seq[ResolvedFunctionDef]
  for def in generic.defs:
    let resolvedFuncDef = ? resolveFunctionDef(fileCtx, typeCtx, def)
    resolvedFuncDefs.add(resolvedFuncDef)

  ok(newResolvedGeneric(generic, resolvedFuncDefs))

proc resolveType(fileCtx: FileContext, typ: Type): Result[ResolvedType, string] =
  assert(typ.decorators.len == 0, fmt"{typ.loc} types do not support decorators")
  case typ.kind:
  of tkGeneric:
    let resolvedGeneric = ? resolveGeneric(fileCtx, typ.generic)
    ok(newResolvedType(resolvedGeneric))
  of tkModule:
    let resolvedModule = ? resolveModule(fileCtx, typ.module)
    ok(newResolvedType(resolvedModule))

proc resolveExplicitImport(imp: Import, impFile: parser.File): Result[seq[ResolvedImportedType], string] =
  var resolvedImpTypes: seq[ResolvedImportedType]
  for impType in imp.names:
    let exportedType = ? impFile.findExportedType(impType.name)
    let resolvedImpType = newResolvedImportedType(impType, exportedType)
    resolvedImpTypes.add(resolvedImpType)
  ok(resolvedImpTypes)

proc resolveShorthandImport(imp: Import, impFile: parser.File): Result[seq[ResolvedImportedType], string] =
  var resolvedImpTypes: seq[ResolvedImportedType]
  for typ in impFile.publicTypes:
    let resolvedImpType = newResolvedImportedType(typ)
    resolvedImpTypes.add(resolvedImpType)
  ok(resolvedImpTypes)

proc resolveImport(app: App, imp: Import): Result[ResolvedImport, string] =
  let impFile = ? app.findFile(imp.absPath)
  let resolvedImpTypes =
    case imp.kind:
    of ikExplicit: ? resolveExplicitImport(imp, impFile)
    of ikShorthand: ? resolveShorthandImport(imp, impFile)
  ok(newResolvedImport(imp, impFile, resolvedImpTypes))

proc resolveImports(app: App, imports: seq[Import]): Result[seq[ResolvedImport], string] =
  var resolvedImports: seq[ResolvedImport]
  for imp in imports:
    let resolvedImport = ? resolveImport(app, imp)
    resolvedImports.add(resolvedImport)
  ok(resolvedImports)

proc resolveFile(app: App, file: parser.File): Result[ResolvedFile, string] =
  let resolvedImports = ? resolveImports(app, file.imports)
  var fileCtx = ? newFileContext(resolvedImports, file.types)

  var resolvedTypes: seq[ResolvedType]
  for typ in file.types:
    let resolvedType = ? resolveType(fileCtx, typ)
    resolvedTypes.add(resolvedType)

  ok(newResolvedFile(file, resolvedImports, resolvedTypes, fileCtx))

proc resolve*(app: App): Result[ResolvedApp, string] =
  var resolvedFiles: seq[ResolvedFile]
  for file in app.files:
    let resolvedFile = ? resolveFile(app, file)
    resolvedFiles.add(resolvedFile)
  ok(newResolvedApp(resolvedFiles))