import results, sequtils, strformat, tables, options

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
import ./resolver/filescope
export filescope

import ./resolver/functionscope
export functionscope

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


# resolveArgumentType (both context overloads — module context is the
# no-Generic form; generic context takes an enclosing `generic`) is
# called by `resolveArgumentTypeImpls` when walking a use-site's impl
# list.
proc resolveArgumentType*(fileScope: FileScope, argType: ArgumentType): Result[ResolvedArgumentType, string]

proc resolveArgumentType*(fileScope: FileScope, generic: Generic, argType: ArgumentType): Result[ResolvedArgumentType, string]

# Constraint-satisfaction check: does `impl` provide every funcDef
# the required generic `base` mandates? Retired the analyzer's
# equivalent def-time check and moved it here so
# ResolvedModuleArgumentType.impls is a provably valid value by the
# time it leaves the resolver.
#
# Verification is deliberately SHALLOW — by `(name, arity)` at the
# parser level, not by concretized-signature comparison. Signature-
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
# needed. Signature-parity mismatches surface at the first call site
# instead of the impl declaration; in practice both sites are usually
# in the same file, and error location tracking still points at the
# offending declaration.

proc resolveArgumentTypeImpls(fileScope: FileScope, argType: ArgumentType, argModule: Module, bases: seq[Generic]): Result[ResolvedModuleArgumentType, string] =
  var impls: seq[ResolvedArgumentType]
  for (base, impl) in zip(bases, argType.impls):
    let resolvedImpl = ? resolveArgumentType(fileScope, impl)
    ? satisfies(resolvedImpl, base)
    impls.add(resolvedImpl)
  ok(newResolvedModuleArgumentType(argModule, impls, argType.loc))

proc resolveArgumentTypeImpls(fileScope: FileScope, generic: Generic, argType: ArgumentType, argModule: Module, bases: seq[Generic]): Result[ResolvedModuleArgumentType, string] =
  var impls: seq[ResolvedArgumentType]
  for (base, impl) in zip(bases, argType.impls):
    let resolvedImpl = ? resolveArgumentType(fileScope, generic, impl)
    ? satisfies(resolvedImpl, base)
    impls.add(resolvedImpl)
  ok(newResolvedModuleArgumentType(argModule, impls, argType.loc))

proc resolveDataModuleArgumentType(fileScope: FileScope, argType: ArgumentType, argModule: Module, dataDef: DataDef): Result[ResolvedModuleArgumentType, string] =
  let requires = ? fileScope.inferGenerics(dataDef)
  if argType.impls.len != requires.len:
    err(fmt"{argType.loc} type `{argModule.name.asl}` expects {requires.len} impls but found {argType.impls.len}")
  else:
    resolveArgumentTypeImpls(fileScope, argType, argModule, requires)

proc resolveDataModuleArgumentType(fileScope: FileScope, generic: Generic, argType: ArgumentType, argModule: Module, dataDef: DataDef): Result[ResolvedModuleArgumentType, string] =
  let requires = ? fileScope.inferGenerics(dataDef)
  if argType.impls.len != requires.len:
    err(fmt"{argType.loc} type `{argModule.name.asl}` expects {requires.len} impls but found {argType.impls.len}")
  else:
    resolveArgumentTypeImpls(fileScope, generic, argType, argModule, requires)

proc resolveModuleArgumentType(fileScope: FileScope, argType: ArgumentType, argModule: Module): Result[ResolvedModuleArgumentType, string] =
  if argModule.data.isSome:
    resolveDataModuleArgumentType(fileScope, argType, argModule, argModule.data.get)
  else:
    if argType.impls.len == 0:
      ok(newResolvedModuleArgumentType(argModule, argType.loc))
    else:
      err(fmt"{argType.loc} type `{argModule.name.asl}` does not require impl types")

# resolveModuleArgumentType — generic context. Mirrors module-context;
# the impl-list validation delegates to the same
# `resolveDataModuleArgumentType` helper. The self-only rule for
# generic references lives on `resolveGenericArgumentType`, not here.
proc resolveModuleArgumentType(fileScope: FileScope, generic: Generic, argType: ArgumentType, argModule: Module): Result[ResolvedModuleArgumentType, string] =
  if argModule.data.isSome:
    resolveDataModuleArgumentType(fileScope, generic, argType, argModule, argModule.data.get)
  else:
    if argType.impls.len == 0:
      ok(newResolvedModuleArgumentType(argModule, argType.loc))
    else:
      err(fmt"{argType.loc} type `{argModule.name.asl}` does not require impl types")

proc resolveGenericArgumentType(generic: Generic, argType: ArgumentType, argGeneric: Generic): Result[ResolvedGenericArgumentType, string] =
  if argType.impls.len == 0:
    if argGeneric == generic:
      ok(newResolvedGenericArgumentType(argGeneric, argType.loc))
    else:
      err(fmt"{argType.loc} type `{argGeneric.name.asl}` is a generic and can not be used within the generic block")
  else:
    err(fmt"{argType.loc} type `{argGeneric.name.asl}` is a generic and does not support further impls")

proc resolveGenericArgumentType(argType: ArgumentType, argGeneric: Generic): Result[ResolvedGenericArgumentType, string] =
  if argType.impls.len == 0:
    ok(newResolvedGenericArgumentType(argGeneric, argGeneric.loc))
  else:
    err(fmt"{argGeneric.loc} generic `{argGeneric.name.asl}` is not allowed to have impls")

# resolveArgumentType — both context overloads.
proc resolveArgumentType*(fileScope: FileScope, argType: ArgumentType): Result[ResolvedArgumentType, string] =
  let typ = ? fileScope.findType(argType.root)
  case typ.kind:
  of tkGeneric:
    let resolvedGenericType = ? resolveGenericArgumentType(argType, typ.generic)
    ok(newResolvedArgumentType(resolvedGenericType))
  of tkModule:
    let resolvedModuleType = ? resolveModuleArgumentType(fileScope, argType, typ.module)
    ok(newResolvedArgumentType(resolvedModuleType))

proc resolveArgumentType*(fileScope: FileScope, generic: Generic, argType: ArgumentType): Result[ResolvedArgumentType, string] =
  let typ = ? fileScope.findType(argType.root)
  case typ.kind:
  of tkGeneric:
    let resolvedGenericType = ? resolveGenericArgumentType(generic, argType, typ.generic)
    ok(newResolvedArgumentType(resolvedGenericType))
  of tkModule:
    let resolvedModuleType = ? resolveModuleArgumentType(fileScope, generic, argType, typ.module)
    ok(newResolvedArgumentType(resolvedModuleType))

# resolveDataType — post-resolution guard. Confirms the resolved
# argument's underlying module has a data block (or that we're
# pointing at an unsubstituted generic, which is acceptable). Reads
# the parser Module through `resolvedArgType.module.parsed`; no
# context parameter is needed because every ResolvedModuleArgumentType
# carries its parser back-ref.
proc resolveDataType*(resolvedArgType: ResolvedArgumentType, argType: ArgumentType): Result[void, string] =
  case resolvedArgType.kind:
  of ratkGeneric: ok()
  of ratkModule:
    let parsedModule = resolvedArgType.module.parsed
    if parsedModule.data.isSome: ok()
    else: err(fmt"{argType.loc} module `{parsedModule.name.asl}` is not a literal/struct/union")

proc resolveArgumentDef*(fileScope: FileScope, argDef: ArgumentDef): Result[ResolvedArgumentDef, string] =
  let resolvedArgumentType = ? resolveArgumentType(fileScope, argDef.argType)
  ? resolveDataType(resolvedArgumentType, argDef.argType)
  ok(newResolvedArgumentDef(argDef, resolvedArgumentType))

proc resolveArgumentDef*(fileScope: FileScope, generic: Generic, argDef: ArgumentDef): Result[ResolvedArgumentDef, string] =
  let resolvedArgumentType = ? resolveArgumentType(fileScope, generic, argDef.argType)
  ? resolveDataType(resolvedArgumentType, argDef.argType)
  ok(newResolvedArgumentDef(argDef, resolvedArgumentType))

proc accumulateGenericPosition(genericTypeIndex: var Table[ResolvedGenericArgumentType, int], field: ResolvedArgumentDef) =
  ## Assigns the next position to each new generic encountered in
  ## field types. Same name across multiple fields keeps its first
  ## position — the analyzer's GenericImplMap binds one generic to
  ## one concrete type per construction, so duplicate occurrences
  ## are semantically benign (any conflict surfaces at the init site
  ## via merge()). Generic-uniqueness inside an explicit `struct(...)`
  ## header is enforced at construction time by
  ## `validateRequiresNameConflict` in `parser/structdef.nim`.
  case field.argType.kind:
  of ratkModule: discard
  of ratkGeneric:
    let genericType = field.argType.generic
    if genericType notin genericTypeIndex:
      genericTypeIndex[genericType] = genericTypeIndex.len

proc resolveStructDef*(fileScope: FileScope, struct: StructDef): Result[ResolvedStructDef, string] =
  var resolvedFields: seq[ResolvedArgumentDef]
  var genericTypeIndex: Table[ResolvedGenericArgumentType, int]
  for field in struct.fields:
    let resolvedField = ? resolveArgumentDef(fileScope, field)
    genericTypeIndex.accumulateGenericPosition(resolvedField)
    resolvedFields.add(resolvedField)

  if struct.header.requires.len > 0 and genericTypeIndex.len > 0:
    return err(fmt"{struct.loc} struct with explicit generic requirements does not support generic fields")

  var resolvedRequires: seq[ResolvedGenericArgumentType]
  for index, generic in struct.header.requires:
    let typ = ? fileScope.findType(generic)
    case typ.kind:
    of tkModule:
      return err(fmt"{generic.loc} type `{generic.asl}` is a module but expected generic")
    of tkGeneric:
      let genericType = newResolvedGenericArgumentType(typ.generic, generic.loc)
      resolvedRequires.add(genericType)
  ok(newResolvedStructDef(struct, resolvedRequires, resolvedFields, genericTypeIndex))

# NOTE: `genericTypeIndex` is the union's shared position table — mutated
# in place as each variant's fields contribute new generics (in
# declaration order); not returned because the union accumulates it.
proc resolveVariant(fileScope: FileScope, variant: VariantDef, genericTypeIndex: var Table[ResolvedGenericArgumentType, int]): Result[ResolvedVariant, string] =
  var resolvedFields: seq[ResolvedArgumentDef]
  for field in variant.fields:
    let resolvedField = ? resolveArgumentDef(fileScope, field)
    genericTypeIndex.accumulateGenericPosition(resolvedField)
    resolvedFields.add(resolvedField)
  ok(newResolvedVariant(variant, resolvedFields))

proc resolveUnionDef*(fileScope: FileScope, union: UnionDef): Result[ResolvedUnionDef, string] =
  var resolvedVariants: seq[ResolvedVariant]
  var genericTypeIndex: Table[ResolvedGenericArgumentType, int]
  for variant in union.variants:
    let resolvedVariant = ? resolveVariant(fileScope, variant, genericTypeIndex)
    resolvedVariants.add(resolvedVariant)
  ok(newResolvedUnionDef(union, resolvedVariants, genericTypeIndex))

proc resolveDataDef*(fileScope: FileScope, data: DataDef): Result[ResolvedData, string] =
  case data.kind:
  of ddkLiteral:
    let resolvedLiteralDef = ? newResolvedLiteralDef(data.literal)
    ok(newResolvedData(resolvedLiteralDef))
  of ddkStruct:
    let resolvedStructDef = ? resolveStructDef(fileScope, data.struct)
    ok(newResolvedData(resolvedStructDef))
  of ddkUnion:
    let resolvedUnionDef = ? resolveUnionDef(fileScope, data.union)
    ok(newResolvedData(resolvedUnionDef))

proc resolveFunctionDef*(fileScope: FileScope, def: FunctionDef): Result[ResolvedFunctionDef, string] =
  var resolvedArgDefs: seq[ResolvedArgumentDef]
  for argDef in def.args:
    let resolvedArgDef = ? resolveArgumentDef(fileScope, argDef)
    resolvedArgDefs.add(resolvedArgDef)

  let resolvedReturnType = ? resolveArgumentType(fileScope, def.returns)
  ? resolveDataType(resolvedReturnType, def.returns)

  ok(newResolvedFunctionDef(def, resolvedArgDefs, resolvedReturnType))

proc resolveFunctionDef*(fileScope: FileScope, generic: Generic, def: FunctionDef): Result[ResolvedFunctionDef, string] =
  var resolvedArgDefs: seq[ResolvedArgumentDef]
  for argDef in def.args:
    let resolvedArgDef = ? resolveArgumentDef(fileScope, generic, argDef)
    resolvedArgDefs.add(resolvedArgDef)

  let resolvedReturnType = ? resolveArgumentType(fileScope, generic, def.returns)
  ? resolveDataType(resolvedReturnType, def.returns)

  ok(newResolvedFunctionDef(def, resolvedArgDefs, resolvedReturnType))

proc resolveExternFunction*(fileScope: FileScope, function: ExternFunction): Result[ResolvedExternFunction, string] =
  let resolvedFunctionDef = ? resolveFunctionDef(fileScope, function.def)
  ok(newResolvedExternFunction(function, resolvedFunctionDef))

proc resolveLiteral(fileScope: FileScope, literal: Literal): Result[ResolvedLiteral, string] =
  let literalModule = ? fileScope.findModule(literal.defaultType)
  ok(newResolvedLiteral(literal, literalModule))

proc resolveVariable*(scope: FunctionScope, variable: Identifier): Result[Identifier, string] =
  if variable notin scope:
    err(fmt"{variable.loc} variable `{variable.asl}` is not present in scope")
  else:
    ok(variable)

proc resolveGetter*(scope: FunctionScope, getter: Getter): Result[ResolvedGetter, string] =
  discard ? resolveVariable(scope, getter.source)
  ok(newResolvedGetter(getter))

proc resolveLiteralInitializer(fileScope: FileScope, literalInit: LiteralInitializer): Result[ResolvedLiteralInitializer, string] =
  let resolvedArgType = ? resolveArgumentType(fileScope, literalInit.argType)
  ok(newResolvedLiteralInitializer(literalInit, resolvedArgType))

# resolveExpression / resolveStatement form the body-cluster cycle.
proc resolveExpression*(fileScope: FileScope, scope: FunctionScope, expression: Expression): Result[ResolvedExpression, string]
proc resolveStatement*(fileScope: FileScope, funcScope: FunctionScope, statement: Statement): Result[ResolvedStatement, string]

proc resolveFunctionCall(fileScope: FileScope, scope: FunctionScope, fncall: FunctionCall): Result[ResolvedFunctionCall, string] =
  let typ = ? fileScope.findType(fncall.root)
  let funcDefs = ? typ.findFunctionDefs(fncall.name, fncall.args.len)
  if funcDefs.len == 0:
    err(fmt"{fncall.loc} generic `{typ.generic.name.asl}` does not have any function named `{fncall.name.asl}` with arity `{fncall.args.len}`")
  else:
    var resolvedArgs: seq[ResolvedExpression]
    for arg in fncall.args:
      let resolvedArg = ? resolveExpression(fileScope, scope, arg)
      resolvedArgs.add(resolvedArg)
    ok(newResolvedFunctionCall(fncall, typ, resolvedArgs))

proc resolveStructRef(fileScope: FileScope, structRef: StructRef): Result[ResolvedStructRef, string] =
  ## Resolves a StructRef into the one-shape (module + impls).
  ## Validates the "receiver-declares-requires ↔ impls-provided" match
  ## and delegates to resolveModuleArgumentType so the impls
  ## seq is arity- and constraint-checked at resolve time.
  let structModule = ? fileScope.findModule(structRef.module)
  if structModule.data.isNone:
    return err(fmt"{structRef.loc} module `{structModule.name.asl}` does not define a data block")
  let moduleData = structModule.data.get
  case moduleData.kind:
  of ddkLiteral:
    err(fmt"{structRef.loc} module `{structModule.name.asl}` is a literal type")
  of ddkUnion:
    err(fmt"{structRef.loc} module `{structModule.name.asl}` is a union type")
  of ddkStruct:
    let resolvedModuleArgType = ? resolveModuleArgumentType(fileScope, structRef.argType, structModule)
    ok(newResolvedStructRef(structRef, resolvedModuleArgType))

proc resolveStructInitializer(fileScope: FileScope, scope: FunctionScope, struct: StructInitializer): Result[ResolvedStructInitializer, string] =
  let resolvedStructRef = ? resolveStructRef(fileScope, struct.structRef)
  let structModule = module(resolvedStructRef)
  var structBlock = ? structModule.struct(struct.loc)
  if struct.kwargs.len != structBlock.fields.len:
    err(fmt"{struct.loc} struct `{structModule.name.asl}` expects `{structBlock.fields.len}` but `{struct.kwargs.len}` were given")
  else:
    var resolvedKeywordArgs = newSeq[ResolvedKeywordArgument](structBlock.fields.len)
    for kwarg in struct.kwargs:
      let fieldId = ? structBlock.findFieldId(kwarg.name)
      let resolvedExpression = ? resolveExpression(fileScope, scope, kwarg.expression)
      resolvedKeywordArgs[fieldId] = newResolvedKeywordArgument(kwarg, resolvedExpression)
    ok(newResolvedStructInitializer(struct, resolvedStructRef, resolvedKeywordArgs))

proc resolveUnionRef(fileScope: FileScope, unionRef: UnionRef): Result[ResolvedUnionRef, string] =
  ## Resolves a UnionRef into the one-shape (module + impls).
  ## Empty impls drive leave-as-is inference at the analyzer; non-empty
  ## impls are arity- and constraint-checked here via
  ## resolveModuleArgumentType so the analyzer can seed its
  ## GenericImplMap from the seq directly.
  let unionModule = ? fileScope.findModule(unionRef.module)
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
        ok(newResolvedUnionRef(unionRef, unionModule, union, variant))
      else:
        let resolvedArgType = ? resolveModuleArgumentType(fileScope, unionRef.argType, unionModule)
        ok(newResolvedUnionRef(unionRef, resolvedArgType, union, variant))

proc resolveKeywordArguments(fileScope: FileScope, scope: FunctionScope, variant: VariantDef, kwargList: KeywordArgumentList): Result[seq[ResolvedKeywordArgument], string] =
  var resolvedKwargs = newSeq[ResolvedKeywordArgument](variant.fields.len)
  var fieldMap: Table[int, Location]
  for kwarg in kwargList.items:
    let fieldId = ? variant.findFieldId(kwarg.name)
    if fieldId in fieldMap:
      let loc = fieldMap[fieldId]
      return err(fmt"{kwarg.loc} duplicate field `{kwarg.name.asl}` encountered, see previous instance at {loc}")
    else:
      let resolvedExpression = ? resolveExpression(fileScope, scope, kwarg.expression)
      resolvedKwargs[fieldId] = newResolvedKeywordArgument(kwarg, resolvedExpression)
      fieldMap[fieldId] = kwarg.loc

  if fieldMap.len != variant.fields.len:
    err(fmt"{kwargList.loc} expected `{variant.fields.len}` fields but `{fieldMap.len}` were given")
  else:
    ok(resolvedKwargs)

proc resolveUnionInitializer(fileScope: FileScope, scope: FunctionScope, unionInit: UnionInitializer): Result[ResolvedUnionInitializer, string] =
  let resolvedUnionRef = ? resolveUnionRef(fileScope, unionInit.unionRef)
  let resolvedKeywordArgs = ? resolveKeywordArguments(fileScope, scope, resolvedUnionRef.variant, unionInit.kwargList)
  ok(newResolvedUnionInitializer(unionInit, resolvedUnionRef, resolvedKeywordArgs))

proc resolveInitializer(fileScope: FileScope, scope: FunctionScope, initializer: Initializer): Result[ResolvedInitializer, string] =
  case initializer.kind:
  of ikLiteral:
    let resolvedLiteralInit = ? resolveLiteralInitializer(fileScope, initializer.literal)
    ok(newResolvedInitializer(resolvedLiteralInit))
  of ikStruct:
    let resolvedStructInit = ? resolveStructInitializer(fileScope, scope, initializer.struct)
    ok(newResolvedInitializer(resolvedStructInit))
  of ikUnion:
    let resolvedUnionInit = ? resolveUnionInitializer(fileScope, scope, initializer.union)
    ok(newResolvedInitializer(resolvedUnionInit))

proc resolveCasePattern*(casePattern: CasePattern): Result[ResolvedCasePattern, string] =
  case casePattern.kind:
  of cpkInteger:
    ok(newResolvedCasePattern(casePattern.intLit))
  of cpkVariable:
    ok(newResolvedCasePattern(casePattern.variable))
  of cpkUnion:
    ok(newResolvedCasePattern(casePattern.variant))

proc resolveCaseBlock(fileScope: FileScope, funcScope: FunctionScope, caseBlock: CaseBlock): Result[ResolvedCaseBlock, string] =
  var caseScope = funcScope
  let resolvedCasePattern = ? resolveCasePattern(caseBlock.pattern)
  caseScope = caseScope.update(resolvedCasePattern)

  var resolvedStatements: seq[ResolvedStatement]
  for statement in caseBlock.statements:
    let resolvedStatement = ? resolveStatement(fileScope, caseScope, statement)
    resolvedStatements.add(resolvedStatement)
    caseScope = caseScope.update(resolvedStatement)
  ok(newResolvedCaseBlock(caseBlock, resolvedCasePattern, resolvedStatements))

proc resolveMatchExpression(fileScope: FileScope, scope: FunctionScope, match: MatchExpression): Result[ResolvedMatchExpression, string] =
  let resolvedSubject = ? resolveExpression(fileScope, scope, match.subject)
  var resolvedCaseBlocks: seq[ResolvedCaseBlock]
  for caseBlock in match.cases:
    let resolvedCaseBlock = ? resolveCaseBlock(fileScope, scope, caseBlock)
    resolvedCaseBlocks.add(resolvedCaseBlock)
  ok(newResolvedMatchExpression(match, resolvedSubject, resolvedCaseBlocks))

proc resolveExpression*(fileScope: FileScope, scope: FunctionScope, expression: Expression): Result[ResolvedExpression, string] =
  case expression.kind:
  of ekLiteral:
    let resolvedLiteral = ? resolveLiteral(fileScope, expression.literal)
    ok(newResolvedExpression(resolvedLiteral))
  of ekGetter:
    let resolvedGetter = ? resolveGetter(scope, expression.getter)
    ok(newResolvedExpression(resolvedGetter))
  of ekVariable:
    let resolvedVariable = ? resolveVariable(scope, expression.variable)
    ok(newResolvedExpression(resolvedVariable))
  of ekFnCall:
    let resolvedFunctionCall = ? resolveFunctionCall(fileScope, scope, expression.fncall)
    ok(newResolvedExpression(resolvedFunctionCall))
  of ekInitializer:
    let resolvedInitializer = ? resolveInitializer(fileScope, scope, expression.initializer)
    ok(newResolvedExpression(resolvedInitializer))
  of ekMatch:
    let resolvedMatchExpr = ? resolveMatchExpression(fileScope, scope, expression.match)
    ok(newResolvedExpression(resolvedMatchExpr))

proc resolveAssignment(fileScope: FileScope, scope: FunctionScope, assignment: Assignment): Result[ResolvedAssignment, string] =
  let resolvedExpression = ? resolveExpression(fileScope, scope, assignment.expression)
  ok(newResolvedAssignment(assignment, resolvedExpression))

proc resolveSetter(fileScope: FileScope, funcScope: FunctionScope, setter: Setter): Result[ResolvedSetter, string] =
  let resolvedGetter = ? resolveGetter(funcScope, setter.target)
  let resolvedExpression = ? resolveExpression(fileScope, funcScope, setter.expression)
  ok(newResolvedSetter(setter, resolvedGetter, resolvedExpression))

proc resolveStatement*(fileScope: FileScope, funcScope: FunctionScope, statement: Statement): Result[ResolvedStatement, string] =
  case statement.kind:
  of skExpr:
    let resolvedExpression = ? resolveExpression(fileScope, funcScope, statement.expression)
    ok(newResolvedStatement(resolvedExpression))
  of skAssignment:
    let resolvedAssignment = ? resolveAssignment(fileScope, funcScope, statement.assignment)
    ok(newResolvedStatement(resolvedAssignment))
  of skSetter:
    let resolvedMutation = ? resolveSetter(fileScope, funcScope, statement.setter)
    ok(newResolvedStatement(resolvedMutation))

proc resolveUserFunction*(fileScope: FileScope, function: UserFunction): Result[ResolvedUserFunction, string] =
  assert(function.decorators.len == 0, fmt"{function.loc} todo: resolve decorators in user function")
  let resolvedFuncDef = ? resolveFunctionDef(fileScope, function.def)

  var funcScope = ? newFunctionScope(resolvedFuncDef)
  var resolvedStmts: seq[ResolvedStatement]
  for statement in function.statements:
    let resolvedStatement = ? resolveStatement(fileScope, funcScope, statement)
    resolvedStmts.add(resolvedStatement)
    funcScope = funcScope.update(resolvedStatement)

  ok(newResolvedUserFunction(function, resolvedFuncDef, resolvedStmts))

proc resolveFunction*(fileScope: FileScope, function: Function): Result[ResolvedFunction, string] =
  case function.kind:
  of fkUser:
    let resolvedUserFunction = ? resolveUserFunction(fileScope, function.user)
    ok(newResolvedFunction(resolvedUserFunction))
  of fkExtern:
    let resolvedExternFunction = ? resolveExternFunction(fileScope, function.extern)
    ok(newResolvedFunction(resolvedExternFunction))

proc resolveModule*(fileScope: FileScope, module: Module): Result[ResolvedModule, string] =
  let resolvedData =
    if module.data.isSome:
      let resolvedDataDef = ? resolveDataDef(fileScope, module.data.get)
      some(resolvedDataDef)
    else:
      none(ResolvedData)

  var resolvedFunctions: seq[ResolvedFunction]
  for function in module.functions:
    let resolvedFunction = ? resolveFunction(fileScope, function)
    resolvedFunctions.add(resolvedFunction)

  ok(newResolvedModule(module, resolvedData, resolvedFunctions))

proc resolveGeneric*(fileScope: FileScope, generic: Generic): Result[ResolvedGeneric, string] =
  var resolvedFuncDefs: seq[ResolvedFunctionDef]
  for def in generic.defs:
    let resolvedFuncDef = ? resolveFunctionDef(fileScope, generic, def)
    resolvedFuncDefs.add(resolvedFuncDef)

  ok(newResolvedGeneric(generic, resolvedFuncDefs))

proc resolveType*(fileScope: FileScope, typ: Type): Result[ResolvedType, string] =
  assert(typ.decorators.len == 0, fmt"{typ.loc} types do not support decorators")
  case typ.kind:
  of tkGeneric:
    let resolvedGeneric = ? resolveGeneric(fileScope, typ.generic)
    ok(newResolvedType(resolvedGeneric))
  of tkModule:
    let resolvedModule = ? resolveModule(fileScope, typ.module)
    ok(newResolvedType(resolvedModule))

proc resolveExplicitImport*(imp: Import, impFile: parser.File): Result[seq[ResolvedImportedType], string] =
  var resolvedImpTypes: seq[ResolvedImportedType]
  for impType in imp.names:
    let exportedType = ? impFile.findExportedType(impType.name)
    let resolvedImpType = newResolvedImportedType(impType, exportedType)
    resolvedImpTypes.add(resolvedImpType)
  ok(resolvedImpTypes)

proc resolveShorthandImport*(imp: Import, impFile: parser.File): Result[seq[ResolvedImportedType], string] =
  var resolvedImpTypes: seq[ResolvedImportedType]
  for typ in impFile.publicTypes:
    let resolvedImpType = newResolvedImportedType(typ)
    resolvedImpTypes.add(resolvedImpType)
  ok(resolvedImpTypes)

proc resolveImport*(app: App, imp: Import): Result[ResolvedImport, string] =
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

proc resolveFile*(app: App, file: parser.File): Result[ResolvedFile, string] =
  let resolvedImports = ? resolveImports(app, file.imports)
  var fileScope = ? newFileScope(resolvedImports, file.types)

  var resolvedTypes: seq[ResolvedType]
  for typ in file.types:
    let resolvedType = ? resolveType(fileScope, typ)
    resolvedTypes.add(resolvedType)

  ok(newResolvedFile(file, resolvedImports, resolvedTypes, fileScope))

proc resolve*(app: App): Result[ResolvedApp, string] =
  var resolvedFiles: seq[ResolvedFile]
  for file in app.files:
    let resolvedFile = ? resolveFile(app, file)
    resolvedFiles.add(resolvedFile)
  ok(newResolvedApp(resolvedFiles))