import results, options, strformat, sets, tables

import parser

type File = parser.File
type FileScope = Table[Identifier, DefinedType]

type ResolvedLiteralType = enum
  rltkU8, rltkU16, rltkU32, rltkU64
  rltkI8, rltkI16, rltkI32, rltkI64
  rltkF32, rltkF64, rltkString, rltkPointer

proc resolveLiteralType(file: File, literal: LiteralType): Result[ResolvedLiteralType, string] =
  case literal.content:
  of "u8": ok(rltkU8)
  of "u16": ok(rltkU16)
  of "u32": ok(rltkU32)
  of "u64": ok(rltkU64)
  of "i8": ok(rltkI8)
  of "i16": ok(rltkI16)
  of "i32": ok(rltkI32)
  of "i64": ok(rltkI64)
  of "f32": ok(rltkF32)
  of "f64": ok(rltkF64)
  of "string": ok(rltkString)
  of "pointer": ok(rltkPointer)
  else: err(fmt"{literal.loc} unsupported literal type encountered `{literal.content}`")

type ResolvedImportedType = ref object
  name: Identifier
  binding: Identifier
  definedType: DefinedType

proc newResolvedImportedType(name: Identifier, binding: Identifier, definedType: DefinedType): ResolvedImportedType =
  ResolvedImportedType(name: name, binding: binding, definedType: definedType)

proc resolveImportedType(app: App, file: File, impFile: File, impType: ImportedType): Result[ResolvedImportedType, string] =
  let importedDefinedType = ? impFile.findExportedType(impType.name)
  ok(newResolvedImportedType(impType.name, impType.binding, importedDefinedType))

type ResolvedImport = ref object
  source: File
  importedTypes: seq[ResolvedImportedType]

proc newResolvedImport(source: File, importedTypes: seq[ResolvedImportedType]): ResolvedImport =
  ResolvedImport(source: source, importedTypes: importedTypes)

proc resolveImport(app: App, file: File, imp: Import): Result[ResolvedImport, string] =
  let impFile = ? app.findFile(imp.path)
  var resolvedImportedTypes: seq[ResolvedImportedType]
  for impType in imp.names:
    let resolvedImportedType = ? resolveImportedType(app, file, impFile, impType)
    resolvedImportedTypes.add(resolvedImportedType)
  ok(newResolvedImport(impFile, resolvedImportedTypes))

type
  ResolvedModuleArgumentType = ref object
    root: Module
    impls: seq[ResolvedArgumentType]
  ResolvedDefinedArgumentTypeKind = enum
    rdatkModule, rdatkGeneric
  ResolvedDefinedArgumentType = ref object
    case kind: ResolvedDefinedArgumentTypeKind
    of rdatkModule: module: ResolvedModuleArgumentType
    of rdatkGeneric: generic: Generic
  ResolvedArgumentTypeKind = enum
    ratkImported, ratkDefined
  ResolvedArgumentType = ref object
    case kind: ResolvedArgumentTypeKind
    of ratkImported: discard
    of ratkDefined: definedType: ResolvedDefinedArgumentType

proc newResolvedModuleArgumentType(root: Module, impls: seq[ResolvedArgumentType]): ResolvedModuleArgumentType =
  ResolvedModuleArgumentType(root: root, impls: impls)

proc newResolvedModuleArgumentType(root: Module): ResolvedModuleArgumentType =
  newResolvedModuleArgumentType(root, @[])

proc newResolvedDefinedArgumentType(module: ResolvedModuleArgumentType): ResolvedDefinedArgumentType =
  ResolvedDefinedArgumentType(kind: rdatkModule, module: module)

proc newResolvedDefinedArgumentType(generic: Generic): ResolvedDefinedArgumentType =
  ResolvedDefinedArgumentType(kind: rdatkGeneric, generic: generic)

proc newResolvedArgumentType(definedType: ResolvedDefinedArgumentType): ResolvedArgumentType =
  ResolvedArgumentType(kind: ratkDefined, definedType: definedType)

proc resolveArgumentType(app: App, file: File, fileScope: FileScope, module: Module, argType: ArgumentType): Result[ResolvedArgumentType, string]

proc resolveModuleArgumentType(app: App, file: File, fileScope: FileScope, module: Module, argType: ArgumentType, root: Module): Result[ResolvedModuleArgumentType, string] =
  # NOTE: requires block will override the inferred impl list
  if root.requires.isSome:
    let expectedImplCount = root.requires.get.generics.len
    if argType.impls.len != expectedImplCount:
      return err(fmt"{argType.loc} type `{root.name.asl}` expects `{expectedImplCount}` impls but found `{argType.impls.len}`")

    var resolvedImpls: seq[ResolvedArgumentType]
    for impl in argType.impls:
      let resolvedImpl = ? resolveArgumentType(app, file, fileScope, module, impl)
      resolvedImpls.add(resolvedImpl)

    return ok(newResolvedModuleArgumentType(root, resolvedImpls))

  # NOTE: infer the impl list from struct/union block
  if root.data.isSome:
    let dataBlock = root.data.get
    case dataBlock.kind:
    of dbkLiteral:
      if argType.impls.len == 0:
        return ok(newResolvedModuleArgumentType(root))
      else:
        return err(fmt"{argType.loc} type `{root.name.asl}` does not require impl types")
    of dbkStruct:
      var requires: seq[Generic]
      let struct = dataBlock.struct
      for field in struct.fields:
        let fieldType = ? file.findType(field.argType.root)
        case fieldType.kind:
        of tkImported:
          return err("todo: resolve imported type field in union variant")
        of tkDefined:
          let definedFieldType = fieldType.definedType
          case definedFieldType.kind:
          of dtkModule: discard
          of dtkGeneric: requires.add(definedFieldType.generic)

      if argType.impls.len != requires.len:
        return err(fmt"{argType.loc} struct `{root.name.asl}` expects `{requires.len}` impls but found `{argType.impls.len}`")

      var resolvedImpls: seq[ResolvedArgumentType]
      for impl in argType.impls:
        let resolvedImpl = ? resolveArgumentType(app, file, fileScope, module, impl)
        resolvedImpls.add(resolvedImpl)

      return ok(newResolvedModuleArgumentType(root, resolvedImpls))

    of dbkUnion:
      var requires: seq[Generic]
      let union = dataBlock.union
      for variant in union.variants:
        for field in variant.fields:
          let fieldType = ? file.findType(field.argType.root)
          case fieldType.kind:
          of tkImported:
            return err("todo: resolve imported type field in union variant")
          of tkDefined:
            let definedFieldType = fieldType.definedType
            case definedFieldType.kind:
            of dtkModule: discard
            of dtkGeneric: requires.add(definedFieldType.generic)

      if argType.impls.len != requires.len:
        return err(fmt"{argType.loc} union `{root.name.asl}` expects `{requires.len}` impls but found `{argType.impls.len}`")

      var resolvedImpls: seq[ResolvedArgumentType]
      for impl in argType.impls:
        let resolvedImpl = ? resolveArgumentType(app, file, fileScope, module, impl)
        resolvedImpls.add(resolvedImpl)

      return ok(newResolvedModuleArgumentType(root, resolvedImpls))

  if argType.impls.len == 0:
    ok(newResolvedModuleArgumentType(root))
  else:
    err(fmt"{argType.loc} type `{root.name.asl}` does not require impl types")

proc resolveArgumentType(app: App, file: File, generic: Generic, argType: ArgumentType): Result[ResolvedArgumentType, string]

proc resolveModuleArgumentType(app: App, file: File, generic: Generic, argType: ArgumentType, root: Module): Result[ResolvedModuleArgumentType, string] =
  # NOTE: requires block will override the inferred impl list
  if root.requires.isSome:
    return err("todo: resolve requires block in argument type")

  # NOTE: infer the impl list from struct/union block
  if root.data.isSome:
    let dataBlock = root.data.get
    case dataBlock.kind:
    of dbkStruct:
      return err(fmt"{dataBlock.loc} todo: resolve struct block in argument type")
    of dbkLiteral:
      if argType.impls.len == 0:
        return ok(newResolvedModuleArgumentType(root))
      else:
        return err(fmt"{argType.loc} type `{root.name.asl}` does not require impl types")
    of dbkUnion:
      var requires: seq[Generic]
      let union = dataBlock.union
      for variant in union.variants:
        for field in variant.fields:
          let fieldType = ? file.findType(field.argType.root)
          case fieldType.kind:
          of tkImported:
            return err("todo: resolve imported type field in union variant")
          of tkDefined:
            let definedFieldType = fieldType.definedType
            case definedFieldType.kind:
            of dtkModule: discard
            of dtkGeneric: requires.add(definedFieldType.generic)

      if argType.impls.len != requires.len:
        return err(fmt"{argType.loc} type `{root.name.asl}` expects `{requires.len}` impls but found `{argType.impls.len}`")

      var resolvedImpls: seq[ResolvedArgumentType]
      for impl in argType.impls:
        let resolvedImpl = ? resolveArgumentType(app, file, generic, impl)
        resolvedImpls.add(resolvedImpl)

      return ok(newResolvedModuleArgumentType(root, resolvedImpls))

  if argType.impls.len == 0:
    ok(newResolvedModuleArgumentType(root))
  else:
    err(fmt"{argType.loc} type `{root.name.asl}` does not require impl types")

proc resolveDefinedArgumentType(app: App, file: File, fileScope: FileScope, module: Module, argType: ArgumentType, definedType: DefinedType): Result[ResolvedDefinedArgumentType, string] =
  case definedType.kind:
  of dtkGeneric:
    if argType.impls.len == 0:
      ok(newResolvedDefinedArgumentType(definedType.generic))
    else:
      err(fmt"{definedType.loc} generic `{definedType.name.asl}` is not allowed to have impls")
  of dtkModule:
    let resolvedModuleType = ? resolveModuleArgumentType(app, file, fileScope, module, argType, definedType.module)
    ok(newResolvedDefinedArgumentType(resolvedModuleType))

proc resolveDefinedArgumentType(app: App, file: File, generic: Generic, argType: ArgumentType, definedType: DefinedType): Result[ResolvedDefinedArgumentType, string] =
  case definedType.kind:
  of dtkGeneric:
    if definedType.generic == generic:
      ok(newResolvedDefinedArgumentType(definedType.generic))
    else:
      err(fmt"{definedType.loc} type `{definedType.name.asl}` is a generic and can not be used within the generic block")
  of dtkModule:
    let resolvedModuleType = ? resolveModuleArgumentType(app, file, generic, argType, definedType.module)
    ok(newResolvedDefinedArgumentType(resolvedModuleType))

proc resolveArgumentType(app: App, file: File, fileScope: FileScope, module: Module, argType: ArgumentType): Result[ResolvedArgumentType, string] =
  let rootType = ? file.findType(argType.root)
  case rootType.kind:
  of tkImported:
    let impType = rootType.imported
    if impType.binding notin fileScope:
      err(fmt"{impType.loc} type `{impType.binding.asl}` does not exist in file scope")
    else:
      let impDefinedType = fileScope[impType.binding]
      let resolvedDefinedType = ? resolveDefinedArgumentType(app, file, fileScope, module, argType, impDefinedType)
      ok(newResolvedArgumentType(resolvedDefinedType))
  of tkDefined:
    let resolvedDefinedType = ? resolveDefinedArgumentType(app, file, fileScope, module, argType, rootType.definedType)
    ok(newResolvedArgumentType(resolvedDefinedType))

proc resolveArgumentType(app: App, file: File, generic: Generic, argType: ArgumentType): Result[ResolvedArgumentType, string] =
  let rootType = ? file.findType(argType.root)
  case rootType.kind:
  of tkImported:
    err("todo: resolve imported type")
  of tkDefined:
    let resolvedDefinedType = ? resolveDefinedArgumentType(app, file, generic, argType, rootType.definedType)
    ok(newResolvedArgumentType(resolvedDefinedType))

proc resolveDataType(app: App, file: File, module: Module, arg: ArgumentType, resolvedArgumentType: ResolvedArgumentType): Result[void, string] =
  case resolvedArgumentType.kind:
  of ratkImported:
    err("todo: resolve imported type argument definition")
  of ratkDefined:
    let resolvedDefinedType = resolvedArgumentType.definedType
    case resolvedDefinedType.kind:
    of rdatkGeneric:
      ok()
    of rdatkModule:
      let resolvedDefinedModuleType = resolvedDefinedType.module
      if resolvedDefinedModuleType.root.data.isSome:
        ok()
      else:
        err(fmt"{arg.loc} module `{resolvedDefinedModuleType.root.name.asl}` is not a literal/struct/union")

proc resolveDataType(app: App, file: File, generic: Generic, arg: ArgumentType, resolvedArgumentType: ResolvedArgumentType): Result[void, string] =
  case resolvedArgumentType.kind:
  of ratkImported:
    err("todo: resolve imported type argument definition")
  of ratkDefined:
    let resolvedDefinedType = resolvedArgumentType.definedType
    case resolvedDefinedType.kind:
    of rdatkGeneric:
      ok()
    of rdatkModule:
      let resolvedDefinedModuleType = resolvedDefinedType.module
      if resolvedDefinedModuleType.root.data.isSome:
        ok()
      else:
        err(fmt"{arg.loc} module `{resolvedDefinedModuleType.root.name.asl}` is not a literal/struct/union")

type ResolvedArgumentDefinition = ref object
  argType: ResolvedArgumentType
  name: Identifier

proc newResolvedArgumentDefinition(argType: ResolvedArgumentType, name: Identifier): ResolvedArgumentDefinition =
  ResolvedArgumentDefinition(name: name, argType: argType)

proc resolveArgumentDefinition(app: App, file: File, fileScope: FileScope, module: Module, arg: ArgumentDefinition): Result[ResolvedArgumentDefinition, string] =
  let resolvedArgumentType = ? resolveArgumentType(app, file, fileScope, module, arg.argType)
  ? resolveDataType(app, file, module, arg.argType, resolvedArgumentType)
  ok(newResolvedArgumentDefinition(resolvedArgumentType, arg.name))

proc resolveArgumentDefinition(app: App, file: File, generic: Generic, arg: ArgumentDefinition): Result[ResolvedArgumentDefinition, string] =
  let resolvedArgumentType = ? resolveArgumentType(app, file, generic, arg.argType)
  ? resolveDataType(app, file, generic, arg.argType, resolvedArgumentType)
  ok(newResolvedArgumentDefinition(resolvedArgumentType, arg.name))

type ResolvedFunctionDefinition = ref object
  public: bool
  name: Identifier
  args: seq[ResolvedArgumentDefinition]
  returns: ResolvedArgumentType

proc newResolvedFunctionDefinition(public: bool, name: Identifier, args: seq[ResolvedArgumentDefinition], returns: ResolvedArgumentType): ResolvedFunctionDefinition =
  ResolvedFunctionDefinition(public: public, name: name, args: args, returns: returns)

proc resolveFunctionDefinition(app: App, file: File, fileScope: FileScope, module: Module, def: FunctionDefinition): Result[ResolvedFunctionDefinition, string] =
  var resolvedArgs: seq[ResolvedArgumentDefinition]
  for arg in def.args:
    let resolvedArg = ? resolveArgumentDefinition(app, file, fileScope, module, arg)
    resolvedArgs.add(resolvedArg)

  let resolvedReturnArgType = ? resolveArgumentType(app, file, fileScope, module, def.returns)
  ? resolveDataType(app, file, module,  def.returns, resolvedReturnArgType)

  ok(newResolvedFunctionDefinition(def.public, def.name, resolvedArgs, resolvedReturnArgType))

proc resolveFunctionDefinition(app: App, file: File, generic: Generic, def: FunctionDefinition): Result[ResolvedFunctionDefinition, string] =
  var resolvedArgs: seq[ResolvedArgumentDefinition]
  for arg in def.args:
    let resolvedArg = ? resolveArgumentDefinition(app, file, generic, arg)
    resolvedArgs.add(resolvedArg)

  let resolvedReturnArgType = ? resolveArgumentType(app, file, generic, def.returns)
  ? resolveDataType(app, file, generic,  def.returns, resolvedReturnArgType)

  ok(newResolvedFunctionDefinition(def.public, def.name, resolvedArgs, resolvedReturnArgType))

type ResolvedExternFunction = ref object
  ffi: string
  def: ResolvedFunctionDefinition

proc newResolvedExternFunction(ffi: string, def: ResolvedFunctionDefinition): ResolvedExternFunction =
  ResolvedExternFunction(ffi: ffi, def: def)

proc resolveExternFunction(app: App, file: File, fileScope: FileScope, module: Module, function: ExternFunction): Result[ResolvedExternFunction, string] =
  let resolvedFunctionDef = ? resolveFunctionDefinition(app, file, fileScope, module, function.def)
  ok(newResolvedExternFunction(function.ffi, resolvedFunctionDef))

type FunctionScope = HashSet[Identifier]

type ResolvedGenericTypeRef = ref object
  generic: Generic
  funcDefs: seq[FunctionDefinition]

proc newResolvedGenericTypeRef(generic: Generic, funcDefs: seq[FunctionDefinition]): ResolvedGenericTypeRef =
  ResolvedGenericTypeRef(generic: generic, funcDefs: funcDefs)

proc resolveGenericTypeRef(app: App, file: File, fileScope: FileScope, module: Module, generic: Generic, name: Identifier, arity: int): Result[ResolvedGenericTypeRef, string] =
  let funcDefs = ? generic.findFunctionDefs(name, arity)
  ok(newResolvedGenericTypeRef(generic, funcDefs))

type ResolvedModuleTypeRef = ref object
  module: Module
  functions: seq[Function]

proc newResolvedModuleTypeRef(module: Module, functions: seq[Function]): ResolvedModuleTypeRef =
  ResolvedModuleTypeRef(module: module, functions: functions)

proc resolveModuleTypeRef(app: App, file: File, fileScope: FileScope, module: Module, typeModule: Module, name: Identifier, arity: int): Result[ResolvedModuleTypeRef, string] =
  let functions = ? typeModule.findFunctions(name, arity)
  ok(newResolvedModuleTypeRef(typeModule, functions))

type
  ResolvedDefinedTypeRefKind = enum
    rdtrkGeneric, rdtrkModule
  ResolvedDefinedTypeRef = ref object
    case kind: ResolvedDefinedTypeRefKind
    of rdtrkGeneric: generic: ResolvedGenericTypeRef
    of rdtrkModule: module: ResolvedModuleTypeRef

proc newResolvedDefinedTypeRef(generic: ResolvedGenericTypeRef): ResolvedDefinedTypeRef =
  ResolvedDefinedTypeRef(kind: rdtrkGeneric, generic: generic)

proc newResolvedDefinedTypeRef(module: ResolvedModuleTypeRef): ResolvedDefinedTypeRef =
  ResolvedDefinedTypeRef(kind: rdtrkModule, module: module)

proc resolveDefinedTypeRef(app: App, file: File, fileScope: FileScope, module: Module, definedType: DefinedType, name: Identifier, arity: int): Result[ResolvedDefinedTypeRef, string] =
  case definedType.kind:
  of dtkModule:
    let resolvedModuleTypeRef = ? resolveModuleTypeRef(app, file, fileScope, module, definedType.module, name, arity)
    ok(newResolvedDefinedTypeRef(resolvedModuleTypeRef))
  of dtkGeneric:
    let resolvedGenericTypeRef = ? resolveGenericTypeRef(app, file, fileScope, module, definedType.generic, name, arity)
    ok(newResolvedDefinedTypeRef(resolvedGenericTypeRef))

type
  ResolvedFunctionRefKind = enum
    rfrkDefined
  ResolvedFunctionRef = ref object
    case kind: ResolvedFunctionRefKind
    of rfrkDefined: definedRef: ResolvedDefinedTypeRef

proc newResolvedFunctionRef(definedRef: ResolvedDefinedTypeRef): ResolvedFunctionRef =
  ResolvedFunctionRef(kind: rfrkDefined, definedRef: definedRef)

proc resolveFunctionRef(app: App, file: File, fileScope: FileScope, module: Module, scope: FunctionScope, argType: ArgumentType, name: Identifier, arity: int): Result[ResolvedFunctionRef, string] =
  let resolvedArgumentType = ? resolveArgumentType(app, file, fileScope, module, argType)

  let rootModule = ? file.findType(argType.root)
  case rootModule.kind:
  of tkImported:
    let impType = rootModule.imported
    if impType.binding notin fileScope:
      err(fmt"{impType.loc} type `{impType.binding.asl}` does not exist in file scope")
    else:
      let impDefinedType = fileScope[impType.binding]
      let resolvedDefinedRef = ? resolveDefinedTypeRef(app, file, fileScope, module, impDefinedType, name, arity)
      ok(newResolvedFunctionRef(resolvedDefinedRef))
  of tkDefined:
    let resolvedDefinedRef = ? resolveDefinedTypeRef(app, file, fileScope, module, rootModule.definedType, name, arity)
    ok(newResolvedFunctionRef(resolvedDefinedRef))

proc resolveVariable(app: App, file: File, module: Module, scope: FunctionScope, variable: Identifier): Result[Identifier, string] =
  if variable notin scope:
    err(fmt"{variable.loc} variable `{variable.asl}` is not present in scope")
  else:
    ok(variable)

type ResolvedGetter = ref object
  source: Identifier
  property: Identifier

proc newResolvedGetter(source, property: Identifier): ResolvedGetter =
  ResolvedGetter(source: source, property: property)

proc resolveGetter(app: App, file: File, module: Module, scope: FunctionScope, getter: Getter): Result[ResolvedGetter, string] =
  let resovledVariable = ? resolveVariable(app, file, module, scope, getter.source)
  ok(newResolvedGetter(getter.source, getter.property))

type
  ResolvedCasePatternKind = enum
    rcpkInteger, rcpkVariable, rcpkVariant
  ResolvedCasePattern = ref object
    case kind: ResolvedCasePatternKind
    of rcpkInteger: integer: IntegerLiteral
    of rcpkVariable: variable: Identifier
    of rcpkVariant: variant: VariantPattern

proc newResolvedCasePattern(integer: IntegerLiteral): ResolvedCasePattern =
  ResolvedCasePattern(kind: rcpkInteger, integer: integer)

proc newResolvedCasePattern(variable: Identifier): ResolvedCasePattern =
  ResolvedCasePattern(kind: rcpkVariable, variable: variable)

proc newResolvedCasePattern(variant: VariantPattern): ResolvedCasePattern =
  ResolvedCasePattern(kind: rcpkVariant, variant: variant)

proc resolveCasePattern(app: App, file: File, module: Module, scope: FunctionScope, casePattern: CasePattern): Result[ResolvedCasePattern, string] =
  case casePattern.kind:
  of cpkIntegerLiteral:
    ok(newResolvedCasePattern(casePattern.intLit))
  of cpkVariable:
    ok(newResolvedCasePattern(casePattern.variable))
  of cpkVariant:
    ok(newResolvedCasePattern(casePattern.variant))

type ResolvedLiteralInitializer = ref object
  argType: ResolvedArgumentType
  value: Literal

proc newResolvedLiteralInitializer(argType: ResolvedArgumentType, value: Literal): ResolvedLiteralInitializer =
  ResolvedLiteralInitializer(argType: argType, value: value)

proc resolveLiteralInitializer(app: App, file: File, fileScope: FileScope, module: Module, scope: FunctionScope, literalInit: LiteralInitializer): Result[ResolvedLiteralInitializer, string] =
  let resolvedArgType = ? resolveArgumentType(app, file, fileScope, module, literalInit.argType)
  ok(newResolvedLiteralInitializer(resolvedArgType, literalInit.value))

type
  ResolvedFunctionCall = ref object
    funcRef: ResolvedFunctionRef
    args: seq[ResolvedExpression]

  ResolvedAssignment = ref object
    target: Identifier
    expression: ResolvedExpression

  ResolvedKeywordArgument = ref object
    name: Identifier
    expression: ResolvedExpression

  ResolvedStructInitializer = ref object
    argType: ResolvedArgumentType
    kwargs: seq[ResolvedKeywordArgument]

  ResolvedUnionInitializer = ref object
    argType: ResolvedArgumentType
    variant: Identifier
    kwargs: seq[ResolvedKeywordArgument]

  ResolvedInitializerKind = enum
    rikStruct, rikUnion, rikLiteral
  ResolvedInitializer = ref object
    case kind: ResolvedInitializerKind
    of rikStruct: struct: ResolvedStructInitializer
    of rikUnion: union: ResolvedUnionInitializer
    of rikLiteral: literal: ResolvedLiteralInitializer

  ResolvedCaseBlock = ref object
    pattern: ResolvedCasePattern
    statements: seq[ResolvedStatement]

  ResolvedMatchExpression = ref object
    subject: ResolvedExpression
    cases: seq[ResolvedCaseBlock]

  ResolvedMutation = ref object
    getter: ResolvedGetter
    expression: ResolvedExpression

  ResolvedExpressionKind = enum
    rekFunctionCall, rekVariable, rekLiteral, rekInitializer, rekGetter, rekMatchExpr
  ResolvedExpression = ref object
    case kind: ResolvedExpressionKind
    of rekFunctionCall: fncall: ResolvedFunctionCall
    of rekVariable: variable: Identifier
    of rekLiteral: literal: Literal
    of rekInitializer: initializer: ResolvedInitializer
    of rekGetter: getter: ResolvedGetter
    of rekMatchExpr: match: ResolvedMatchExpression

  ResolvedStatementKind = enum
    rskAssignment, rskExpr, rskMutation
  ResolvedStatement = ref object
    case kind: ResolvedStatementKind
    of rskAssignment: assignment: ResolvedAssignment
    of rskExpr: expression: ResolvedExpression
    of rskMutation: mutation: ResolvedMutation

# ResolvedFunctionCall
proc newResolvedFunctionCall(funcRef: ResolvedFunctionRef, args: seq[ResolvedExpression]): ResolvedFunctionCall =
  ResolvedFunctionCall(funcRef: funcRef, args: args)

# ResolvedAssignment
proc newResolvedAssignment(target: Identifier, expression: ResolvedExpression): ResolvedAssignment =
  ResolvedAssignment(target: target, expression: expression)

# ResolvedKeywordArgument
proc newResolvedKeywordArgument(name: Identifier, expression: ResolvedExpression): ResolvedKeywordArgument =
  ResolvedKeywordArgument(name: name, expression: expression)

# ResolvedStructInitializer
proc newResolvedStructInitializer(argType: ResolvedArgumentType, kwargs: seq[ResolvedKeywordArgument]): ResolvedStructInitializer =
  ResolvedStructInitializer(argType: argType, kwargs: kwargs)

# ResolvedUnionInitializer
proc newResolvedUnionInitializer(argType: ResolvedArgumentType, variant: Identifier, kwargs: seq[ResolvedKeywordArgument]): ResolvedUnionInitializer =
  ResolvedUnionInitializer(argType: argType, variant: variant, kwargs: kwargs)

# ResolvedInitializer
proc newResolvedInitializer(struct: ResolvedStructInitializer): ResolvedInitializer =
  ResolvedInitializer(kind: rikStruct, struct: struct)

proc newResolvedInitializer(union: ResolvedUnionInitializer): ResolvedInitializer =
  ResolvedInitializer(kind: rikUnion, union: union)

proc newResolvedInitializer(literal: ResolvedLiteralInitializer): ResolvedInitializer =
  ResolvedInitializer(kind: rikLiteral, literal: literal)

# ResolvedMutation
proc newResolvedMutation(getter: ResolvedGetter, expression: ResolvedExpression): ResolvedMutation =
  ResolvedMutation(getter: getter, expression: expression)

# ResolvedExpression
proc newResolvedExpression(fncall: ResolvedFunctionCall): ResolvedExpression =
  ResolvedExpression(kind: rekFunctionCall, fncall: fncall)

proc newResolvedExpression(initializer: ResolvedInitializer): ResolvedExpression =
  ResolvedExpression(kind: rekInitializer, initializer: initializer)

proc newResolvedExpression(variable: Identifier): ResolvedExpression =
  ResolvedExpression(kind: rekVariable, variable: variable)

proc newResolvedExpression(literal: Literal): ResolvedExpression =
  ResolvedExpression(kind: rekLiteral, literal: literal)

proc newResolvedExpression(getter: ResolvedGetter): ResolvedExpression =
  ResolvedExpression(kind: rekGetter, getter: getter)

proc newResolvedExpression(match: ResolvedMatchExpression): ResolvedExpression =
  ResolvedExpression(kind: rekMatchExpr, match: match)

# ResolvedCaseBlock
proc newResolvedCaseBlock(pattern: ResolvedCasePattern, statements: seq[ResolvedStatement]): ResolvedCaseBlock =
  ResolvedCaseBlock(pattern: pattern, statements: statements)

# ResolvedMatchExpression
proc newResolvedMatchExpression(subject: ResolvedExpression, cases: seq[ResolvedCaseBlock]): ResolvedMatchExpression =
  ResolvedMatchExpression(subject: subject, cases: cases)

# ResolvedStatement
proc newResolvedStatement(assignment: ResolvedAssignment): ResolvedStatement =
  ResolvedStatement(kind: rskAssignment, assignment: assignment)

proc newResolvedStatement(expression: ResolvedExpression): ResolvedStatement =
  ResolvedStatement(kind: rskExpr, expression: expression)

proc newResolvedStatement(mutation: ResolvedMutation): ResolvedStatement =
  ResolvedStatement(kind: rskMutation, mutation: mutation)

proc variable(statement: ResolvedStatement): Option[Identifier] =
  case statement.kind:
  of rskAssignment: some(statement.assignment.target)
  of rskExpr: none(Identifier)
  of rskMutation: none(Identifier)

proc resolveExpression(app: App, file: File, fileScope: FileScope, module: Module, scope: FunctionScope, expression: Expression): Result[ResolvedExpression, string]
proc resolveStatement(app: App, file: File, fileScope: FileScope, module: Module, scope: FunctionScope, statement: Statement): Result[ResolvedStatement, string]

proc resolveFunctionCall(app: App, file: File, fileScope: FileScope, module: Module, scope: FunctionScope, fncall: FunctionCall): Result[ResolvedFunctionCall, string] =
  let resolvedFunctionRef = ? resolveFunctionRef(app, file, fileScope, module, scope, fncall.argType, fncall.name, fncall.args.len)
  var resolvedArgs: seq[ResolvedExpression]
  for arg in fncall.args:
    let resolvedArg = ? resolveExpression(app, file, fileScope, module, scope, arg)
    resolvedArgs.add(resolvedArg)
  ok(newResolvedFunctionCall(resolvedFunctionRef, resolvedArgs))

proc resolveStructInitializer(app: App, file: File, fileScope: FileScope, module: Module, scope: FunctionScope, struct: StructInitializer): Result[ResolvedStructInitializer, string] =
  let resolvedArgType = ? resolveArgumentType(app, file, fileScope, module, struct.argType)
  let structType = ? file.findType(struct.argType.root)
  case structType.kind:
  of tkImported: err(fmt"{struct.loc} todo: resolve imported struct initializer")
  of tkDefined:
    let definedType = structType.definedType
    case definedType.kind:
    of dtkGeneric: err(fmt"{struct.loc} type `{definedType.name.asl}` is a generic and not struct")
    of dtkModule:
      let structModule = definedType.module
      if structModule.data.isNone:
        err(fmt"{struct.loc} module `{structModule.name.asl}` is not a struct")
      else:
        let dataBlock = structModule.data.get
        case dataBlock.kind:
        of dbkLiteral: err(fmt"{dataBlock.loc} module `{structModule.name.asl}` is a literal")
        of dbkUnion: err(fmt"{dataBlock.loc} module `{structModule.name.asl}` is a union")
        of dbkStruct:
          let structBlock = dataBlock.struct
          if struct.kwargs.len != structBlock.fields.len:
            err(fmt"{struct.loc} struct `{structModule.name.asl}` expects `{structBlock.fields.len}` but `{struct.kwargs.len}` were given")
          else:
            var resolvedKeywordArgs = newSeq[ResolvedKeywordArgument](structBlock.fields.len)
            for kwarg in struct.kwargs:
              let fieldId = ? structBlock.findFieldId(kwarg.name)
              let resolvedExpression = ? resolveExpression(app, file, fileScope, module, scope, kwarg.expression)
              resolvedKeywordArgs[fieldId] = newResolvedKeywordArgument(kwarg.name, resolvedExpression)
            ok(newResolvedStructInitializer(resolvedArgType, resolvedKeywordArgs))

proc resolveUnionInitializer(app: App, file: File, fileScope: FileScope, module: Module, scope: FunctionScope, unionInit: UnionInitializer): Result[ResolvedUnionInitializer, string] =
  let resolvedArgType = ? resolveArgumentType(app, file, fileScope, module, unionInit.argType)
  let unionType = ? file.findType(unionInit.argType.root)
  case unionType.kind:
  of tkImported: err(fmt"{unionInit.loc} todo: resolve imported type union initializer")
  of tkDefined:
    let unionDefinedType = unionType.definedType
    case unionDefinedType.kind:
    of dtkGeneric: err(fmt"{unionInit.loc} type `{unionDefinedType.name.asl}` is a generic and not union")
    of dtkModule:
      let unionModule = unionDefinedType.module
      if unionModule.data.isNone:
        err(fmt"{unionInit.loc} module `{unionModule.name.asl}` is not a union")
      else:
        let dataBlock = unionModule.data.get
        case dataBlock.kind:
        of dbkLiteral: err(fmt"{dataBlock.loc} module `{unionModule.name.asl}` is a literal")
        of dbkStruct: err(fmt"{dataBlock.loc} module `{unionModule.name.asl}` is a struct")
        of dbkUnion:
          let union = dataBlock.union
          let variant = ? union.findVariant(unionInit.variant)
          if unionInit.kwargs.len != variant.fields.len:
            err(fmt"{unionInit.loc} union `{unionModule.name.asl}` expects `{variant.fields.len}` but `{unionInit.kwargs.len}` were given")
          else:
            var resolvedKeywordArgs = newSeq[ResolvedKeywordArgument](variant.fields.len)
            for kwarg in unionInit.kwargs:
              let fieldId = ? variant.findFieldId(kwarg.name)
              let resolvedExpression = ? resolveExpression(app, file, fileScope, module, scope, kwarg.expression)
              resolvedKeywordArgs[fieldId] = newResolvedKeywordArgument(kwarg.name, resolvedExpression)
            ok(newResolvedUnionInitializer(resolvedArgType, variant.name, resolvedKeywordArgs))

proc resolveInitializer(app: App, file: File, fileScope: FileScope, module: Module, scope: FunctionScope, initializer: Initializer): Result[ResolvedInitializer, string] =
  case initializer.kind:
  of ikLiteral:
    let resolvedLiteralInit = ? resolveLiteralInitializer(app, file, fileScope, module, scope, initializer.literal)
    ok(newResolvedInitializer(resolvedLiteralInit))
  of ikStruct:
    let resolvedStructInit = ? resolveStructInitializer(app, file, fileScope, module, scope, initializer.struct)
    ok(newResolvedInitializer(resolvedStructInit))
  of ikUnion:
    let resolvedUnionInit = ? resolveUnionInitializer(app, file, fileScope, module, scope, initializer.union)
    ok(newResolvedInitializer(resolvedUnionInit))

proc resolveCaseBlock(app: App, file: File, fileScope: FileScope, module: Module, scope: FunctionScope, caseBlock: CaseBlock): Result[ResolvedCaseBlock, string] =
  let resolvedCasePattern = ? resolveCasePattern(app, file, module, scope, caseBlock.pattern)
  var resovledStatements: seq[ResolvedStatement]
  var childScope = scope # create a child scope to enable shadowing

  for binding in caseBlock.pattern.bindings:
    childScope.incl(binding)

  for statement in caseBlock.statements:
    let resolvedStatement = ? resolveStatement(app, file, fileScope, module, childScope, statement)
    resovledStatements.add(resolvedStatement)
    if resolvedStatement.variable.isSome: childScope.incl(resolvedStatement.variable.get)
  ok(newResolvedCaseBlock(resolvedCasePattern, resovledStatements))

proc resolveMatchExpression(app: App, file: File, fileScope: FileScope, module: Module, scope: FunctionScope, match: MatchExpression): Result[ResolvedMatchExpression, string] =
  let resolvedSubject = ? resolveExpression(app, file, fileScope, module, scope, match.subject)
  var resolvedCaseBlocks: seq[ResolvedCaseBlock]
  for caseBlock in match.cases:
    let resolvedCaseBlock = ? resolveCaseBlock(app, file, fileScope, module, scope, caseBlock)
    resolvedCaseBlocks.add(resolvedCaseBlock)
  ok(newResolvedMatchExpression(resolvedSubject, resolvedCaseBlocks))

proc resolveExpression(app: App, file: File, fileScope: FileScope, module: Module, scope: FunctionScope, expression: Expression): Result[ResolvedExpression, string] =
  case expression.kind:
  of ekLiteral:
    ok(newResolvedExpression(expression.literal))
  of ekGetter:
    let resolvedGetter = ? resolveGetter(app, file, module, scope, expression.getter)
    ok(newResolvedExpression(resolvedGetter))
  of ekVariable:
    let resolvedVariable = ? resolveVariable(app, file, module, scope, expression.variable)
    ok(newResolvedExpression(resolvedVariable))
  of ekFnCall:
    let resolvedFunctionCall = ? resolveFunctionCall(app, file, fileScope, module, scope, expression.fncall)
    ok(newResolvedExpression(resolvedFunctionCall))
  of ekInitializer:
    let resolvedInitializer = ? resolveInitializer(app, file, fileScope, module, scope, expression.initializer)
    ok(newResolvedExpression(resolvedInitializer))
  of ekMatch:
    let resolvedMatchExpr = ? resolveMatchExpression(app, file, fileScope, module, scope, expression.match)
    ok(newResolvedExpression(resolvedMatchExpr))

proc resolveAssignment(app: App, file: File, fileScope: FileScope, module: Module, scope: FunctionScope, assignment: Assignment): Result[ResolvedAssignment, string] =
  let resolvedExpression = ? resolveExpression(app, file, fileScope, module, scope, assignment.expression)
  ok(newResolvedAssignment(assignment.target, resolvedExpression))

proc resolveMutation(app: App, file: File, fileScope: FileScope, module: Module, scope: FunctionScope, mutation: Mutation): Result[ResolvedMutation, string] =
  let resolvedGetter = ? resolveGetter(app, file, module, scope, mutation.target)
  let resolvedExpression = ? resolveExpression(app, file, fileScope, module, scope, mutation.expression)
  ok(newResolvedMutation(resolvedGetter, resolvedExpression))

proc resolveStatement(app: App, file: File, fileScope: FileScope, module: Module, scope: FunctionScope, statement: Statement): Result[ResolvedStatement, string] =
  case statement.kind:
  of skExpr:
    let resolvedExpression = ? resolveExpression(app, file, fileScope, module, scope, statement.expression)
    ok(newResolvedStatement(resolvedExpression))
  of skAssignment:
    let resolvedAssignment = ? resolveAssignment(app, file, fileScope, module, scope, statement.assignment)
    ok(newResolvedStatement(resolvedAssignment))
  of skMutation:
    let resolvedMutation = ? resolveMutation(app, file, fileScope, module, scope, statement.mutation)
    ok(newResolvedStatement(resolvedMutation))

type ResolvedUserFunction = ref object
  funcDef: ResolvedFunctionDefinition
  statements: seq[ResolvedStatement]

proc newResolvedUserFunction(funcDef: ResolvedFunctionDefinition, statements: seq[ResolvedStatement]): ResolvedUserFunction =
  ResolvedUserFunction(funcDef: funcDef, statements: statements)

proc resolveUserFunction(app: App, file: File, fileScope: FileScope, module: Module, function: UserFunction): Result[ResolvedUserFunction, string] =
  if function.decorators.len > 0:
    return err(fmt"{function.loc} todo: resolve decorators in user function")

  let resolvedFunctionDefinition = ? resolveFunctionDefinition(app, file, fileScope, module, function.def)

  var scope: FunctionScope
  for arg in resolvedFunctionDefinition.args:
    scope.incl(arg.name)

  var resolvedStatements: seq[ResolvedStatement]
  for statement in function.statements:
    let resolvedStatement = ? resolveStatement(app, file, fileScope, module, scope, statement)
    resolvedStatements.add(resolvedStatement)
    if resolvedStatement.variable.isSome: scope.incl(resolvedStatement.variable.get)

  ok(newResolvedUserFunction(resolvedFunctionDefinition, resolvedStatements))

type
  ResolvedFunctionKind = enum
    rfkExtern, rfkUser
  ResolvedFunction = ref object
    case kind: ResolvedFunctionKind
    of rfkExtern: extern: ResolvedExternFunction
    of rfkUser: user: ResolvedUserFunction

proc newResolvedFunction(extern: ResolvedExternFunction): ResolvedFunction =
  ResolvedFunction(kind: rfkExtern, extern: extern)

proc newResolvedFunction(user: ResolvedUserFunction): ResolvedFunction =
  ResolvedFunction(kind: rfkUser, user: user)

proc resolveFunction(app: App, file: File, fileScope: FileScope, module: Module, function: Function): Result[ResolvedFunction, string] =
  case function.kind:
  of fkUser:
    let resolvedUserFunction = ? resolveUserFunction(app, file, fileScope, module, function.user)
    ok(newResolvedFunction(resolvedUserFunction))
  of fkExtern:
    let resolvedExternFunction = ? resolveExternFunction(app, file, fileScope, module, function.extern)
    ok(newResolvedFunction(resolvedExternFunction))

type ResolvedStruct = ref object
  fields: seq[ResolvedArgumentDefinition]

proc newResolvedStruct(fields: seq[ResolvedArgumentDefinition]): ResolvedStruct =
  ResolvedStruct(fields: fields)

proc resolveStruct(app: App, file: File, fileScope: FileScope, module: Module, struct: Struct): Result[ResolvedStruct, string] =
  var resolvedFields: seq[ResolvedArgumentDefinition]
  for field in struct.fields:
    let resolvedField = ? resolveArgumentDefinition(app, file, fileScope, module, field)
    resolvedFields.add(resolvedField)
  ok(newResolvedStruct(resolvedFields))

type ResolvedVariant = ref object
  name: Identifier
  fields: seq[ResolvedArgumentDefinition]

proc newResolvedVariant(name: Identifier, fields: seq[ResolvedArgumentDefinition]): ResolvedVariant =
  ResolvedVariant(name: name, fields: fields)

proc resolveVariant(app: App, file: File, fileScope: FileScope, module: Module, variant: VariantDefinition): Result[ResolvedVariant, string] =
  var resolvedFields: seq[ResolvedArgumentDefinition]
  for field in variant.fields:
    let resolvedField = ? resolveArgumentDefinition(app, file, fileScope, module, field)
    resolvedFields.add(resolvedField)
  ok(newResolvedVariant(variant.name, resolvedFields))

type ResolvedUnion = ref object
  variants: seq[ResolvedVariant]

proc newResolvedUnion(variants: seq[ResolvedVariant]): ResolvedUnion =
  ResolvedUnion(variants: variants)

proc resolveUnion(app: App, file: File, fileScope: FileScope, module: Module, union: Union): Result[ResolvedUnion, string] =
  var resolvedVariants: seq[ResolvedVariant]
  for variant in union.variants:
    let resolvedVariant = ? resolveVariant(app, file, fileScope, module, variant)
    resolvedVariants.add(resolvedVariant)
  ok(newResolvedUnion(resolvedVariants))

type
  ResolvedDataKind = enum
    rdkLiteral, rdkStruct, rdkUnion
  ResolvedData = ref object
    case kind: ResolvedDataKind
    of rdkLiteral: literal: ResolvedLiteralType
    of rdkStruct: struct: ResolvedStruct
    of rdkUnion: union: ResolvedUnion

proc newResolvedData(literal: ResolvedLiteralType): ResolvedData =
  ResolvedData(kind: rdkLiteral, literal: literal)

proc newResolvedData(struct: ResolvedStruct): ResolvedData =
  ResolvedData(kind: rdkStruct, struct: struct)

proc newResolvedData(union: ResolvedUnion): ResolvedData =
  ResolvedData(kind: rdkUnion, union: union)

proc resolveDataBlock(app: App, file: File, fileScope: FileScope, module: Module, data: DataBlock): Result[ResolvedData, string] =
  case data.kind:
  of dbkLiteral:
    let resolvedLiteralType = ? resolveLiteralType(file, data.literal)
    ok(newResolvedData(resolvedLiteralType))
  of dbkStruct:
    let resolvedStruct = ? resolveStruct(app, file, fileScope, module, data.struct)
    ok(newResolvedData(resolvedStruct))
  of dbkUnion:
    let resolvedUnion = ? resolveUnion(app, file, fileScope, module, data.union)
    ok(newResolvedData(resolvedUnion))

type ResolvedModule = ref object
  requires: seq[Generic]
  data: Option[ResolvedData]
  functions: seq[ResolvedFunction]

proc newResolvedModule(requires: seq[Generic], data: Option[ResolvedData], functions: seq[ResolvedFunction]): ResolvedModule =
  ResolvedModule(requires: requires, data: data, functions: functions)

proc resolveModule(app: App, file: File, fileScope: FileScope, module: Module): Result[ResolvedModule, string] =
  if module.decorators.len > 0:
    return err("todo: resolve decorators")

  var resolvedRequires: seq[Generic]
  if module.requires.isSome:
    for generic in module.requires.get.generics:
      let dataType = ? file.findType(generic)
      case dataType.kind:
      of tkImported:
        return err("todo: resolve imported type in requires block")
      of tkDefined:
        let definedType = dataType.definedType
        case definedType.kind:
        of dtkModule:
          return err(fmt"{generic.loc} type `{generic.asl}` is a module but expected generic")
        of dtkGeneric:
          resolvedRequires.add(definedType.generic)

  var resolvedData: Option[ResolvedData]
  if module.data.isSome:
    let resolvedDataBlock = ? resolveDataBlock(app, file, fileScope, module, module.data.get)
    resolvedData = some(resolvedDataBlock)

  var resolvedFunctions: seq[ResolvedFunction]
  for function in module.functions:
    let resolvedFunction = ? resolveFunction(app, file, fileScope, module, function)
    resolvedFunctions.add(resolvedFunction)

  ok(newResolvedModule(resolvedRequires, resolvedData, resolvedFunctions))

type ResolvedGeneric = ref object
  public: bool
  name: Identifier
  funcDefs: seq[ResolvedFunctionDefinition]

proc newResolvedGeneric(public: bool, name: Identifier, funcDefs: seq[ResolvedFunctionDefinition]): ResolvedGeneric =
  ResolvedGeneric(public: public, name: name, funcDefs: funcDefs)

proc resolveGeneric(app: App, file: File, generic: Generic): Result[ResolvedGeneric, string] =
  if generic.decorators.len > 0:
    return err(fmt"{generic.loc} todo: resolve generic decorators")

  var resolvedFunctionDefs: seq[ResolvedFunctionDefinition]
  for funcDef in generic.funcDefs:
    let resolvedFunctionDefinition = ? resolveFunctionDefinition(app, file, generic, funcDef)
    resolvedFunctionDefs.add(resolvedFunctionDefinition)

  ok(newResolvedGeneric(generic.public, generic.name, resolvedFunctionDefs))

type
  ResolvedDefinedTypeKind = enum
    rdtkModule, rdtkGeneric
  ResolvedDefinedType = ref object
    case kind: ResolvedDefinedTypeKind
    of rdtkModule: module: ResolvedModule
    of rdtkGeneric: generic: ResolvedGeneric

proc newResolvedDefinedType(module: ResolvedModule): ResolvedDefinedType =
  ResolvedDefinedType(kind: rdtkModule, module: module)

proc newResolvedDefinedType(generic: ResolvedGeneric): ResolvedDefinedType =
  ResolvedDefinedType(kind: rdtkGeneric, generic: generic)

proc resolveDefinedType(app: App, file: File, fileScope: FileScope, definedType: DefinedType): Result[ResolvedDefinedType, string] =
  case definedType.kind:
  of dtkGeneric:
    let resolvedGeneric = ? resolveGeneric(app, file, definedType.generic)
    ok(newResolvedDefinedType(resolvedGeneric))
  of dtkModule:
    let resolvedModule = ? resolveModule(app, file, fileScope, definedType.module)
    ok(newResolvedDefinedType(resolvedModule))

type ResolvedFile = ref object
  imports: seq[ResolvedImport]
  definedTypes: seq[ResolvedDefinedType]

proc newResolvedFile(imports: seq[ResolvedImport], definedTypes: seq[ResolvedDefinedType]): ResolvedFile =
  ResolvedFile(imports: imports, definedTypes: definedTypes)

proc resolveFile(app: App, file: File): Result[ResolvedFile, string] =
  var resolvedImports: seq[ResolvedImport]
  var fileScope: FileScope
  for imp in file.imports:
    let resolvedImport = ? resolveImport(app, file, imp)
    resolvedImports.add(resolvedImport)
    for impType in resolvedImport.importedTypes:
      fileScope[impType.binding] = impType.definedType

  var resolvedDefinedTypes: seq[ResolvedDefinedType]
  for definedType in file.definedTypes:
    let resolvedDefinedType = ? resolveDefinedType(app, file, fileScope, definedType)
    resolvedDefinedTypes.add(resolvedDefinedType)

  ok(newResolvedFile(resolvedImports, resolvedDefinedTypes))

type ResolvedApp = ref object
  files: seq[ResolvedFile]

proc newResolvedApp(files: seq[ResolvedFile]): ResolvedApp =
  ResolvedApp(files: files)

proc resolve*(app: App): Result[ResolvedApp, string] =
  var resolvedFiles: seq[ResolvedFile]
  for file in app.files:
    let maybeResolvedFile = resolveFile(app, file)
    if maybeResolvedFile.isErr:
      return err(fmt"{file.path}:{maybeResolvedFile.error}")
    else:
      resolvedFiles.add(maybeResolvedFile.get)
  ok(newResolvedApp(resolvedFiles))
