import results, options, tables, strformat, parseutils

import tokenizer
import parser

type File = parser.File

const NATIVE_TYPES = @["i8", "i16", "i32", "i64", "u8", "u16", "u32", "u64",
    "f32", "f64", "String", "List", "Map", "System"]

type ResolvedNativeType = ref object
  name: string

proc newResolvedNativeType(name: string): ResolvedNativeType =
  ResolvedNativeType(name: name)

type ResolvedGenericType = ref object
  file: int
  generic: int

type ResolvedModuleType = ref object
  file: int
  module: int

type
  ResolvedTypeKind = enum
    rtkNative, rtkGeneric, rtkModule
  ResolvedType = ref object
    case kind: ResolvedTypeKind
    of rtkGeneric: generic: ResolvedGenericType
    of rtkModule: module: ResolvedModuleType
    of rtkNative: native: ResolvedNativeType

proc newResolvedType(native: ResolvedNativeType): ResolvedType =
  ResolvedType(kind: rtkNative, native: native)

type FileScope = Table[Identifier, ResolvedType]

proc newFileScope(): FileScope =
  var scope: Table[Identifier, ResolvedType]
  for intType in NATIVE_TYPES:
    let maybeTypeName = newIdentifier(intType, newLocation())
    assert(maybeTypeName.isOk, fmt"failed to build type registry for {intType}")
    let resolvedNativeType = newResolvedNativeType(intType)
    scope[maybeTypeName.get] = newResolvedType(resolvedNativeType)
  return scope

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

proc resolveLiteral(app: App, file: File, module: Module,
    l: LiteralType): Result[void, string] =
  err("todo: resolve literal type")

proc resolveStruct(app: App, file: File, module: Module,
    struct: Struct): Result[void, string] =
  err("todo: resolve struct")

proc resolveUnion(app: App, file: File, module: Module, union: Union): Result[
    void, string] =
  err("todo: resolve union")

proc resolveData(app: App, file: File, module: Module, data: DataBlock): Result[
    void, string] =
  case data.kind:
  of dbkStruct: ? resolveStruct(app, file, module, data.struct)
  of dbkUnion: ? resolveUnion(app, file, module, data.union)
  of dbkLiteral: ? resolveLiteral(app, file, module, data.literal)
  err("todo: resolve data block")

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
  of rtkNative: discard

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
  of rtkNative:
    let argTypeNative = resolvedArgType.root.native
    if argTypeNative.name == "System":
      return err("{argDef.argType.loc} module '{argModule.name.value}' is not a struct/union")

  ok(resolvedArgType)

type ResolvedFunctionDefinition = ref object
  args: seq[ResolvedArgumentType]
  returns: ResolvedArgumentType

proc newResolvedFunctionDefinition(args: seq[ResolvedArgumentType],
    returns: ResolvedArgumentType): ResolvedFunctionDefinition =
  ResolvedFunctionDefinition(args: args, returns: returns)

proc resolveFunctionDefinition(app: App, file: File, fileScope: FileScope,
    module: Module, def: FunctionDefinition,
        funcScope: var FunctionScope): Result[
    ResolvedFunctionDefinition, string] =
  var argDefs: seq[ResolvedArgumentType]
  for index, argDef in def.args:
    let resolvedArgType = ? resolveArgumentDefinition(app, file, fileScope,
        module, argDef)
    argDefs.add(resolvedArgType)
    funcScope = funcScope.addArg(argDef.name)

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
  of rtkNative:
    let nativeType = resolvedArgType.root.native
    let resolvedNativeType = ? fileScope.findType(nativeType.name)
    return err("todo: resolve function name in native function call")
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
  of skExpr: err("todo: resolve expression")

proc resolveUserFunction(app: App, file: File, fileScope: FileScope,
    module: Module, function: UserFunction): Result[void, string] =
  var funcScope = newFunctionScope()
  let funcDef = ? resolveFunctionDefinition(app, file, fileScope, module,
      function.def, funcScope)

  for statement in function.statements:
    ? resolveStatement(app, file, fileScope, module, statement, funcScope)
  err("todo: resolve user function")

proc resolveExternFunction(app: App, file: File, fileScope: FileScope,
    module: Module, function: ExternFunction): Result[void, string] =
  var funcScope = newFunctionScope()
  let funcDef = ? resolveFunctionDefinition(app, file, fileScope, module,
      function.def, funcScope)
  err("todo: resolve extern function")

proc resolveFunction(app: App, file: File, fileScope: FileScope, module: Module,
    function: Function): Result[void, string] =
  case function.kind:
  of fkUser: resolveUserFunction(app, file, fileScope, module, function.user)
  of fkExtern: resolveExternFunction(app, file, fileScope, module, function.extern)

proc resolveModule(app: App, file: File, fileScope: FileScope,
    module: Module): Result[void, string] =
  if module.data.isSome:
    ? resolveData(app, file, module, module.data.get)

  for function in module.functions:
    ? resolveFunction(app, file, fileScope, module, function)

  err("todo: resolve modules")

proc resolveFile(app: App, file: File): Result[void, string] =
  var scope = newFileScope()
  for imp in file.imports:
    ? resolveImport(app, file, scope, imp)
  for module in file.modules:
    ? resolveModule(app, file, scope, module)
  err("todo: resolve file")

proc resolve*(app: App): Result[void, string] =
  for file in app.files:
    ? resolveFile(app, file)
  err("todo: resolve app")
