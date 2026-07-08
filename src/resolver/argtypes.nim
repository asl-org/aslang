## Argument-type cluster — the mutually-recursive `ArgumentType` shape
## and the file-scope lookups + argument-type resolve procs that walk
## it. First layer in the resolver's dependency chain: nothing else
## in the resolver imports back into this file.

import results, strformat, strutils, options, tables, hashes, sets, sequtils

import parser

type FileScope* = Table[Identifier, Type]
  ## Populated by resolver/imports.nim (imported-name → imported Type)
  ## and passed to every scope-consuming resolve* proc downstream.
type FunctionScope* = HashSet[Identifier]
  ## Set of variables in scope at a body-level site.

type
  ResolvedModuleArgumentType* = ref object
    module: Module
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

# ---- forward declarations (case-union recursion) ----

proc hash*(argType: ResolvedArgumentType): Hash
proc asl*(argType: ResolvedArgumentType): string

# resolveArgumentType (both context overloads) is called by the
# module-context resolveModuleArgumentType helper for impls.
proc resolveArgumentType*(app: App,     file: parser.File, fileScope: FileScope, module: Module,
    argType: ArgumentType): Result[ResolvedArgumentType, string]

proc resolveArgumentType*(app: App,     file: parser.File, fileScope: FileScope, generic: Generic,
    argType: ArgumentType): Result[ResolvedArgumentType, string]

# =====================================================================

# ---- ResolvedGenericArgumentType ----

proc newResolvedGenericArgumentType*(generic: Generic, loc: Location): ResolvedGenericArgumentType =
  ResolvedGenericArgumentType(generic: generic, loc: loc)

proc parsed*(argType: ResolvedGenericArgumentType): Generic = argType.generic
proc name*(argType: ResolvedGenericArgumentType): Identifier = argType.generic.name
proc loc*(argType: ResolvedGenericArgumentType): Location = argType.loc
proc hash*(argType: ResolvedGenericArgumentType): Hash = argType.generic.hash
proc `==`*(a, b: ResolvedGenericArgumentType): bool = a.hash == b.hash
proc asl*(argType: ResolvedGenericArgumentType): string = argType.generic.name.asl

# ---- ResolvedModuleArgumentType ----

proc newResolvedModuleArgumentType*(module: Module, impls: seq[ResolvedArgumentType], loc: Location): ResolvedModuleArgumentType =
  ResolvedModuleArgumentType(loc: loc, module: module, impls: impls)

proc newResolvedModuleArgumentType*(module: Module, loc: Location): ResolvedModuleArgumentType =
  newResolvedModuleArgumentType(module, @[], loc)

proc loc*(argType: ResolvedModuleArgumentType): Location = argType.loc
proc module*(argType: ResolvedModuleArgumentType): Module = argType.module
proc impls*(argType: ResolvedModuleArgumentType): seq[ResolvedArgumentType] = argType.impls
proc parsed*(argType: ResolvedModuleArgumentType): Module = argType.module
  ## The parser Module that this argument type refers to. Consumers who
  ## need the ResolvedModule look it up at their site via
  ## `ResolvedFile.findModule(module.name)`.
proc name*(argType: ResolvedModuleArgumentType): Identifier = argType.module.name

proc hash*(argType: ResolvedModuleArgumentType): Hash =
  # Hash by parser Module identity.
  var acc = argType.module.hash
  for impl in argType.impls:
    acc = acc !& impl.hash
  return acc
proc `==`*(a, b: ResolvedModuleArgumentType): bool = a.hash == b.hash

proc asl*(argType: ResolvedModuleArgumentType): string =
  if argType.impls.len == 0:
    fmt"{argType.parsed.name.asl}"
  else:
    var impls: seq[string]
    for impl in argType.impls:
      impls.add(impl.asl)
    let implsJoined = impls.join(", ")
    fmt"{argType.parsed.name.asl}[{implsJoined}]"

# ---- ResolvedArgumentType (outer tagged union) ----

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
  of ratkModule: argType.module.parsed.name
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

# ---- Scope lookups ----

proc findType*(file: parser.File, fileScope: FileScope, name: Identifier): Result[Type, string] =
  let maybeLocal = file.findType(name)
  if maybeLocal.isOk: return maybeLocal
  let maybeImported = file.findImportedName(name)
  if maybeImported.isOk:
    let importedType = maybeImported.get
    if importedType.binding notin fileScope:
      return err(fmt"{importedType.loc} type `{importedType.binding.asl}` does not exist in the file scope.")
    return ok(fileScope[importedType.binding])
  # Name isn't in the parser's local-def or imported-name indexes
  # but the resolver may have populated fileScope with it via a
  # shorthand `import "file.asl"` expansion in resolveImport.
  if name in fileScope: ok(fileScope[name])
  else: err(fmt"{name.loc} type `{name.asl}` does not exist in the scope")

proc findModule*(file: parser.File, fileScope: FileScope, name: Identifier): Result[Module, string] =
  let initType = ? file.findType(fileScope, name)
  case initType.kind:
  of tkGeneric: err(fmt"{name.loc} type `{name.asl}` is a generic and not a module")
  of tkModule: ok(initType.module)

proc findRequiredImplsForFields(file: parser.File, fileScope: FileScope, fields: seq[ArgumentDef]): Result[seq[Generic], string] =
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
    let definedFieldType = ? file.findType(fileScope, field.argType.root)
    case definedFieldType.kind:
    of tkModule: discard
    of tkGeneric: requiredImpls.add(definedFieldType.generic)
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

# ---- resolveArgumentType internals ----

# Constraint-satisfaction check: does `resolvedImpl` provide every
# funcDef the required generic `base` mandates? Retired the analyzer's
# equivalent def-time check and moved it here so
# ResolvedModuleArgumentType.impls is a provably valid value by the
# time it leaves the resolver.
#
# Semantics drift vs the retired analyzer check: verification is by
# (name, arity) at the parser level, not by concretized-signature
# hash. Signature-parity (e.g. impl provides `byte_size(items: u16)`
# where the base generic mandates `byte_size(items: u32)`) is left to
# the analyzer's value-vs-defType walk at use sites
# (analyzer/body.nim's `analyzeValueTypeAgainstDefType`), which
# already runs the strict hash-based check every time a value is
# type-checked against a definition. The def-time check here catches
# the "impl is missing the method entirely" case — the common
# regression path — using the parser-level `findFunctionDefs` API
# directly, no resolver-side lookup needed.
proc checkImplSatisfiesGeneric(resolvedImpl: ResolvedArgumentType, base: Generic): Result[void, string] =
  case resolvedImpl.kind:
  of ratkModule:
    let implModule = resolvedImpl.module.module
    for funcDef in base.funcDefs:
      let maybeFuncDefs = implModule.findFunctionDefs(funcDef.name, funcDef.arity)
      if maybeFuncDefs.isErr:
        return err(fmt"{resolvedImpl.module.loc} module `{implModule.name.asl}` does not implement function `{funcDef.name.asl}` to support `{base.name.asl}`")
  of ratkGeneric:
    let implGeneric = resolvedImpl.generic.parsed
    for funcDef in base.funcDefs:
      let maybeFuncDefs = implGeneric.findFunctionDefs(funcDef.name, funcDef.arity)
      if maybeFuncDefs.isErr:
        return err(fmt"{resolvedImpl.generic.loc} generic `{implGeneric.name.asl}` does not implement function `{funcDef.name.asl}` to support `{base.name.asl}`")
  ok()

proc findGeneric*(file: parser.File, fileScope: FileScope, name: Identifier): Result[Generic, string] =
  ## Parser-level generic lookup — mirror of `findModule` for the
  ## constraint-check helper. Used by resolveModuleArgumentType's
  ## explicit-requires path to translate each `requires(...)` name into
  ## its parser Generic so the check can walk its funcDefs.
  let initType = ? file.findType(fileScope, name)
  case initType.kind:
  of tkModule: err(fmt"{name.loc} type `{name.asl}` is a module but expected generic")
  of tkGeneric: ok(initType.generic)

# resolveModuleArgumentType — module context.
proc resolveModuleArgumentType(app: App, file: parser.File, fileScope: FileScope,
    module: Module, argType: ArgumentType,
    root: Module): Result[ResolvedModuleArgumentType, string] =
    # NOTE: requires block will override the inferred impl list
  if root.requires.isSome:
    let requiredNames = root.requires.get.generics
    if argType.impls.len != requiredNames.len:
      return err(fmt"{argType.loc} type `{root.name.asl}` expects `{requiredNames.len}` impls but found `{argType.impls.len}`")

    var impls: seq[ResolvedArgumentType]
    for (requiredName, impl) in zip(requiredNames, argType.impls):
      let requiredGeneric = ? file.findGeneric(fileScope, requiredName)
      let resolvedImpl = ? resolveArgumentType(app, file, fileScope, module, impl)
      ? checkImplSatisfiesGeneric(resolvedImpl, requiredGeneric)
      impls.add(resolvedImpl)

    return ok(newResolvedModuleArgumentType(root, impls, argType.loc))

  # NOTE: infer the impl list from struct/union block
  if root.data.isSome:
    let dataDef = root.data.get
    case dataDef.kind:
    of ddkLiteral:
      if argType.impls.len == 0:
        return ok(newResolvedModuleArgumentType(root, argType.loc))
      else:
        return err(fmt"{argType.loc} type `{root.name.asl}` does not require impl types")
    of ddkStruct:
      let requires = ? file.findRequiredImplsForStruct(fileScope, dataDef.struct)
      if argType.impls.len != requires.len:
        return err(fmt"{argType.loc} struct `{root.name.asl}` expects `{requires.len}` impls but found `{argType.impls.len}`")

      var impls: seq[ResolvedArgumentType]
      for (requiredGeneric, impl) in zip(requires, argType.impls):
        let resolvedImpl = ? resolveArgumentType(app, file, fileScope, module, impl)
        ? checkImplSatisfiesGeneric(resolvedImpl, requiredGeneric)
        impls.add(resolvedImpl)

      return ok(newResolvedModuleArgumentType(root, impls, argType.loc))

    of ddkUnion:
      let requires = ? file.findRequiredImplsForUnion(fileScope, dataDef.union)
      if argType.impls.len != requires.len:
        return err(fmt"{argType.loc} union `{root.name.asl}` expects `{requires.len}` impls but found `{argType.impls.len}`")

      var impls: seq[ResolvedArgumentType]
      for (requiredGeneric, impl) in zip(requires, argType.impls):
        let resolvedImpl = ? resolveArgumentType(app, file, fileScope, module, impl)
        ? checkImplSatisfiesGeneric(resolvedImpl, requiredGeneric)
        impls.add(resolvedImpl)

      return ok(newResolvedModuleArgumentType(root, impls, argType.loc))

  if argType.impls.len == 0:
    ok(newResolvedModuleArgumentType(root, argType.loc))
  else:
    err(fmt"{argType.loc} type `{root.name.asl}` does not require impl types")

# resolveModuleArgumentType — generic context. Mirrors module-context
# but with the self-only rule and a still-stubbed ddkStruct path.
proc resolveModuleArgumentType(app: App, file: parser.File, fileScope: FileScope, generic: Generic,
    argType: ArgumentType,
    root: Module): Result[ResolvedModuleArgumentType, string] =
  if root.requires.isSome:
    return err("todo: resolve requires block in argument type")

  if root.data.isSome:
    let dataDef = root.data.get
    case dataDef.kind:
    of ddkStruct:
      return err(fmt"{dataDef.loc} todo: resolve struct block in argument type")
    of ddkLiteral:
      if argType.impls.len == 0:
        return ok(newResolvedModuleArgumentType(root, argType.loc))
      else:
        return err(fmt"{argType.loc} type `{root.name.asl}` does not require impl types")
    of ddkUnion:
      var requires = ? findRequiredImplsForUnion(file, fileScope, dataDef.union)
      if argType.impls.len != requires.len:
        return err(fmt"{argType.loc} type `{root.name.asl}` expects `{requires.len}` impls but found `{argType.impls.len}`")

      var impls: seq[ResolvedArgumentType]
      for (requiredGeneric, impl) in zip(requires, argType.impls):
        let resolvedImpl = ? resolveArgumentType(app, file, fileScope, generic, impl)
        ? checkImplSatisfiesGeneric(resolvedImpl, requiredGeneric)
        impls.add(resolvedImpl)

      return ok(newResolvedModuleArgumentType(root, impls, argType.loc))

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

# resolveArgumentType — both context overloads.
proc resolveArgumentType*(app: App,     file: parser.File, fileScope: FileScope, module: Module,
    argType: ArgumentType): Result[ResolvedArgumentType, string] =
  let definedType = ? file.findType(fileScope, argType.root)
  case definedType.kind:
  of tkGeneric:
    let resolvedGenericType = ? resolveGenericArgumentType(app, file, module, argType, definedType.generic)
    ok(newResolvedArgumentType(resolvedGenericType))
  of tkModule:
    let resolvedModuleType = ? resolveModuleArgumentType(app, file, fileScope, module, argType, definedType.module)
    ok(newResolvedArgumentType(resolvedModuleType))

proc resolveArgumentType*(app: App,     file: parser.File, fileScope: FileScope, generic: Generic,
    argType: ArgumentType): Result[ResolvedArgumentType, string] =
  let definedType = ? file.findType(fileScope, argType.root)
  case definedType.kind:
  of tkGeneric:
    let resolvedGenericType = ? resolveGenericArgumentType(app, file, generic, argType, definedType.generic)
    ok(newResolvedArgumentType(resolvedGenericType))
  of tkModule:
    let resolvedModuleType = ? resolveModuleArgumentType(app, file, fileScope, generic, argType, definedType.module)
    ok(newResolvedArgumentType(resolvedModuleType))

# resolveDataType — post-resolution guard. Confirms the resolved
# argument's underlying module has a data block (or that we're
# pointing at an unsubstituted generic, which is acceptable).
# Reads through the parser Module — set at parse time and always
# available.
proc resolveDataType*(file: parser.File, module: Module, arg: ArgumentType,
    resolvedArgumentType: ResolvedArgumentType): Result[void, string] =
  case resolvedArgumentType.kind:
  of ratkGeneric:
    ok()
  of ratkModule:
    let parsedModule = resolvedArgumentType.module.parsed
    if parsedModule.data.isSome:
      ok()
    else:
      err(fmt"{arg.loc} module `{parsedModule.name.asl}` is not a literal/struct/union")

proc resolveDataType*(file: parser.File, generic: Generic, arg: ArgumentType,
    resolvedArgumentType: ResolvedArgumentType): Result[void, string] =
  case resolvedArgumentType.kind:
  of ratkGeneric:
    ok()
  of ratkModule:
    let parsedModule = resolvedArgumentType.module.parsed
    if parsedModule.data.isSome:
      ok()
    else:
      err(fmt"{arg.loc} module `{parsedModule.name.asl}` is not a literal/struct/union")

