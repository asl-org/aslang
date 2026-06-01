## User function + tagged-union Function analysis.
##
## Currently empty — function-body analysis is the next milestone.
## The commented-out scaffolding below was carried over from the
## monolithic analyzer.nim so the user-function / statement /
## expression / function-ref structure stays preserved while it's
## being iterated on.

# type AnalyzedExternFunction = ref object
#   funcDef: AnalyzedFunctionDefinition
#   ffi: string

# proc newAnalyzedExternFunction(funcDef: AnalyzedFunctionDefinition, ffi: string): AnalyzedExternFunction =
#   AnalyzedExternFunction(funcDef: funcDef, ffi: ffi)

# proc analyzeExternFunction*(app: ResolvedApp, file: ResolvedFile, module: ResolvedModule, function: ResolvedExternFunction): Result[AnalyzedExternFunction, string] =
#   let analyzedFuncDef = ? analyzeFunctionDefinition(app, file, module, function.def)
#   ok(newAnalyzedExternFunction(analyzedFuncDef, function.ffi))

# proc analyzeModuleTypeRef(app: ResolvedApp, file: ResolvedFile, module: ResolvedModule, moduleTypeRef: ResolvedModuleTypeRef): Result[void, string] =
#   let resolvedModule = ? file.findModule(moduleTypeRef.module.name)
#   err(fmt"{moduleTypeRef.loc} todo: analyze module ref")

# proc analyzeDefinedTypeRef(app: ResolvedApp, file: ResolvedFile, module: ResolvedModule, definedTypeRef: ResolvedTypeRef): Result[void, string] =
#   case definedTypeRef.kind:
#   of rdtrkGeneric:
#     err(fmt"{definedTypeRef.loc} todo: analyze defined generic ref")
#   of rdtrkModule:
#     analyzeModuleTypeRef(app, file, module, definedTypeRef.module)

# proc analyzeFunctionRef(app: ResolvedApp, file: ResolvedFile, module: ResolvedModule, funcRef: ResolvedFunctionRef): Result[void, string] =
#   case funcRef.kind:
#   of rfrkDefined: analyzeDefinedTypeRef(app, file, module, funcRef.definedType)

# proc analyzeExpression(app: ResolvedApp, file: ResolvedFile, module: ResolvedModule, scope: Table[Identifier, AnalyzedArgumentDefinition], expression: ResolvedExpression): Result[void, string]

# proc analyzeFunctionCall(app: ResolvedApp, file: ResolvedFile, module: ResolvedModule, scope: Table[Identifier, AnalyzedArgumentDefinition], fncall: ResolvedFunctionCall): Result[void, string] =
#   ? analyzeFunctionRef(app, file, module, fncall.funcRef)
#   for arg in fncall.args:
#     ? analyzeExpression(app, file, module, scope, arg)
#   err(fmt"{fncall.loc} todo: analyze function call")

# proc analyzeExpression(app: ResolvedApp, file: ResolvedFile, module: ResolvedModule, scope: Table[Identifier, AnalyzedArgumentDefinition], expression: ResolvedExpression): Result[void, string] =
#   case expression.kind:
#   of rekGetter: err(fmt"{expression.loc} todo: analyze getter")
#   of rekInitializer: err(fmt"{expression.loc} todo: analyze initializer")
#   of rekVariable: err(fmt"{expression.loc} todo: analyze variable")
#   of rekLiteral: err(fmt"{expression.loc} todo: analyze literal")
#   of rekMatchExpr: err(fmt"{expression.loc} todo: analyze match block")
#   of rekFunctionCall: analyzeFunctionCall(app, file, module, scope, expression.fncall)

# proc analyzeStatement(app: ResolvedApp, file: ResolvedFile, module: ResolvedModule, scope: Table[Identifier, AnalyzedArgumentDefinition], statement: ResolvedStatement): Result[void, string] =
#   case statement.kind:
#   of rskAssignment: err(fmt"{statement.loc} todo: analyze assignment")
#   of rskMutation: err(fmt"{statement.loc} todo: analyze mutation")
#   of rskExpr: analyzeExpression(app, file, module, scope, statement.expression)

# proc analyzeUserFunction(app: ResolvedApp, file: ResolvedFile, module: ResolvedModule, function: ResolvedUserFunction): Result[void, string] =
#   var scope: Table[Identifier, AnalyzedArgumentDefinition]
#   for arg in analyzedFuncDef.args:
#     assert(arg.name notin scope, "UNREACHABLE: function definition can not have same param name in different positions")
#     scope[arg.name] = arg
#   for statement in function.statements:
#     ? analyzeStatement(app, file, module, scope, statement)
#   ok()

# type
#   AnalyzedFunctionKind = enum
#     afkExtern, afkUser
#   AnalyzedFunction = ref object
#     case kind: AnalyzedFunctionKind
#     of afkExtern: extern: AnalyzedExternFunction
#     of afkUser:

# proc newAnalyzedFunction(extern: AnalyzedExternFunction): AnalyzedFunction =
#   AnalyzedFunction(kind: afkExtern, extern: extern)

# proc analyzeFunction*(app: ResolvedApp, file: ResolvedFile, module: ResolvedModule, function: ResolvedFunction): Result[AnalyzedFunction, string] =
#   case function.kind:
#   of rfkExtern:
#     let analyzedExternFn = ? analyzeExternFunction(app, file, module, function.extern)
#     ok(newAnalyzedFunction(analyzedExternFn))
#   of rfkUser:
#     let analyzedFuncDef = ? analyzeFunctionDefinition(app, file, module, function.def)
#     ok()
