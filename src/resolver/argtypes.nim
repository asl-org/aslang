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

import results, options, strformat, tables, hashes, strutils, sets

import tokenizer
import parser

# FileScope alias — keyed by binding (alias-or-name); shared by
# every resolver file that walks bodies.
type FileScope* = Table[Identifier, DefinedType]

# ResolvedModuleArgumentType / ResolvedGenericArgumentType /
# ResolvedArgumentType — mutually recursive cluster (an impl is
# itself a ResolvedArgumentType). Flat two-variant tagged union per
# grammar `ArgumentType: ModuleArgumentType | GenericArgumentType`
# — imported types resolve through `fileScope` and surface as
# ordinary `ratkModule`/`ratkGeneric` values just like local types,
# so there's no separate "imported" variant.
type
  ResolvedModuleArgumentType* = ref object
    root: Module
    impls: seq[ResolvedArgumentType]
    loc: Location

  ResolvedGenericArgumentType* = ref object
    generic: Generic
    loc: Location

  ResolvedArgumentTypeKind* = enum
    ratkModule, ratkGeneric

  ResolvedArgumentType* = ref object
    case kind: ResolvedArgumentTypeKind
    of ratkModule: module: ResolvedModuleArgumentType
    of ratkGeneric: generic: ResolvedGenericArgumentType

proc newResolvedGenericArgumentType*(generic: Generic, loc: Location): ResolvedGenericArgumentType =
  ResolvedGenericArgumentType(generic: generic, loc: loc)

proc parsed*(argType: ResolvedGenericArgumentType): Generic = argType.generic
proc name*(argType: ResolvedGenericArgumentType): Identifier = argType.generic.name
proc loc*(argType: ResolvedGenericArgumentType): Location = argType.loc
# TODO: hash conflicts may occur because `loc` only considers line and col in hash not file path.
proc hash*(argType: ResolvedGenericArgumentType): Hash = argType.generic.hash
proc `==`*(a, b: ResolvedGenericArgumentType): bool = a.hash == b.hash
proc asl*(argType: ResolvedGenericArgumentType): string = argType.generic.name.asl

# Forward declarations — both context overloads need to be declared
# up front because resolveModuleArgumentType recurses through them
# when resolving impls.
proc hash*(argType: ResolvedArgumentType): Hash
proc asl*(argType: ResolvedArgumentType): string

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
proc asl*(argType: ResolvedModuleArgumentType): string =
  if argType.impls.len == 0:
    fmt"{argType.module.name.asl}"
  else:
    var impls: seq[string]
    for impl in argType.impls:
      impls.add(impl.asl)
    let implsJoined = impls.join(", ")
    fmt"{argType.module.name.asl}[{implsJoined}]"

proc findDefinedType*(file: parser.File, fileScope: FileScope, name: Identifier): Result[DefinedType, string] =
  let maybeFieldType = file.findType(name)
  if maybeFieldType.isOk:
    let fieldType = maybeFieldType.get
    case fieldType.kind:
    of tkImported:
      let importedType = fieldType.imported
      if importedType.binding notin fileScope:
        err(fmt"{importedType.loc} type `{importedType.binding.asl}` does not exist in the file scope.")
      else:
        ok(fileScope[importedType.binding])
    of tkDefined:
      ok(fieldType.definedType)
  elif name in fileScope:
    # Name isn't in the parser's typeIndex (no explicit import or
    # local definition) but the resolver populated fileScope with it
    # — i.e., it came from a shorthand `import "file.asl"` expansion
    # in resolveImport.
    ok(fileScope[name])
  else:
    err(fmt"{name.loc} type `{name.asl}` does not exist in the scope")

proc findModule*(file: parser.File, fileScope: FileScope, name: Identifier): Result[Module, string] =
  let initDefinedType = ? file.findDefinedType(fileScope, name)
  case initDefinedType.kind:
  of dtkGeneric: err(fmt"{name.loc} type `{name.asl}` is a generic and not a module")
  of dtkModule: ok(initDefinedType.module)

proc findRequiredImplsForFields(file: parser.File, fileScope: FileScope, fields: seq[ArgumentDefinition]): Result[seq[Generic], string] =
  # TODO(union-inference): walk impls recursively. Today this only
  # looks at the field's top-level root, so a field typed
  # `Box[u8, Sample]` returns nothing — even though the containing
  # struct/variant should inherit `Sample` as one of its requires.
  # Under leave-as-is, polymorphic types nesting in field positions
  # is common (any field whose value came from a partial-coverage
  # union initializer carries a free generic). Walk each impl's
  # ArgumentType recursively and collect every generic referenced
  # anywhere in the tree, deduped by first-seen order.
  var requiredImpls: seq[Generic]
  for field in fields:
    let definedFieldType = ? file.findDefinedType(fileScope, field.argType.root)
    case definedFieldType.kind:
    of dtkModule: discard
    of dtkGeneric: requiredImpls.add(definedFieldType.generic)
  ok(requiredImpls)

proc findRequiredImplsForStruct(file: parser.File, fileScope: FileScope, struct: StructDef): Result[seq[Generic], string] =
  findRequiredImplsForFields(file, fileScope, struct.fields)

proc findRequiredImplsForUnion(file: parser.File, fileScope: FileScope, union: UnionDef): Result[seq[Generic], string] =
  # Rust-style: a generic name shared across variants is one shared
  # type parameter, deduped by first-seen order across variants.
  var seen: HashSet[Generic]
  var requiredUnionImpls: seq[Generic]
  for variant in union.variants:
    let requiredVariantImpls = ? findRequiredImplsForFields(file, fileScope, variant.fields)
    for generic in requiredVariantImpls:
      if generic notin seen:
        seen.incl(generic)
        requiredUnionImpls.add(generic)
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

# ResolvedArgumentType
proc newResolvedArgumentType*(module: ResolvedModuleArgumentType): ResolvedArgumentType =
  ResolvedArgumentType(kind: ratkModule, module: module)

proc newResolvedArgumentType*(generic: ResolvedGenericArgumentType): ResolvedArgumentType =
  ResolvedArgumentType(kind: ratkGeneric, generic: generic)

proc kind*(argType: ResolvedArgumentType): ResolvedArgumentTypeKind = argType.kind

proc module*(argType: ResolvedArgumentType): ResolvedModuleArgumentType =
  assert argType.kind == ratkModule,
    fmt"ResolvedArgumentType.module accessed but kind is {argType.kind}"
  argType.module

proc generic*(argType: ResolvedArgumentType): ResolvedGenericArgumentType =
  assert argType.kind == ratkGeneric,
    fmt"ResolvedArgumentType.generic accessed but kind is {argType.kind}"
  argType.generic

proc name*(argType: ResolvedArgumentType): Identifier =
  case argType.kind:
  of ratkModule: argType.module.name
  of ratkGeneric: argType.generic.name

proc loc*(argType: ResolvedArgumentType): Location =
  case argType.kind:
  of ratkModule: argType.module.loc
  of ratkGeneric: argType.generic.loc

proc hash*(argType: ResolvedArgumentType): Hash =
  case argType.kind:
  of ratkModule: argType.module.hash
  of ratkGeneric: argType.generic.hash

proc `==`*(a, b: ResolvedArgumentType): bool = a.hash == b.hash

proc asl*(argType: ResolvedArgumentType): string =
  case argType.kind:
  of ratkModule: argType.module.asl
  of ratkGeneric: argType.generic.asl

proc concreteArgumentType*(argType: ResolvedArgumentType, concrete: ResolvedArgumentType, generic: Generic): ResolvedArgumentType =
  case argType.kind:
  of ratkModule: argType
  of ratkGeneric:
    if argType.generic.parsed != generic:
      argType
    else:
      concrete

# resolveArgumentType — both context overloads, defined now after
# the module/generic helpers.
proc resolveArgumentType*(app: App, file: parser.File, fileScope: FileScope, module: Module, argType: ArgumentType): Result[ResolvedArgumentType, string] =
  let definedType = ? file.findDefinedType(fileScope, argType.root)
  case definedType.kind:
  of dtkGeneric:
    let resolvedGenericType = ? resolveGenericArgumentType(app, file, module, argType, definedType.generic)
    ok(newResolvedArgumentType(resolvedGenericType))
  of dtkModule:
    let resolvedModuleType = ? resolveModuleArgumentType(app, file, fileScope, module, argType, definedType.module)
    ok(newResolvedArgumentType(resolvedModuleType))

proc resolveArgumentType*(app: App, file: parser.File, fileScope: FileScope, generic: Generic, argType: ArgumentType): Result[ResolvedArgumentType, string] =
  let definedType = ? file.findDefinedType(fileScope, argType.root)
  case definedType.kind:
  of dtkGeneric:
    let resolvedGenericType = ? resolveGenericArgumentType(app, file, generic, argType, definedType.generic)
    ok(newResolvedArgumentType(resolvedGenericType))
  of dtkModule:
    let resolvedModuleType = ? resolveModuleArgumentType(app, file, fileScope, generic, argType, definedType.module)
    ok(newResolvedArgumentType(resolvedModuleType))

# resolveDataType — post-resolution guard. Confirms the resolved
# argument's underlying module has a data block (or that we're
# pointing at an unsubstituted generic, which is acceptable).
proc resolveDataType*(file: parser.File, module: Module, arg: ArgumentType,
    resolvedArgumentType: ResolvedArgumentType): Result[void, string] =
  case resolvedArgumentType.kind:
  of ratkGeneric:
    ok()
  of ratkModule:
    let resolvedModuleType = resolvedArgumentType.module
    if resolvedModuleType.root.data.isSome:
      ok()
    else:
      err(fmt"{arg.loc} module `{resolvedModuleType.root.name.asl}` is not a literal/struct/union")

proc resolveDataType*(file: parser.File, generic: Generic, arg: ArgumentType,
    resolvedArgumentType: ResolvedArgumentType): Result[void, string] =
  case resolvedArgumentType.kind:
  of ratkGeneric:
    ok()
  of ratkModule:
    let resolvedModuleType = resolvedArgumentType.module
    if resolvedModuleType.root.data.isSome:
      ok()
    else:
      err(fmt"{arg.loc} module `{resolvedModuleType.root.name.asl}` is not a literal/struct/union")
