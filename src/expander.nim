import options, tables, strformat, strutils, sequtils, strformat

import analyzer/main as analyzer
import parser/main as parser
import resolver/main as resolver
import defanalyzer/main as defanalyzer
import codegen

type
  AnalyzedTypeKind = enum
    atkGeneric, atkModule
  AnalyzedType = ref object
    case kind: AnalyzedTypeKind
    of atkGeneric: generic: AnalyzedGeneric
    of atkModule: module: AnalyzedModule

proc newAnalyzedType(module: AnalyzedModule): AnalyzedType =
  AnalyzedType(kind: atkModule, module: module)

proc newAnalyzedType(generic: AnalyzedGeneric): AnalyzedType =
  AnalyzedType(kind: atkGeneric, generic: generic)

proc resolved(analyzedType: AnalyzedType): ResolvedLocalType =
  case analyzedType.kind:
  of atkGeneric: newResolvedLocalType(analyzedType.generic.resolved)
  of atkModule: newResolvedLocalType(analyzedType.module.resolved)

type IRApp = ref object
  analyzed: AnalyzedApp
  typeIndex: Table[ResolvedLocalType, int]
  types: seq[AnalyzedType]

proc newIRApp(app: AnalyzedApp): IRApp =
  var typeIndex: Table[ResolvedLocalType, int]
  var types: seq[AnalyzedType]
  for file in app.files:
    for module in file.modules:
      let localType = newResolvedLocalType(module.resolved)
      assert(localType notin typeIndex, "[BUG] - duplicate module hash collision")
      typeIndex[localType] = types.len
      types.add(newAnalyzedType(module))

  for file in app.files:
    for generic in file.generics:
      let localType = newResolvedLocalType(generic.resolved)
      assert(localType notin typeIndex, "[BUG] - duplicate generic hash collision")
      typeIndex[localType] = types.len
      types.add(newAnalyzedType(generic))

  IRApp(analyzed: app, typeIndex: typeIndex, types: types)

proc findTypeId(app: IRApp, localType: ResolvedLocalType): int =
  assert(localType in app.typeIndex, "[BUG] - resolved local type must exist in the index")
  app.typeIndex[localType]

proc findType(app: IRApp, localType: ResolvedLocalType): AnalyzedType = app.types[app.findTypeId(localType)]

proc findType(app: IRApp, localType: AnalyzedLocalType): AnalyzedType =
  app.findType(localType.resolved)

proc findModuleId(app: IRApp, module: ResolvedModule): int =
  let id = app.findTypeId(newResolvedLocalType(module))
  let analyzedType = app.types[id]
  assert(analyzedType.kind == atkModule, "[BUG] - resolved local type must be a module")
  return id

proc findModule(app: IRApp, module: ResolvedModule): AnalyzedModule =
  let analyzedType = app.findType(newResolvedLocalType(module))
  assert(analyzedType.kind == atkModule, "[BUG] - resolved local type must be a module")
  analyzedType.module

proc findGenericId(app: IRApp, generic: ResolvedGeneric): int =
  let id = app.findTypeId(newResolvedLocalType(generic))
  let analyzedType = app.types[id]
  assert(analyzedType.kind == atkGeneric, "[BUG] - resolved local type must be a generic")
  return id

proc findGeneric(app: IRApp, generic: ResolvedGeneric): AnalyzedGeneric =
  let analyzedType = app.findType(newResolvedLocalType(generic))
  assert(analyzedType.kind == atkGeneric, "[BUG] - resolved local type must be a generic")
  analyzedType.generic

proc findType(app: IRApp, argType: AnalyzedArgumentType): string =
  case argType.kind:
  of aatkGeneric: "pointer"
  of aatkModule:
    let argModule = app.findModule(argType.module.module)
    assert(argModule.data.isSome, "[BUG] - a pure functional module can not be used as an argument")
    let data = argModule.data.get
    case data.kind:
    of adkLiteral: data.literal.ctype
    of adkStruct, adkUnion: "pointer"

proc fields(app: IRApp, fields: seq[AnalyzedArgumentDef]): (seq[string], seq[string]) =
  var fieldNames: seq[string]
  var fieldTypes: seq[string]
  for field in fields:
    let fieldType = app.findType(field.argType)
    fieldTypes.add(fieldType)
    fieldNames.add(field.name.asl)
  return (fieldNames, fieldTypes)


proc expand(app: IRApp, expected: AnalyzedArgumentType, actual: AnalyzedArgumentType, argId: int, resultArg: string, input: bool = true): (seq[string], int, string) =
  var code: seq[string]
  var newArgId = argId
  var lastArg = resultArg
  case expected.kind:
  of aatkModule:
    case actual.kind:
    of aatkModule: discard
    of aatkGeneric: assert(false, "[BUG] - generic types can not be coerced to module types")
  of aatkGeneric:
    case actual.kind:
    of aatkGeneric: discard
    of aatkModule:
      let argModule = app.findModule(actual.module.module)
      assert(argModule.data.isSome, "[BUG] - module argument type must have a data block")
      let argData = argModule.data.get
      let ctype =
        case argData.kind:
        of adkLiteral: argData.literal.ctype
        of adkStruct, adkUnion: "pointer"

      lastArg = fmt"__asl_arg_{newArgId}"
      newArgId += 1

      let op = if input: "wrap" else: "unwrap"
      code.add(fmt"pointer {lastArg} = {ctype}_{op}(resultArg);")

  return (code, newArgId, lastArg)

proc expand(app: IRApp, moduleName: string, variant: AnalyzedVariantDef, variantId: int): seq[string] =
  let (fieldNames, fieldTypes) = app.fields(variant.fields())
  variantFunctions(moduleName, variant.name.asl, variantId, fieldNames, fieldTypes)

proc expand(moduleName: string, literal: AnalyzedLiteralDef): seq[string] =
  literalByteSizeFunction(moduleName, literal.ctype)

proc expand(app: IRApp, moduleName: string, struct: AnalyzedStructDef): seq[string] =
  let (fieldNames, fieldTypes) = app.fields(struct.fields)
  structFunctions(moduleName, fieldNames, fieldTypes)

proc expand(app: IRApp, moduleName: string, union: AnalyzedUnionDef): seq[string] =
  var code: seq[string]
  code.add(unionIdGetterFunction(moduleName))
  code.add(unionIdSetterFunction(moduleName))
  for variantId, variant in union.variants:
    code.add(expand(app, moduleName, variant, variantId))
  return code

proc expand(app: IRApp, moduleName: string, data: AnalyzedDataDef): seq[string] =
  case data.kind:
  of adkLiteral: expand(moduleName, data.literal)
  of adkStruct: expand(app, moduleName, data.struct)
  of adkUnion: expand(app, moduleName, data.union)

proc expand(app: IRApp, statement: AnalyzedStatement, argId: int): (seq[string], int, string)
proc expand(app: IRApp, expression: AnalyzedExpression, argId: int): (seq[string], int, string)

proc expand(app: IRApp, caseBlock: AnalyzedCaseBlock, subjectArgType: AnalyzedArgumentType, argId: int, subjectArg: string, resultArg: string): (seq[string], int, string) =
  assert(subjectArgType.kind == aatkModule, "[BUG] - match expression only support module types")
  let subjectModuleId = app.findModuleId(subjectArgType.module.module)
  let subjectModule = app.findModule(subjectArgType.module.module)
  let subjectData = subjectModule.data.get
  let moduleName = fmt"{subjectModule.name.asl}_{subjectModuleId}"

  var code: seq[string]
  var newArgId = argId
  var lastArg: string
  case caseBlock.pattern.kind:
  of acpkVariable:
    code.add("default:")
    code.add("{")

    case subjectData.kind:
    of adkStruct: assert(false, "[BUG] - match expression do not support struct types")
    of adkLiteral:
      code.add(fmt"{subjectData.literal.ctype} {caseBlock.pattern.variable.name.asl} = {subjectArg};")
    of adkUnion:
      code.add(fmt"pointer {caseBlock.pattern.variable.name.asl} = {subjectArg};")

    assert(caseBlock.statements.len > 0, "[BUG] - case block can not be empty")
    for statement in caseBlock.statements:
      let res = expand(app, statement, newArgId)
      code.add(res[0])
      newArgId = res[1]
      lastArg = res[2]

    code.add("{resultArg} = {lastArg};")
    code.add("break;")
    code.add("}")
  of acpkUnion:
    assert(subjectData.kind == adkUnion, "[BUG] - unreachable module must be a union")
    let variant = caseBlock.pattern.variant.variant
    let variantId = subjectData.union.findVariantId(variant)
    let variantName = variant.name.asl
    code.add(fmt"case {variantId}: ")
    code.add("{")

    for binding in caseBlock.pattern.bindings:
      assert(binding.kind == abkVariantField, "[BUG] - union case pattern must have a variant field binding")
      let field = binding.variantField.field
      let fieldName = field.name.asl
      let funcName = fmt"{moduleName}_{variantName}_get_{fieldName}"
      let funcCall = fmt"{funcName}({subjectArg})"

      let argName = fmt"__asl_arg_{newArgId}"
      newArgId += 1
      lastArg = argName

      let ctype = app.findType(field.argType)
      code.add(fmt"{ctype} {argName} = {funcCall};")

      let res = expand(app, field.argType, binding.argType, newArgId, argName, input = false)
      code.add(res[0])
      newArgId = res[1]
      lastArg = res[2]

    assert(caseBlock.statements.len > 0, "[BUG] - case block can not be empty")
    for statement in caseBlock.statements:
      let res = expand(app, statement, newArgId)
      code.add(res[0])
      newArgId = res[1]
      lastArg = res[2]

    code.add("{resultArg} = {lastArg};")
    code.add("break;")
    code.add("}")
  of acpkInteger:
    assert(subjectData.kind == adkLiteral, "[BUG] - unreachable module must be a literal")
    code.add(fmt"case {caseBlock.pattern.integer.asl}: ")
    code.add("{")

    assert(caseBlock.statements.len > 0, "[BUG] - case block can not be empty")
    for statement in caseBlock.statements:
      let res = expand(app, statement, newArgId)
      code.add(res[0])
      newArgId = res[1]
      lastArg = res[2]

    code.add("{resultArg} = {lastArg};")
    code.add("break;")
    code.add("}")

  return (code, newArgId, lastArg)

proc expand(app: IRApp, match: AnalyzedMatchExpression, argId: int): (seq[string], int, string) =
  var code: seq[string]
  let res = expand(app, match.subject, argId)
  code.add(res[0])
  var newArgId = res[1]
  let subjectArg = res[2]

  let resultType = app.findType(match.returns)
  let resultArg = fmt"__asl_arg_{newArgId}"
  newArgId += 1
  code.add(fmt"{resultType} {resultArg};")

  let subjectArgType = match.subject.argType
  assert(subjectArgType.kind == aatkModule, "[BUG] - match expression only support module types")
  let subjectModule = app.findModule(subjectArgType.module.module)
  let subjectData = subjectModule.data.get
  case subjectData.kind:
  of adkStruct:
    assert(false, "[BUG] - match block does not support struct types")
  of adkLiteral:
    code.add(fmt"switch({subjectArg})")
  of adkUnion:
    let variantId = fmt"{subjectModule.name.asl}_get_id({subjectArg})"
    code.add(fmt"switch({variantId})")

  code.add("{")
  for caseBlock in match.cases:
    let res = expand(app, caseBlock, subjectArgType, newArgId, subjectArg, resultArg)
    code.add(res[0])
    newArgId = res[1]

  code.add("}")
  return (code, newArgId, resultArg)


proc expand(app: IRApp, fncall: AnalyzedFunctionCall, argId: int): (seq[string], int, string) =
  var code: seq[string]
  let typ = app.findType(fncall.localType)
  case typ.kind:
  of atkModule:
    let funcDefId = typ.module.findFunctionId(fncall.funcDef)
    let targetFunc = typ.module.findFunction(fncall.funcDef)
    let targetFuncDef = targetFunc.def
    let funcName = fmt"{targetFunc.name.asl}_{funcDefId}"

    var args: seq[string]
    for generic, impl in fncall.impls:
      args.add($(app.findGenericId(generic)))

    assert(fncall.args.len == targetFuncDef.args.len, "[BUG] - function call args length must be equal to function def args length")

    var newArgId = argId
    for id in countup(0, fncall.args.len - 1):
      let argDef = targetFuncDef.args[id]
      let argVal = fncall.args[id]

      let res = expand(app, argVal, newArgId)
      code.add(res[0])
      newArgId = res[1]
      let argName = res[2]

      case argVal.argType.kind:
      of aatkModule:
        let ctype = app.findType(argVal.argType)
        args.add(fmt"Generic_wrap_{ctype}(argName)")
      of aatkGeneric:
        assert(false)

    let argsString = args.join(", ")
    case targetFuncDef.returns.kind:
    of aatkModule:
      let ctype = app.findType(targetFuncDef.returns)
      let lastArg = fmt"__asl_arg_{newArgId}"
      newArgId += 1
      code.add(fmt"{ctype} {lastArg} = {funcName}({argsString});")
      return (code, newArgId, lastArg)
    of aatkGeneric:
      assert(false)
  of atkGeneric: assert(false)

proc expand(app: IRApp, init: AnalyzedInitializer, argId: int): (seq[string], int, string) =
  var code: seq[string]
  var newArgId: int = argId
  var lastArg: string
  case init.kind:
  of aikStruct:
    let structModuleId = app.findModuleId(init.struct.argType.module)
    let structModule = app.findModule(init.struct.argType.module)
    let funcName = fmt"{structModule.name.asl}_{structModuleId}_init"

    newArgId = argId
    var initArgs: seq[string]
    for kwarg in init.struct.kwargs:
      var res = expand(app, kwarg.expression, newArgId)
      code.add(res[0])
      newArgId = res[1]

      res = expand(app, kwarg.field.argType, kwarg.expression.argType, newArgId, res[2])
      code.add(res[0])
      newArgId = res[1]
      initArgs.add(res[2])

    lastArg = fmt"__asl_arg_{newArgId}"
    newArgId += 1
    let initArgsStr = initArgs.join(", ")
    code.add(fmt"pointer {lastArg} = {funcName}({initArgsStr});")
  of aikLiteral:
    let ctype = app.findType(init.literal.argType)
    lastArg = fmt"__asl_arg_{newArgId}"
    newArgId += 1
    code.add(fmt"{ctype} {lastArg} = {init.literal.literal.asl};")
  of aikUnion:
    let unionModuleId = app.findModuleId(init.union.argType.module)
    let unionModule = app.findModule(init.union.argType.module)
    let funcName = fmt"{unionModule.name.asl}_{unionModuleId}_{init.union.variant.asl}_init"

    newArgId = argId
    var initArgs: seq[string]
    for kwarg in init.union.kwargs:
      let res = expand(app, kwarg.expression, newArgId)
      code.add(res[0])
      newArgId = res[1]
      initArgs.add(res[2])

    lastArg = fmt"__asl_arg_{newArgId}"
    newArgId += 1
    let initArgsStr = initArgs.join(", ")
    code.add(fmt"pointer {lastArg} = {funcName}({initArgsStr});")

  return (code, newArgId, lastArg)

proc expand(app: IRApp, getter: AnalyzedGetter, argId: int): (seq[string], int, string) =
  let sourceModuleId = app.findModuleId(getter.source.module)
  let sourceModule = app.findModule(getter.source.module)

  let moduleName = fmt"{sourceModule.name.asl}_{sourceModuleId}"
  let funcName = "{moduleName}_get_{getter.property.name.asl}"


  assert(false)

proc expand(app: IRApp, variable: AnalyzedVariable, argId: int): (seq[string], int, string) =
  (@[], argId, variable.name.asl)

proc expand(app: IRApp, expression: AnalyzedExpression, argId: int): (seq[string], int, string) =
  case expression.kind:
  of aekFunctionCall: expand(app, expression.fncall, argId)
  of aekGetter: expand(app, expression.getter, argId)
  of aekInitializer: expand(app, expression.init, argId)
  of aekMatchExpr: expand(app, expression.match, argId)
  of aekVariable: expand(app, expression.variable, argId)


proc expand(app: IRApp, assignment: AnalyzedAssignment, argId: int): (seq[string], int, string) =
  let res = expand(app, assignment.expression, argId)

  var code: seq[string]
  code.add(res[0])
  code.add(fmt"// {assignment.target.asl} = {res[2]};")
  return (code, res[1], res[2])


proc expand(app: IRApp, statement: AnalyzedStatement, argId: int): (seq[string], int, string) =
  expand(app, statement.assignment, argId)

proc expand*(app: AnalyzedApp): string =
  let app = newIRApp(app)
  # keep track of extern name -> function signature mapping
  var externFunctions: Table[string, string]

  var code: seq[string]
  for id, typ in app.types:
    case typ.kind:
    of atkModule:
      let module = typ.module
      let moduleName = fmt"{module.name.asl}_{id}"
      if module.data.isSome: code.add(expand(app, moduleName, module.data.get))

      for functionId, function in module.functions:
        let funcName = fmt"{moduleName}_{function.name.asl}_{functionId}"
        case function.kind:
        of afkGenerated:
          # NOTE: only byte_size must be a generated function
          assert(function.generated.name.asl == "byte_size" and function.generated.arity == 0, "[BUG] - only `byte_size` must be a generated function")
        of afkExtern:
          let extern = function.extern

          var argDefs: seq[string]
          var argVals: seq[string]
          for id, _ in extern.generics:
            argDefs.add(fmt"uint32 __asl_generic_{id}")
            argVals.add(fmt"__asl_generic_{id}")
          for arg in extern.def.args:
            let argType = app.findType(arg.argType)
            argDefs.add(fmt"{argType} {arg.name.asl}")
            argVals.add(arg.name.asl)

          let returnType = app.findType(extern.def.returns)
          let argDefsStr = argDefs.join(", ")
          let externDef = fmt"{returnType} {extern.ffi}({argDefsStr})"

          if extern.ffi in externFunctions:
            let prevDef = externFunctions[extern.ffi]
            assert(prevDef == externDef, fmt"[BUG] - extern function misconfiguration encountered")
          else:
            externFunctions[extern.ffi] = externDef

          code.add(fmt"{returnType} {funcName}({argDefsStr})")
          code.add("{")
          let argValsStr = argVals.join(", ")
          code.add(fmt"return {extern.ffi}({argValsStr});")
          code.add("}")
        of afkUser:
          let userFunc = function.user
          var args: seq[string]
          for id, _ in userFunc.generics:
            args.add(fmt"uint32 __asl_generic_{id}")
          for arg in userFunc.def.args:
            let argType = app.findType(arg.argType)
            args.add(fmt"{argType} {arg.name.asl}")

          let returnType = app.findType(userFunc.def.returns)
          let argsStr = args.join(", ")
          code.add(fmt"{returnType} {funcName}({argsStr})")
          code.add("{")
          var argId: int = 0
          for statement in userFunc.statements:
            let res = expand(app, statement, argId)
            code.add(res[0])
            argId = res[1]

          code.add("return {lastArg};")
          code.add("}")
    of atkGeneric:
      discard
      # assert(false)

  return code.join("\n")