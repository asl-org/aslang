import results, options, tables, strformat, parseutils

import tokenizer
import parser

type File = parser.File

type ResolvedGenericType = ref object
  file: int
  generic: int

type ResolvedModuleType = ref object
  file: int
  module: int

proc newResolvedModuleType(file: int, module: int): ResolvedModuleType =
  ResolvedModuleType(file: file, module: module)

type
  ResolvedTypeKind = enum
    rtkGeneric, rtkModule
  ResolvedType = ref object
    case kind: ResolvedTypeKind
    of rtkGeneric: generic: ResolvedGenericType
    of rtkModule: module: ResolvedModuleType

proc newResolvedType(module: ResolvedModuleType): ResolvedType =
  ResolvedType(kind: rtkModule, module: module)

type FileScope = Table[Identifier, ResolvedType]

proc findType(scope: FileScope, name: Identifier): Result[ResolvedType, string] =
  if name in scope: ok(scope[name])
  else: err(fmt"failed to find type: {name.value}")

proc findType(scope: FileScope, name: string): Result[ResolvedType, string] =
  let maybeIdentifier = newIdentifier(name, newLocation())
  assert(maybeIdentifier.isOk, $(maybeIdentifier.error))
  scope.findType(maybeIdentifier.get)

type FunctionScope = ref object
  lut: Table[Identifier, int]
  counter: int

proc newFunctionScope(): FunctionScope =
  FunctionScope(lut: initTable[Identifier, int](), counter: 0)

proc addArg(scope: FunctionScope, arg: Identifier): FunctionScope =
  scope.lut[arg] = scope.counter
  scope.counter += 1
  return scope

proc getArg(scope: FunctionScope, arg: Identifier): Option[int] =
  if arg in scope.lut: some(scope.lut[arg])
  else: none(int)

proc resolveImport(app: App, file: File, scope: FileScope, imp: Import): Result[
    void, string] =
  err("todo: resolve imports")

type
  ResolvedLiteralTypeKind = enum
    rltkU8, rltkU16, rltkU32, rltkU64
    rltkI8, rltkI16, rltkI32, rltkI64
    rltkF32, rltkF64
  ResolvedLiteralType = ref object
    kind: ResolvedLiteralTypeKind

proc newResolvedLiteralType(kind: ResolvedLiteralTypeKind): ResolvedLiteralType =
  ResolvedLiteralType(kind: kind)

proc resolveLiteralType(app: App, file: File, module: Module,
    l: LiteralType): Result[ResolvedLiteralType, string] =
  case l.content:
  of "u8": ok(newResolvedLiteralType(rltkU8))
  of "u16": ok(newResolvedLiteralType(rltkU16))
  of "u32": ok(newResolvedLiteralType(rltkU32))
  of "u64": ok(newResolvedLiteralType(rltkU64))
  of "i8": ok(newResolvedLiteralType(rltkI8))
  of "i16": ok(newResolvedLiteralType(rltkI16))
  of "i32": ok(newResolvedLiteralType(rltkI32))
  of "i64": ok(newResolvedLiteralType(rltkI64))
  of "f32": ok(newResolvedLiteralType(rltkF32))
  of "f64": ok(newResolvedLiteralType(rltkF64))
  else: err(fmt"{file.path}:{l.loc} literal '{l.content}' is unsupported")

proc resolveStruct(app: App, file: File, module: Module,
    struct: Struct): Result[void, string] =
  err("todo: resolve struct")

proc resolveUnion(app: App, file: File, module: Module, union: Union): Result[
    void, string] =
  err("todo: resolve union")

type
  ResolvedDataKind = enum
    rdkLiteral, rdkStruct, rdkUnion
  ResolvedData = ref object
    case kind: ResolvedDataKind
    of rdkLiteral: literal: ResolvedLiteralType
    of rdkStruct: discard
    of rdkUnion: discard

proc newResolvedData(literal: ResolvedLiteralType): ResolvedData =
  ResolvedData(kind: rdkLiteral, literal: literal)

proc newResolvedDataStruct(): ResolvedData =
  ResolvedData(kind: rdkStruct)

proc newResolvedDataUnion(): ResolvedData =
  ResolvedData(kind: rdkUnion)

proc resolveData(app: App, file: File, module: Module, data: DataBlock): Result[
    ResolvedData, string] =
  case data.kind:
  of dbkLiteral:
    let resolvedLiteral = ? resolveLiteralType(app, file, module, data.literal)
    ok(newResolvedData(resolvedLiteral))
  of dbkStruct:
    ? resolveStruct(app, file, module, data.struct)
    ok(newResolvedDataStruct())
  of dbkUnion:
    ? resolveUnion(app, file, module, data.union)
    ok(newResolvedDataUnion())

type ResolvedArgumentType = ref object
  root: ResolvedType
  impls: seq[ResolvedArgumentType]

proc newResolvedArgumentType(root: ResolvedType, impls: seq[
    ResolvedArgumentType]): ResolvedArgumentType =
  ResolvedArgumentType(root: root, impls: impls)

proc resolveArgumentType(app: App, file: File, fileScope: FileScope,
    module: Module, argType: ArgumentType): Result[ResolvedArgumentType, string] =
  let resolvedRoot = ? fileScope.findType(argType.root)
  case resolvedRoot.kind:
  of rtkGeneric:
    if argType.impls.len > 0:
      return err(fmt"{argType.loc} generic '{argType.root.value}' does not accept impl types")
  of rtkModule: discard

  var resolvedImpls: seq[ResolvedArgumentType]
  for impl in argType.impls:
    let resolvedImpl = ? resolveArgumentType(app, file, fileScope, module, impl)
    resolvedImpls.add(resolvedImpl)

  ok(newResolvedArgumentType(resolvedRoot, resolvedImpls))

proc resolveArgumentDefinition(app: App, file: File, fileScope: FileScope,
    module: Module, argDef: ArgumentDefinition): Result[ResolvedArgumentType, string] =
  let resolvedArgType = ? resolveArgumentType(app, file, fileScope, module,
      argDef.argType)
  # TODO: check if the data block is present on the resolved type
  case resolvedArgType.root.kind:
  of rtkGeneric: discard
  of rtkModule:
    let argTypeModule = resolvedArgType.root.module
    let argModule = app.files[argTypeModule.file].modules[argTypeModule.module]
    if argModule.data.isNone:
      return err("{argDef.argType.loc} module '{argModule.name.value}' is not a struct/union")

  ok(resolvedArgType)

type ResolvedFunctionDefinition = ref object
  args: seq[ResolvedArgumentType]
  returns: ResolvedArgumentType

proc newResolvedFunctionDefinition(args: seq[ResolvedArgumentType],
    returns: ResolvedArgumentType): ResolvedFunctionDefinition =
  ResolvedFunctionDefinition(args: args, returns: returns)

proc resolveFunctionDefinition(app: App, file: File, fileScope: FileScope, module: Module, def: FunctionDefinition): Result[ResolvedFunctionDefinition, string] =
  var argDefs: seq[ResolvedArgumentType]
  for index, argDef in def.args:
    let resolvedArgType = ? resolveArgumentDefinition(app, file, fileScope,
        module, argDef)
    argDefs.add(resolvedArgType)

  let resolvedReturnType = ? resolveArgumentType(app, file, fileScope, module, def.returns)
  ok(newResolvedFunctionDefinition(argDefs, resolvedReturnType))

type ResolvedIntegerLiteral = ref object
  argType: ResolvedArgumentType
  value: string

proc newResolvedIntegerLiteral(argType: ResolvedArgumentType,
    value: string): ResolvedIntegerLiteral =
  ResolvedIntegerLiteral(argType: argType, value: value)

proc resolveIntegerLiteral(file: File, fileScope: FileScope,
    literal: IntegerLiteral): Result[ResolvedIntegerLiteral, string] =
  case literal.kind:
  of ilkSigned:
    err("todo: resolve signed integer literal")
  of ilkUnsigned:
    let ulit = literal.unsigned
    var temp: BiggestUInt
    let code = parseBiggestUInt(ulit.value, temp)
    if code == 0 or code != ulit.value.len:
      return err(fmt"{file.path}:{ulit.loc} Failed to parse unsigned int from: {ulit.value}")
    if temp > int32.high.uint32:
      return err(fmt"{file.path}:{ulit.loc} Overflow: Value out of range for type i32")

    let resolvedType = ? fileScope.findType("i32")
    let resolvedArgumentType = newResolvedArgumentType(resolvedType, @[])
    ok(newResolvedIntegerLiteral(resolvedArgumentType, ulit.value))

type
  ResolvedLiteralKind = enum
    rlkInteger, rlkFloat, rlkString
  ResolvedLiteral = ref object
    case kind: ResolvedLiteralKind
    of rlkInteger: integer: ResolvedIntegerLiteral
    of rlkFloat: discard
    of rlkString: discard

proc newResolvedLiteral(integer: ResolvedIntegerLiteral): ResolvedLiteral =
  ResolvedLiteral(kind: rlkInteger, integer: integer)

proc resolveLiteral(file: File, fileScope: FileScope,
    literal: Literal): Result[ResolvedLiteral, string] =
  case literal.kind:
  of lkInteger:
    let integer = literal.intLit
    let resolvedInteger = ? resolveIntegerLiteral(file, fileScope, integer)
    ok(newResolvedLiteral(resolvedInteger))
  of lkFloat: err("todo: resolve float literal")
  of lkString: err("todo: resolve string literal")

type
  ResolvedExpressionKind = enum
    rekLiteral, rekFnCall, rekGetter, rekInitializer, rekVariable, rekMatch
  ResolvedExpression = ref object
    case kind: ResolvedExpressionKind
    of rekLiteral: literal: ResolvedLiteral
    of rekFnCall: discard
    of rekGetter: discard
    of rekInitializer: discard
    of rekVariable: id: int
    of rekMatch: discard

proc newResolvedExpression(id: int): ResolvedExpression =
  ResolvedExpression(kind: rekVariable, id: id)

proc newResolvedExpression(literal: ResolvedLiteral): ResolvedExpression =
  ResolvedExpression(kind: rekLiteral, literal: literal)

proc resolveExpression(app: App, file: File, fileScope: FileScope,
    module: Module, expression: Expression, funcScope: FunctionScope): Result[
    ResolvedExpression, string]

proc resolveFunctionCall(app: App, file: File, fileScope: FileScope,
    module: Module, fncall: FunctionCall, funcScope: FunctionScope): Result[
        void, string] =
  let resolvedArgType = ? resolveArgumentType(app, file, fileScope, module,
      fncall.argType)

  case resolvedArgType.root.kind:
  of rtkGeneric: return err("todo: resolve function name in generic function call")
  of rtkModule: return err("todo: resolve function name in module function call")

  var args: seq[ResolvedExpression]
  for arg in fncall.args:
    let resolvedArg = ? resolveExpression(app, file, fileScope, module,
        arg, funcScope)
    args.add(resolvedArg)

  err("todo: resolve function call")

proc resolveExpression(app: App, file: File, fileScope: FileScope,
    module: Module, expression: Expression, funcScope: FunctionScope): Result[
    ResolvedExpression, string] =
  case expression.kind:
  of ekLiteral:
    let resolvedLiteral = ? resolveLiteral(file, fileScope, expression.literal)
    let resolvedExpression = newResolvedExpression(resolvedLiteral)
    ok(resolvedExpression)
  of ekVariable:
    let variable = expression.variable
    let maybeId = funcScope.getArg(variable)
    if maybeId.isNone:
      err(fmt"{file.path}:{variable.loc} variable '{variable.value}' is not present in the function scope")
    else:
      let expression = newResolvedExpression(maybeId.get)
      ok(expression)
  of ekInitializer: err("todo: resolve initializer expression")
  of ekGetter: err("todo: resolve getter expression")
  of ekFnCall:
    let fncall = expression.fncall
    ? resolveFunctionCall(app, file, fileScope, module, fncall, funcScope)
    err("todo: resolve fncall expression")
  of ekMatch: err("todo: resolve match expression")

proc resolveStatement(app: App, file: File, fileScope: FileScope,
    module: Module, statement: Statement, funcScope: FunctionScope): Result[
        void, string] =
  case statement.kind:
  of skAssignment:
    let assignment = statement.assignment
    # TODO: resolve the expression
    discard ? resolveExpression(app, file, fileScope, module,
        assignment.expression, funcScope)
    # TODO: update the scope with target variable
    err("todo: resolve assigned statement")
  of skMutation: err("todo: resolve mutation")
  of skExpr: err("todo: resolve expression")

proc resolveUserFunction(app: App, file: File, fileScope: FileScope,
    module: Module, function: UserFunction): Result[void, string] =
  var funcScope = newFunctionScope()
  let funcDef = ? resolveFunctionDefinition(app, file, fileScope, module,
      function.def)
  for argDef in function.def.args:
    funcScope = funcScope.addArg(argDef.name)

  for statement in function.statements:
    ? resolveStatement(app, file, fileScope, module, statement, funcScope)
  err("todo: resolve user function")

type ResolvedExternFunction = ref object
  ffi: string
  funcDef: ResolvedFunctionDefinition

proc newResolvedExternFunction(ffi: string, funcDef: ResolvedFunctionDefinition): ResolvedExternFunction =
  ResolvedExternFunction(ffi: ffi, funcDef: funcDef)

proc resolveExternFunction(app: App, file: File, fileScope: FileScope,
    module: Module, function: ExternFunction): Result[ResolvedExternFunction, string] =
  let funcDef = ? resolveFunctionDefinition(app, file, fileScope, module, function.def)
  ok(newResolvedExternFunction(function.ffi, funcDef))

type
  ResolvedFunctionKind = enum
    rfkExtern, rfkUser
  ResolvedFunction = ref object
    case kind: ResolvedFunctionKind
    of rfkExtern: extern: ResolvedExternFunction
    of rfkUser: discard

proc newResolvedFunction(extern: ResolvedExternFunction): ResolvedFunction =
  ResolvedFunction(kind: rfkExtern, extern: extern)

proc newResolvedFunction(): ResolvedFunction =
  ResolvedFunction(kind: rfkUser)

proc resolveFunction(app: App, file: File, fileScope: FileScope, module: Module,
    function: Function): Result[ResolvedFunction, string] =
  case function.kind:
  of fkUser:
    ? resolveUserFunction(app, file, fileScope, module, function.user)
    ok(newResolvedFunction())
  of fkExtern:
    let resolvedExternFunc = ? resolveExternFunction(app, file, fileScope, module, function.extern)
    ok(newResolvedFunction(resolvedExternFunc))

type ResolvedModule = ref object
  data: Option[ResolvedData]
  functions: seq[ResolvedFunction]

proc newResolvedModule(data: Option[ResolvedData], functions: seq[ResolvedFunction]): ResolvedModule =
  ResolvedModule(data: data, functions: functions)

proc resolveModule(app: App, file: File, fileScope: FileScope,
    module: Module): Result[ResolvedModule, string] =
  let resolved_data_opt =
    if module.data.isSome:
      let resolvedData = ? resolveData(app, file, module, module.data.get)
      some(resolvedData)
    else:
      none(ResolvedData)

  var functions: seq[ResolvedFunction]
  for function in module.functions:
    let resolvedFunction = ? resolveFunction(app, file, fileScope, module, function)
    functions.add(resolvedFunction)

  ok(newResolvedModule(resolved_data_opt, functions))

proc resolveFile(app: App, file: File, id: int): Result[void, string] =
  var scope: FileScope
  for imp in file.imports:
    ? resolveImport(app, file, scope, imp)

  var modules: seq[ResolvedModule]
  for index, module in file.modules:
    let resolvedModule = ? resolveModule(app, file, scope, module)
    modules.add(resolvedModule)
    scope[module.name] = newResolvedType(newResolvedModuleType(id, index))
  err("todo: resolve file")

proc resolve*(app: App): Result[void, string] =
  for index, file in app.files:
    ? resolveFile(app, file, index)
  err("todo: resolve app")
