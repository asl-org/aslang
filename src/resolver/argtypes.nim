## Argument-type resolution. The three Resolved*ArgumentType ref
## objects are mutually recursive (an impl is itself a
## ResolvedArgumentType), so they live in one type block. This file
## also owns FileScope (a Table[Identifier, DefinedType]) since
## resolveArgumentType is the first proc that consults it.
##
## The procs come in module-context and generic-context overloads.
## resolveDataType is the post-resolution guard that asserts a
## referenced module actually has a struct/union/literal data block
## (or — inside a generic block — that an unsubstituted generic is
## acceptable as a field/argument type).

import results, options, strformat, tables, hashes

import tokenizer
import parser

# FileScope alias — keyed by binding (alias-or-name); shared by
# every resolver file that walks bodies.
type FileScope* = Table[Identifier, DefinedType]

# ResolvedModuleArgumentType / ResolvedDefinedArgumentType /
# ResolvedArgumentType — mutually recursive cluster (an impl is
# itself a ResolvedArgumentType).
type
  ResolvedModuleArgumentType* = ref object
    root: Module
    impls: seq[ResolvedArgumentType]
    loc: Location

  ResolvedGenericArgumentType* = ref object
    generic: Generic
    loc: Location

  ResolvedDefinedArgumentTypeKind* = enum
    rdatkModule, rdatkGeneric

  ResolvedDefinedArgumentType* = ref object
    case kind: ResolvedDefinedArgumentTypeKind
    of rdatkModule: module: ResolvedModuleArgumentType
    of rdatkGeneric: generic: ResolvedGenericArgumentType

  ResolvedArgumentTypeKind* = enum
    ratkImported, ratkDefined

  ResolvedArgumentType* = ref object
    case kind: ResolvedArgumentTypeKind
    of ratkImported: discard
    of ratkDefined: definedType: ResolvedDefinedArgumentType

proc newResolvedGenericArgumentType*(generic: Generic, loc: Location): ResolvedGenericArgumentType =
  ResolvedGenericArgumentType(generic: generic, loc: loc)

proc parsed*(argType: ResolvedGenericArgumentType): Generic = argType.generic
proc name*(argType: ResolvedGenericArgumentType): Identifier = argType.generic.name
proc loc*(argType: ResolvedGenericArgumentType): Location = argType.loc
# TODO: hash conflicts may occur because `loc` only considers line and col in hash not file path.
proc hash*(argType: ResolvedGenericArgumentType): Hash = argType.generic.hash
proc `==`*(a, b: ResolvedGenericArgumentType): bool = a.hash == b.hash

# Forward declarations — both context overloads need to be declared
# up front because resolveModuleArgumentType recurses through them
# when resolving impls.
proc hash*(argType: ResolvedArgumentType): Hash

proc resolveArgumentType*(app: App, file: parser.File, fileScope: FileScope, module: Module, argType: ArgumentType): Result[ResolvedArgumentType, string]

proc resolveArgumentType*(app: App, file: parser.File, fileScope: FileScope, generic: Generic, argType: ArgumentType): Result[ResolvedArgumentType, string]

# ResolvedModuleArgumentType
proc newResolvedModuleArgumentType*(root: Module, impls: seq[ResolvedArgumentType], loc: Location): ResolvedModuleArgumentType =
  ResolvedModuleArgumentType(loc: loc, root: root, impls: impls)

proc newResolvedModuleArgumentType*(root: Module, loc: Location): ResolvedModuleArgumentType =
  newResolvedModuleArgumentType(root, @[], loc)

proc loc*(argType: ResolvedModuleArgumentType): Location = argType.loc
proc module*(argType: ResolvedModuleArgumentType): Module = argType.root
proc name*(argType: ResolvedModuleArgumentType): Identifier = argType.root.name
proc impls*(argType: ResolvedModuleArgumentType): seq[ResolvedArgumentType] = argType.impls
proc hash*(argType: ResolvedModuleArgumentType): Hash =
  var acc = argType.module.hash
  for impl in argType.impls:
    acc = acc !& impl.hash
  return acc
proc `==`*(a, b: ResolvedModuleArgumentType): bool = a.hash == b.hash

proc findDefinedType*(file: parser.File, fileScope: FileScope, name: Identifier): Result[DefinedType, string] =
  let fieldType = ? file.findType(name)
  case fieldType.kind:
  of tkImported:
    let importedType = fieldType.imported
    if importedType.binding notin fileScope:
      err(fmt"{importedType.loc} type `{importedType.binding.asl}` does not exist in the file scope.")
    else:
      ok(fileScope[importedType.binding])
  of tkDefined:
    ok(fieldType.definedType)

proc findModule*(file: parser.File, fileScope: FileScope, name: Identifier): Result[Module, string] =
  let initDefinedType = ? file.findDefinedType(fileScope, name)
  case initDefinedType.kind:
  of dtkGeneric: err(fmt"{name.loc} type `{name.asl}` is a generic and not a module")
  of dtkModule: ok(initDefinedType.module)

proc findRequiredImplsForFields(file: parser.File, fileScope: FileScope, fields: seq[ArgumentDefinition]): Result[seq[Generic], string] =
  var requiredImpls: seq[Generic]
  for field in fields:
    let definedFieldType = ? file.findDefinedType(fileScope, field.argType.root)
    case definedFieldType.kind:
    of dtkModule: discard
    of dtkGeneric: requiredImpls.add(definedFieldType.generic)
  ok(requiredImpls)

proc findRequiredImplsForStruct(file: parser.File, fileScope: FileScope, struct: Struct): Result[seq[Generic], string] =
  findRequiredImplsForFields(file, fileScope, struct.fields)

proc findRequiredImplsForUnion(file: parser.File, fileScope: FileScope, union: Union): Result[seq[Generic], string] =
  var requiredUnionImpls: seq[Generic]
  for variant in union.variants:
    let requiredVariantImpls = ? findRequiredImplsForFields(file, fileScope, variant.fields)
    requiredUnionImpls.add(requiredVariantImpls)
  ok(requiredUnionImpls)

# resolveModuleArgumentType — module context.
proc resolveModuleArgumentType(app: App, file: parser.File, fileScope: FileScope,
    module: Module, argType: ArgumentType,
    root: Module): Result[ResolvedModuleArgumentType, string] =
  # NOTE: requires block will override the inferred impl list
  if root.requires.isSome:
    let expectedImplCount = root.requires.get.generics.len
    if argType.impls.len != expectedImplCount:
      return err(fmt"{argType.loc} type `{root.name.asl}` expects `{expectedImplCount}` impls but found `{argType.impls.len}`")

    var resolvedImpls: seq[ResolvedArgumentType]
    for impl in argType.impls:
      let resolvedImpl = ? resolveArgumentType(app, file, fileScope, module, impl)
      resolvedImpls.add(resolvedImpl)

    return ok(newResolvedModuleArgumentType(root, resolvedImpls, argType.loc))

  # NOTE: infer the impl list from struct/union block
  if root.data.isSome:
    let dataBlock = root.data.get
    case dataBlock.kind:
    of dbkLiteral:
      if argType.impls.len == 0:
        return ok(newResolvedModuleArgumentType(root, argType.loc))
      else:
        return err(fmt"{argType.loc} type `{root.name.asl}` does not require impl types")
    of dbkStruct:
      let requires = ? file.findRequiredImplsForStruct(fileScope, dataBlock.struct)
      if argType.impls.len != requires.len:
        return err(fmt"{argType.loc} struct `{root.name.asl}` expects `{requires.len}` impls but found `{argType.impls.len}`")

      var resolvedImpls: seq[ResolvedArgumentType]
      for impl in argType.impls:
        let resolvedImpl = ? resolveArgumentType(app, file, fileScope, module, impl)
        resolvedImpls.add(resolvedImpl)

      return ok(newResolvedModuleArgumentType(root, resolvedImpls, argType.loc))

    of dbkUnion:
      let requires = ? file.findRequiredImplsForUnion(fileScope, dataBlock.union)
      if argType.impls.len != requires.len:
        return err(fmt"{argType.loc} union `{root.name.asl}` expects `{requires.len}` impls but found `{argType.impls.len}`")

      var resolvedImpls: seq[ResolvedArgumentType]
      for impl in argType.impls:
        let resolvedImpl = ? resolveArgumentType(app, file, fileScope, module, impl)
        resolvedImpls.add(resolvedImpl)

      return ok(newResolvedModuleArgumentType(root, resolvedImpls, argType.loc))

  if argType.impls.len == 0:
    ok(newResolvedModuleArgumentType(root, argType.loc))
  else:
    err(fmt"{argType.loc} type `{root.name.asl}` does not require impl types")

# resolveModuleArgumentType — generic context. Mirrors module-context
# but with the self-only rule and a still-stubbed dbkStruct path.
proc resolveModuleArgumentType(app: App, file: parser.File, fileScope: FileScope, generic: Generic,
    argType: ArgumentType,
    root: Module): Result[ResolvedModuleArgumentType, string] =
  if root.requires.isSome:
    return err("todo: resolve requires block in argument type")

  if root.data.isSome:
    let dataBlock = root.data.get
    case dataBlock.kind:
    of dbkStruct:
      return err(fmt"{dataBlock.loc} todo: resolve struct block in argument type")
    of dbkLiteral:
      if argType.impls.len == 0:
        return ok(newResolvedModuleArgumentType(root, argType.loc))
      else:
        return err(fmt"{argType.loc} type `{root.name.asl}` does not require impl types")
    of dbkUnion:
      var requires = ? findRequiredImplsForUnion(file, fileScope, dataBlock.union)
      if argType.impls.len != requires.len:
        return err(fmt"{argType.loc} type `{root.name.asl}` expects `{requires.len}` impls but found `{argType.impls.len}`")

      var resolvedImpls: seq[ResolvedArgumentType]
      for impl in argType.impls:
        let resolvedImpl = ? resolveArgumentType(app, file, fileScope, generic, impl)
        resolvedImpls.add(resolvedImpl)

      return ok(newResolvedModuleArgumentType(root, resolvedImpls, argType.loc))

  if argType.impls.len == 0:
    ok(newResolvedModuleArgumentType(root, argType.loc))
  else:
    err(fmt"{argType.loc} type `{root.name.asl}` does not require impl types")

# ResolvedDefinedArgumentType
proc newResolvedDefinedArgumentType*(
    module: ResolvedModuleArgumentType): ResolvedDefinedArgumentType =
  ResolvedDefinedArgumentType(kind: rdatkModule, module: module)

proc newResolvedDefinedArgumentType*(
    generic: ResolvedGenericArgumentType): ResolvedDefinedArgumentType =
  ResolvedDefinedArgumentType(kind: rdatkGeneric, generic: generic)

proc kind*(argType: ResolvedDefinedArgumentType): ResolvedDefinedArgumentTypeKind = argType.kind
proc module*(argType: ResolvedDefinedArgumentType): ResolvedModuleArgumentType =
  assert argType.kind == rdatkModule,
    fmt"ResolvedDefinedArgumentType.module accessed but kind is {argType.kind}"
  argType.module
proc generic*(argType: ResolvedDefinedArgumentType): ResolvedGenericArgumentType =
  assert argType.kind == rdatkGeneric,
    fmt"ResolvedDefinedArgumentType.generic accessed but kind is {argType.kind}"
  argType.generic
proc name*(argType: ResolvedDefinedArgumentType): Identifier =
  case argType.kind:
  of rdatkGeneric: argType.generic.name
  of rdatkModule: argType.module.name
proc loc*(argType: ResolvedDefinedArgumentType): Location =
  case argType.kind:
  of rdatkGeneric: argType.generic.loc
  of rdatkModule: argType.module.loc
proc hash*(argType: ResolvedDefinedArgumentType): Hash =
  case argType.kind:
  of rdatkGeneric: argType.generic.hash
  of rdatkModule: argType.module.hash
proc `==`*(a, b: ResolvedDefinedArgumentType): bool = a.hash == b.hash

proc concreteDefinedArgumentType(argType: ResolvedDefinedArgumentType, concrete: ResolvedArgumentType, generic: Generic): ResolvedDefinedArgumentType =
  case argType.kind:
  of rdatkModule: return argType
  of rdatkGeneric:
    if argType.generic.parsed != generic:
      return argType
    else:
      case concrete.kind:
      of ratkImported: assert(false, "TODO: support concrete imported impl type")
      of ratkDefined: return concrete.definedType

proc resolveGenericArgumentType(app: App, file: parser.File, generic: Generic, argType: ArgumentType, genericArgType: Generic): Result[ResolvedGenericArgumentType, string] =
  if genericArgType == generic:
    ok(newResolvedGenericArgumentType(genericArgType, argType.loc))
  else:
    err(fmt"{argType.loc} type `{genericArgType.name.asl}` is a generic and can not be used within the generic block")

proc resolveGenericArgumentType(app: App, file: parser.File, module: Module, argType: ArgumentType, genericArgType: Generic): Result[ResolvedGenericArgumentType, string] =
  if argType.impls.len == 0:
    ok(newResolvedGenericArgumentType(genericArgType, genericArgType.loc))
  else:
    err(fmt"{genericArgType.loc} generic `{genericArgType.name.asl}` is not allowed to have impls")

# resolveDefinedArgumentType — both context overloads.
proc resolveDefinedArgumentType(app: App, file: parser.File,
    fileScope: FileScope, module: Module, argType: ArgumentType,
    definedType: DefinedType): Result[ResolvedDefinedArgumentType, string] =
  case definedType.kind:
  of dtkGeneric:
    let resolvedGenericType = ? resolveGenericArgumentType(app, file, module, argType, definedType.generic)
    ok(newResolvedDefinedArgumentType(resolvedGenericType))
  of dtkModule:
    let resolvedModuleType = ? resolveModuleArgumentType(app, file, fileScope, module, argType, definedType.module)
    ok(newResolvedDefinedArgumentType(resolvedModuleType))

proc resolveDefinedArgumentType(app: App, file: parser.File, fileScope: FileScope, generic: Generic,
    argType: ArgumentType,
    definedType: DefinedType): Result[ResolvedDefinedArgumentType, string] =
  case definedType.kind:
  of dtkGeneric:
    let resolvedGenericType = ? resolveGenericArgumentType(app, file, generic, argType, definedType.generic)
    ok(newResolvedDefinedArgumentType(resolvedGenericType))
  of dtkModule:
    let resolvedModuleType = ? resolveModuleArgumentType(app, file, fileScope, generic, argType, definedType.module)
    ok(newResolvedDefinedArgumentType(resolvedModuleType))

# ResolvedArgumentType
proc newResolvedArgumentType*(definedType: ResolvedDefinedArgumentType): ResolvedArgumentType =
  ResolvedArgumentType(kind: ratkDefined, definedType: definedType)

proc kind*(argType: ResolvedArgumentType): ResolvedArgumentTypeKind = argType.kind
proc definedType*(argType: ResolvedArgumentType): ResolvedDefinedArgumentType =
  assert argType.kind == ratkDefined,
    fmt"ResolvedArgumentType.definedType accessed but kind is {argType.kind}"
  argType.definedType
proc name*(argType: ResolvedArgumentType): Identifier =
  case argType.kind:
  of ratkImported: assert(false, "todo: implement resolved imported type name")
  of ratkDefined: return argType.definedType.name
proc loc*(argType: ResolvedArgumentType): Location =
  case argType.kind:
  of ratkImported: assert(false, "todo: implement resolved imported type location")
  of ratkDefined: return argType.definedType.loc
proc hash*(argType: ResolvedArgumentType): Hash =
  case argType.kind:
  of ratkImported: assert(false, "todo: implement resolved imported type hash")
  of ratkDefined: return argType.definedType.hash
proc `==`*(a, b: ResolvedArgumentType): bool = a.hash == b.hash

proc concreteArgumentType*(argType: ResolvedArgumentType, concrete: ResolvedArgumentType, generic: Generic): ResolvedArgumentType =
  case argType.kind:
  of ratkImported:
    assert(false, "todo: concretize imported argument type")
  of ratkDefined:
    let concreteDefinedArgType = argType.definedType.concreteDefinedArgumentType(concrete, generic)
    return newResolvedArgumentType(concreteDefinedArgType)

# resolveArgumentType — both context overloads, defined now after
# the module/defined helpers.
proc resolveArgumentType*(app: App, file: parser.File, fileScope: FileScope, module: Module, argType: ArgumentType): Result[ResolvedArgumentType, string] =
  let definedType = ? file.findDefinedType(fileScope, argType.root)
  let resolvedDefinedType = ? resolveDefinedArgumentType(app, file, fileScope, module, argType, definedType)
  ok(newResolvedArgumentType(resolvedDefinedType))

proc resolveArgumentType*(app: App, file: parser.File, fileScope: FileScope, generic: Generic, argType: ArgumentType): Result[ResolvedArgumentType, string] =
  let definedType = ? file.findDefinedType(fileScope, argType.root)
  let resolvedDefinedType = ? resolveDefinedArgumentType(app, file, fileScope, generic, argType, definedType)
  ok(newResolvedArgumentType(resolvedDefinedType))

# resolveDataType — post-resolution guard. Confirms the resolved
# argument's underlying module has a data block (or that we're
# pointing at an unsubstituted generic, which is acceptable).
proc resolveDataType*(file: parser.File, module: Module, arg: ArgumentType,
    resolvedArgumentType: ResolvedArgumentType): Result[void, string] =
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

proc resolveDataType*(file: parser.File, generic: Generic, arg: ArgumentType,
    resolvedArgumentType: ResolvedArgumentType): Result[void, string] =
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
