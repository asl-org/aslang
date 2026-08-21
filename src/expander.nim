import options, tables, strformat, strutils

import analyzer
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

proc findModule(app: IRApp, module: ResolvedModule): AnalyzedModule =
  let localType = newResolvedLocalType(module)
  assert(localType in app.typeIndex, "[BUG] - resolved local type must exist in the index")
  let analyzedType = app.types[app.typeIndex[localType]]
  assert(analyzedType.kind == atkModule, "[BUG] - resolved local type must be a module")
  analyzedType.module

proc findGeneric(app: IRApp, generic: ResolvedGeneric): AnalyzedGeneric =
  let localType = newResolvedLocalType(generic)
  assert(localType in app.typeIndex, "[BUG] - resolved local type must exist in the index")
  let analyzedType = app.types[app.typeIndex[localType]]
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

      for function in module.functions:
        case function.kind:
        of afkGenerated:
          # NOTE: only byte_size must be a generated function
          assert(function.generated.name.asl == "byte_size" and function.generated.arity == 0, "[BUG] - only `byte_size` must be a generated function")
        of afkExtern:
          let extern = function.extern

          var args: seq[string]
          for id, _ in extern.generics:
            args.add(fmt"uint32_t __asl_generic_{id}")
          for arg in extern.def.args:
            let argType = app.findType(arg.argType)
            args.add(fmt"{argType} {arg.name.asl}")

          let returnType = app.findType(extern.def.returns)
          let argsStr = args.join(", ")
          let externDef = fmt"{returnType} {extern.ffi}({argsStr})"

          if extern.ffi in externFunctions:
            let prevDef = externFunctions[extern.ffi]
            assert(prevDef == externDef, fmt"[BUG] - extern function misconfiguration encountered")
          else:
            externFunctions[extern.ffi] = externDef
        of afkUser:
          discard
          # assert(false)
    of atkGeneric:
      discard
      # assert(false)

  return code.join("\n")