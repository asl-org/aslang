import results, sequtils, strformat, sets, tables, options

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

# ---- Scope lookups ----

proc findType*(file: parser.File, fileScope: FileScope, name: Identifier): Result[Type, string] =
  let maybeLocal = file.findType(name)
  if maybeLocal.isOk: maybeLocal
  else:
    if name in fileScope: ok(fileScope[name])
    else: err(fmt"{name.loc} type `{name.asl}` does not exist in the scope")

proc findGeneric*(file: parser.File, fileScope: FileScope, name: Identifier): Result[Generic, string] =
  let initType = ? file.findType(fileScope, name)
  case initType.kind:
  of tkModule: err(fmt"{name.loc} type `{name.asl}` is a module but expected generic")
  of tkGeneric: ok(initType.generic)

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
  if struct.requires.len > 0:
    var requiredImpls: seq[Generic]
    for generic in struct.requires:
      let foundGeneric = ? file.findGeneric(fileScope, generic)
      requiredImpls.add(foundGeneric)
    ok(requiredImpls)
  else:
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

proc findRequiredImplsForData(file: parser.File, fileScope: FileScope, dataDef: DataDef): Result[seq[Generic], string] =
  case dataDef.kind:
  of ddkLiteral: ok(newSeq[Generic]())
  of ddkStruct: file.findRequiredImplsForStruct(fileScope, dataDef.struct)
  of ddkUnion: file.findRequiredImplsForUnion(fileScope, dataDef.union)

# resolveArgumentType (both context overloads) is called by the
# module-context resolveModuleArgumentType helper for impls.
proc resolveArgumentType*(app: App,     file: parser.File, fileScope: FileScope, module: Module,
    argType: ArgumentType): Result[ResolvedArgumentType, string]

proc resolveArgumentType*(app: App,     file: parser.File, fileScope: FileScope, generic: Generic,
    argType: ArgumentType): Result[ResolvedArgumentType, string]

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
proc checkImplSatisfiesGeneric(impl: ResolvedArgumentType, base: Generic): Result[void, string] =
  case impl.kind:
  of ratkModule:
    let implModule = impl.module.module
    for funcDef in base.funcDefs:
      let maybeFuncDefs = implModule.findFunctionDefs(funcDef.name, funcDef.arity)
      if maybeFuncDefs.isErr:
        return err(fmt"{impl.module.loc} module `{implModule.name.asl}` does not implement function `{funcDef.name.asl}` to support `{base.name.asl}`")
  of ratkGeneric:
    let implGeneric = impl.generic.parsed
    for funcDef in base.funcDefs:
      let maybeFuncDefs = implGeneric.findFunctionDefs(funcDef.name, funcDef.arity)
      if maybeFuncDefs.isErr:
        return err(fmt"{impl.generic.loc} generic `{implGeneric.name.asl}` does not implement function `{funcDef.name.asl}` to support `{base.name.asl}`")
  ok()

proc resolveArgumentTypeImpls(app: App, file: parser.File, fileScope: FileScope, module: Module, argType: ArgumentType, root: Module, requires: seq[Generic]): Result[ResolvedModuleArgumentType, string] =
  var impls: seq[ResolvedArgumentType]
  for (requiredGeneric, impl) in zip(requires, argType.impls):
    let resolvedImpl = ? resolveArgumentType(app, file, fileScope, module, impl)
    ? checkImplSatisfiesGeneric(resolvedImpl, requiredGeneric)
    impls.add(resolvedImpl)
  ok(newResolvedModuleArgumentType(root, impls, argType.loc))

proc resolveArgumentTypeImpls(app: App, file: parser.File, fileScope: FileScope, generic: Generic, argType: ArgumentType, root: Module, requires: seq[Generic]): Result[ResolvedModuleArgumentType, string] =
  var impls: seq[ResolvedArgumentType]
  for (requiredGeneric, impl) in zip(requires, argType.impls):
    let resolvedImpl = ? resolveArgumentType(app, file, fileScope, generic, impl)
    ? checkImplSatisfiesGeneric(resolvedImpl, requiredGeneric)
    impls.add(resolvedImpl)
  ok(newResolvedModuleArgumentType(root, impls, argType.loc))

proc resolveDataModuleArgumentType(app: App, file: parser.File, fileScope: FileScope, module: Module, argType: ArgumentType, root: Module, dataDef: DataDef): Result[ResolvedModuleArgumentType, string] =
  let requires = ? file.findRequiredImplsForData(fileScope, dataDef)
  if argType.impls.len != requires.len:
    err(fmt"{argType.loc} type `{root.name.asl}` expects {requires.len} impls but found {argType.impls.len}")
  else:
    resolveArgumentTypeImpls(app, file, fileScope, module, argType, root, requires)

proc resolveDataModuleArgumentType(app: App, file: parser.File, fileScope: FileScope, generic: Generic, argType: ArgumentType, root: Module, dataDef: DataDef): Result[ResolvedModuleArgumentType, string] =
  let requires = ? file.findRequiredImplsForData(fileScope, dataDef)
  if argType.impls.len != requires.len:
    err(fmt"{argType.loc} type `{root.name.asl}` expects {requires.len} impls but found {argType.impls.len}")
  else:
    resolveArgumentTypeImpls(app, file, fileScope, generic, argType, root, requires)

# resolveModuleArgumentType — module context.
proc resolveModuleArgumentType(app: App, file: parser.File, fileScope: FileScope, module: Module, argType: ArgumentType, root: Module): Result[ResolvedModuleArgumentType, string] =
  # NOTE: infer the impl list from struct/union block
  if root.data.isSome:
    resolveDataModuleArgumentType(app, file, fileScope, module, argType, root, root.data.get)
  else:
    if argType.impls.len == 0:
      ok(newResolvedModuleArgumentType(root, argType.loc))
    else:
      err(fmt"{argType.loc} type `{root.name.asl}` does not require impl types")

# resolveModuleArgumentType — generic context. Mirrors module-context
# but with the self-only rule and a still-stubbed ddkStruct path.
proc resolveModuleArgumentType(app: App, file: parser.File, fileScope: FileScope, generic: Generic, argType: ArgumentType, root: Module): Result[ResolvedModuleArgumentType, string] =
  if root.data.isSome:
    resolveDataModuleArgumentType(app, file, fileScope, generic, argType, root, root.data.get)
  else:
    if argType.impls.len == 0:
      ok(newResolvedModuleArgumentType(root, argType.loc))
    else:
      err(fmt"{argType.loc} type `{root.name.asl}` does not require impl types")

proc resolveGenericArgumentType(app: App, file: parser.File, generic: Generic, argType: ArgumentType, genericArgType: Generic): Result[ResolvedGenericArgumentType, string] =
  if argType.impls.len == 0:
    if genericArgType == generic:
      ok(newResolvedGenericArgumentType(genericArgType, argType.loc))
    else:
      err(fmt"{argType.loc} type `{genericArgType.name.asl}` is a generic and can not be used within the generic block")
  else:
    err(fmt"{argType.loc} type `{genericArgType.name.asl}` is a generic and does not support further impls")

proc resolveGenericArgumentType(app: App, file: parser.File, module: Module, argType: ArgumentType, genericArgType: Generic): Result[ResolvedGenericArgumentType, string] =
  if argType.impls.len == 0:
    ok(newResolvedGenericArgumentType(genericArgType, genericArgType.loc))
  else:
    err(fmt"{genericArgType.loc} generic `{genericArgType.name.asl}` is not allowed to have impls")

# resolveArgumentType — both context overloads.
proc resolveArgumentType*(app: App, file: parser.File, fileScope: FileScope, module: Module,
    argType: ArgumentType): Result[ResolvedArgumentType, string] =
  let typ = ? file.findType(fileScope, argType.root)
  case typ.kind:
  of tkGeneric:
    let resolvedGenericType = ? resolveGenericArgumentType(app, file, module, argType, typ.generic)
    ok(newResolvedArgumentType(resolvedGenericType))
  of tkModule:
    let resolvedModuleType = ? resolveModuleArgumentType(app, file, fileScope, module, argType, typ.module)
    ok(newResolvedArgumentType(resolvedModuleType))

proc resolveArgumentType*(app: App, file: parser.File, fileScope: FileScope, generic: Generic, argType: ArgumentType): Result[ResolvedArgumentType, string] =
  let typ = ? file.findType(fileScope, argType.root)
  case typ.kind:
  of tkGeneric:
    let resolvedGenericType = ? resolveGenericArgumentType(app, file, generic, argType, typ.generic)
    ok(newResolvedArgumentType(resolvedGenericType))
  of tkModule:
    let resolvedModuleType = ? resolveModuleArgumentType(app, file, fileScope, generic, argType, typ.module)
    ok(newResolvedArgumentType(resolvedModuleType))

# resolveDataType — post-resolution guard. Confirms the resolved
# argument's underlying module has a data block (or that we're
# pointing at an unsubstituted generic, which is acceptable).
# Reads through the parser Module — set at parse time and always
# available.
proc resolveDataType*(argType: ArgumentType, resolvedArgType: ResolvedArgumentType): Result[void, string] =
  case resolvedArgType.kind:
  of ratkGeneric: ok()
  of ratkModule:
    let parsedModule = resolvedArgType.module.parsed
    if parsedModule.data.isSome: ok()
    else: err(fmt"{argType.loc} module `{parsedModule.name.asl}` is not a literal/struct/union")

proc resolveArgumentDef*(app: App, file: parser.File, fileScope: FileScope, module: Module, argDef: ArgumentDef): Result[ResolvedArgumentDef, string] =
  let resolvedArgumentType = ? resolveArgumentType(app, file, fileScope, module, argDef.argType)
  ? resolveDataType(argDef.argType, resolvedArgumentType)
  ok(newResolvedArgumentDef(argDef, resolvedArgumentType))

proc resolveArgumentDef*(app: App, file: parser.File, fileScope: FileScope, generic: Generic, argDef: ArgumentDef): Result[ResolvedArgumentDef, string] =
  let resolvedArgumentType = ? resolveArgumentType(app, file, fileScope, generic, argDef.argType)
  ? resolveDataType(argDef.argType, resolvedArgumentType)
  ok(newResolvedArgumentDef(argDef, resolvedArgumentType))

proc resolveLiteralDef*(file: parser.File, literal: LiteralDef): Result[ResolvedLiteralDef, string] =
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

proc resolveStructDef*(app: App, file: parser.File, fileScope: FileScope, module: Module, struct: StructDef): Result[ResolvedStructDef, string] =
  var resolvedFields: seq[ResolvedArgumentDef]
  var genericTypeIndex: Table[ResolvedGenericArgumentType, int]
  for field in struct.fields:
    let resolvedField = ? resolveArgumentDef(app, file, fileScope, module, field)
    genericTypeIndex.accumulateGenericPosition(resolvedField)
    resolvedFields.add(resolvedField)

  if struct.requires.len > 0 and genericTypeIndex.len > 0:
    return err(fmt"{struct.loc} struct with explicit generic requirements does not support generic fields")

  var resolvedRequires: seq[ResolvedGenericArgumentType]
  for index, generic in struct.requires:
    let typ = ? file.findType(fileScope, generic)
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
proc resolveVariant(app: App, file: parser.File, fileScope: FileScope, module: Module, variant: VariantDef, genericTypeIndex: var Table[ResolvedGenericArgumentType, int]): Result[ResolvedVariant, string] =
  var resolvedFields: seq[ResolvedArgumentDef]
  for field in variant.fields:
    let resolvedField = ? resolveArgumentDef(app, file, fileScope, module, field)
    genericTypeIndex.accumulateGenericPosition(resolvedField)
    resolvedFields.add(resolvedField)
  ok(newResolvedVariant(variant, resolvedFields))

proc resolveUnionDef*(app: App, file: parser.File, fileScope: FileScope,
    module: Module, union: UnionDef): Result[ResolvedUnionDef, string] =
  var resolvedVariants: seq[ResolvedVariant]
  var genericTypeIndex: Table[ResolvedGenericArgumentType, int]
  for variant in union.variants:
    let resolvedVariant = ? resolveVariant(app, file, fileScope, module, variant, genericTypeIndex)
    resolvedVariants.add(resolvedVariant)
  ok(newResolvedUnionDef(union, resolvedVariants, genericTypeIndex))

proc resolveDataDef*(app: App, file: parser.File,
    fileScope: FileScope, module: Module, data: DataDef): Result[ResolvedData, string] =
  case data.kind:
  of ddkLiteral:
    let resolvedLiteralType = ? resolveLiteralDef(file, data.literal)
    ok(newResolvedData(resolvedLiteralType))
  of ddkStruct:
    let resolvedStruct = ? resolveStructDef(app, file, fileScope, module,
      data.struct)
    ok(newResolvedData(resolvedStruct))
  of ddkUnion:
    let resolvedUnion = ? resolveUnionDef(app, file, fileScope, module, data.union)
    ok(newResolvedData(resolvedUnion))

proc resolveFunctionDef*(app: App,     file: parser.File, fileScope: FileScope, module: Module, def: FunctionDef): Result[ResolvedFunctionDef, string] =
  var resolvedArgDefs: seq[ResolvedArgumentDef]
  for argDef in def.args:
    let resolvedArgDef = ? resolveArgumentDef(app, file, fileScope, module, argDef)
    resolvedArgDefs.add(resolvedArgDef)

  let resolvedReturnType = ? resolveArgumentType(app, file, fileScope, module, def.returns)
  ? resolveDataType(def.returns, resolvedReturnType)

  ok(newResolvedFunctionDef(def, resolvedArgDefs, resolvedReturnType))

proc resolveFunctionDef*(app: App, file: parser.File, fileScope: FileScope, generic: Generic, def: FunctionDef): Result[ResolvedFunctionDef, string] =
  var resolvedArgDefs: seq[ResolvedArgumentDef]
  for argDef in def.args:
    let resolvedArgDef = ? resolveArgumentDef(app, file, fileScope, generic, argDef)
    resolvedArgDefs.add(resolvedArgDef)

  let resolvedReturnType = ? resolveArgumentType(app, file, fileScope, generic, def.returns)
  ? resolveDataType(def.returns, resolvedReturnType)

  ok(newResolvedFunctionDef(def, resolvedArgDefs, resolvedReturnType))

proc resolveExternFunction*(app: App,     file: parser.File, fileScope: FileScope, module: Module,
    function: ExternFunction): Result[ResolvedExternFunction, string] =
  let resolvedFunctionDef = ? resolveFunctionDef(app, file, fileScope,
    module, function.def)
  ok(newResolvedExternFunction(function, resolvedFunctionDef))

proc resolveVariable*(file: parser.File, scope: FunctionScope,
    variable: Identifier): Result[Identifier, string] =
  if variable notin scope:
    err(fmt"{variable.loc} variable `{variable.asl}` is not present in scope")
  else:
    ok(variable)

proc resolveGetter*(file: parser.File, scope: FunctionScope,
    getter: Getter): Result[ResolvedGetter, string] =
  discard ? resolveVariable(file, scope, getter.source)
  ok(newResolvedGetter(getter))

proc resolveLiteralInitializer(app: App, file: parser.File, fileScope: FileScope, module: Module,
    literalInit: LiteralInitializer): Result[
        ResolvedLiteralInitializer, string] =
  let resolvedArgType = ? resolveArgumentType(app, file, fileScope, module,
    literalInit.argType)
  ok(newResolvedLiteralInitializer(literalInit, resolvedArgType))

# resolveExpression / resolveStatement form the body-cluster cycle.
proc resolveExpression*(app: App, file: parser.File, fileScope: FileScope,
    module: Module, scope: FunctionScope,
    expression: Expression): Result[ResolvedExpression, string]

proc resolveStatement*(app: App, file: parser.File, fileScope: FileScope,
    module: Module, scope: FunctionScope,
    statement: Statement): Result[ResolvedStatement, string]

proc resolveFunctionCall(app: App, file: parser.File, fileScope: FileScope,
    module: Module, scope: FunctionScope,
    fncall: FunctionCall): Result[ResolvedFunctionCall, string] =
  let typ = ? file.findType(fileScope, fncall.root)
  let funcDefs = ? typ.findFunctionDefs(fncall.name, fncall.args.len)
  if funcDefs.len == 0:
    err(fmt"{fncall.loc} generic `{typ.generic.name.asl}` does not have any function named `{fncall.name.asl}` with arity `{fncall.args.len}`")
  else:
    var resolvedArgs: seq[ResolvedExpression]
    for arg in fncall.args:
      let resolvedArg = ? resolveExpression(app, file, fileScope, module, scope, arg)
      resolvedArgs.add(resolvedArg)
    ok(newResolvedFunctionCall(fncall, resolvedArgs))

proc resolveStructRef(app: App, file: parser.File, fileScope: FileScope, module: Module,
    structRef: StructRef): Result[ResolvedStructRef, string] =
  ## Resolves a StructRef into the one-shape (module + impls).
  ## Validates the "receiver-declares-requires ↔ impls-provided" match
  ## and delegates to resolveModuleArgumentType so the impls
  ## seq is arity- and constraint-checked at resolve time.
  let structModule = ? file.findModule(fileScope, structRef.module)
  if structModule.data.isNone:
    return err(fmt"{structRef.loc} module `{structModule.name.asl}` does not define a data block")
  let moduleData = structModule.data.get
  case moduleData.kind:
  of ddkLiteral:
    err(fmt"{structRef.loc} module `{structModule.name.asl}` is a literal type")
  of ddkUnion:
    err(fmt"{structRef.loc} module `{structModule.name.asl}` is a union type")
  of ddkStruct:
    let resolvedModuleArgType = ? resolveModuleArgumentType(app, file, fileScope, module, structRef.argType, structModule)
    ok(newResolvedStructRef(structRef, resolvedModuleArgType))

proc resolveStructInitializer(app: App, file: parser.File, fileScope: FileScope, module: Module, scope: FunctionScope,
    struct: StructInitializer): Result[ResolvedStructInitializer, string] =
  let resolvedStructRef = ? resolveStructRef(app, file, fileScope, module, struct.structRef)
  let structModule = module(resolvedStructRef)
  var structBlock = ? structModule.struct(struct.loc)
  if struct.kwargs.len != structBlock.fields.len:
    err(fmt"{struct.loc} struct `{structModule.name.asl}` expects `{structBlock.fields.len}` but `{struct.kwargs.len}` were given")
  else:
    var resolvedKeywordArgs = newSeq[ResolvedKeywordArgument](structBlock.fields.len)
    for kwarg in struct.kwargs:
      let fieldId = ? structBlock.findFieldId(kwarg.name)
      let resolvedExpression = ? resolveExpression(app, file, fileScope,
        module, scope, kwarg.expression)
      resolvedKeywordArgs[fieldId] = newResolvedKeywordArgument(kwarg,
        resolvedExpression)
    ok(newResolvedStructInitializer(struct, resolvedStructRef, resolvedKeywordArgs))

proc resolveUnionRef(app: App, file: parser.File, fileScope: FileScope, module: Module,
    unionRef: UnionRef): Result[ResolvedUnionRef, string] =
  ## Resolves a UnionRef into the one-shape (module + impls).
  ## Empty impls drive leave-as-is inference at the analyzer; non-empty
  ## impls are arity- and constraint-checked here via
  ## resolveModuleArgumentType so the analyzer can seed its
  ## GenericImplMap from the seq directly.
  let unionModule = ? file.findModule(fileScope, unionRef.module)
  if unionRef.impls.len == 0:
    return ok(newResolvedUnionRef(unionRef, unionModule, @[]))
  let syntheticArgType = newArgumentType(unionRef.module, unionRef.impls)
  let resolvedArgType = ? resolveArgumentType(app, file, fileScope, module, syntheticArgType)
  ok(newResolvedUnionRef(unionRef, unionModule, resolvedArgType.module.impls))

proc resolveUnionInitializer(app: App, file: parser.File, fileScope: FileScope,
    module: Module, scope: FunctionScope,
    unionInit: UnionInitializer): Result[ResolvedUnionInitializer, string] =
  let resolvedUnionRef = ? resolveUnionRef(app, file, fileScope, module, unionInit.unionRef)
  let initModule = module(resolvedUnionRef)
  let union = ? initModule.union(unionInit.loc)
  let variant = ? union.findVariant(unionInit.variant)
  if unionInit.kwargs.len != variant.fields.len:
    return err(fmt"{unionInit.loc} union `{initModule.name.asl}` expects `{variant.fields.len}` but `{unionInit.kwargs.len}` were given")
  var resolvedKeywordArgs = newSeq[ResolvedKeywordArgument](
    variant.fields.len)
  for kwarg in unionInit.kwargs:
    let fieldId = ? variant.findFieldId(kwarg.name)
    let resolvedExpression = ? resolveExpression(app, file, fileScope,
      module, scope, kwarg.expression)
    resolvedKeywordArgs[fieldId] = newResolvedKeywordArgument(kwarg,
      resolvedExpression)
  ok(newResolvedUnionInitializer(unionInit, resolvedUnionRef, resolvedKeywordArgs))

proc resolveInitializer(app: App, file: parser.File, fileScope: FileScope,
    module: Module, scope: FunctionScope,
    initializer: Initializer): Result[ResolvedInitializer, string] =
  case initializer.kind:
  of ikLiteral:
    let resolvedLiteralInit = ? resolveLiteralInitializer(app, file, fileScope,
      module, initializer.literal)
    ok(newResolvedInitializer(resolvedLiteralInit))
  of ikStruct:
    let resolvedStructInit = ? resolveStructInitializer(app, file, fileScope,
      module, scope, initializer.struct)
    ok(newResolvedInitializer(resolvedStructInit))
  of ikUnion:
    let resolvedUnionInit = ? resolveUnionInitializer(app, file, fileScope,
      module, scope, initializer.union)
    ok(newResolvedInitializer(resolvedUnionInit))

proc resolveCasePattern*(casePattern: CasePattern): Result[
    ResolvedCasePattern, string] =
  case casePattern.kind:
  of cpkInteger:
    ok(newResolvedCasePattern(casePattern.intLit))
  of cpkVariable:
    ok(newResolvedCasePattern(casePattern.variable))
  of cpkUnion:
    ok(newResolvedCasePattern(casePattern.variant))

proc resolveCaseBlock(app: App, file: parser.File, fileScope: FileScope,
    module: Module, scope: FunctionScope,
    caseBlock: CaseBlock): Result[ResolvedCaseBlock, string] =
  let resolvedCasePattern = ? resolveCasePattern(caseBlock.pattern)
  var resolvedStatements: seq[ResolvedStatement]
  var childScope = scope # create a child scope to enable shadowing

  for binding in caseBlock.pattern.bindings:
    childScope.incl(binding)

  for statement in caseBlock.statements:
    let resolvedStatement = ? resolveStatement(app, file, fileScope, module,
      childScope, statement)
    resolvedStatements.add(resolvedStatement)
    if resolvedStatement.variable.isSome:
      childScope.incl(resolvedStatement.variable.get)
  ok(newResolvedCaseBlock(caseBlock, resolvedCasePattern, resolvedStatements))

proc resolveMatchExpression(app: App, file: parser.File, fileScope: FileScope,
    module: Module, scope: FunctionScope,
    match: MatchExpression): Result[ResolvedMatchExpression, string] =
  let resolvedSubject = ? resolveExpression(app, file, fileScope, module, scope,
    match.subject)
  var resolvedCaseBlocks: seq[ResolvedCaseBlock]
  for caseBlock in match.cases:
    let resolvedCaseBlock = ? resolveCaseBlock(app, file, fileScope, module,
      scope, caseBlock)
    resolvedCaseBlocks.add(resolvedCaseBlock)
  ok(newResolvedMatchExpression(match, resolvedSubject, resolvedCaseBlocks))

proc resolveExpression*(app: App,     file: parser.File, fileScope: FileScope,
    module: Module, scope: FunctionScope,
    expression: Expression): Result[ResolvedExpression, string] =
  case expression.kind:
  of ekLiteral:
    ok(newResolvedExpression(expression.literal))
  of ekGetter:
    let resolvedGetter = ? resolveGetter(file, scope, expression.getter)
    ok(newResolvedExpression(resolvedGetter))
  of ekVariable:
    let resolvedVariable = ? resolveVariable(file, scope, expression.variable)
    ok(newResolvedExpression(resolvedVariable))
  of ekFnCall:
    let resolvedFunctionCall = ? resolveFunctionCall(app, file, fileScope,
      module, scope, expression.fncall)
    ok(newResolvedExpression(resolvedFunctionCall))
  of ekInitializer:
    let resolvedInitializer = ? resolveInitializer(app, file, fileScope, module,
      scope, expression.initializer)
    ok(newResolvedExpression(resolvedInitializer))
  of ekMatch:
    let resolvedMatchExpr = ? resolveMatchExpression(app, file, fileScope,
      module, scope, expression.match)
    ok(newResolvedExpression(resolvedMatchExpr))

proc resolveAssignment(app: App, file: parser.File, fileScope: FileScope,
    module: Module, scope: FunctionScope,
    assignment: Assignment): Result[ResolvedAssignment, string] =
  let resolvedExpression = ? resolveExpression(app, file, fileScope, module,
    scope, assignment.expression)
  ok(newResolvedAssignment(assignment, resolvedExpression))

proc resolveSetter(app: App, file: parser.File, fileScope: FileScope,
    module: Module, scope: FunctionScope,
    setter: Setter): Result[ResolvedSetter, string] =
  let resolvedGetter = ? resolveGetter(file, scope, setter.target)
  let resolvedExpression = ? resolveExpression(app, file, fileScope, module,
    scope, setter.expression)
  ok(newResolvedSetter(setter, resolvedGetter, resolvedExpression))

proc resolveStatement*(app: App,     file: parser.File, fileScope: FileScope,
    module: Module, scope: FunctionScope,
    statement: Statement): Result[ResolvedStatement, string] =
  case statement.kind:
  of skExpr:
    let resolvedExpression = ? resolveExpression(app, file, fileScope, module,
      scope, statement.expression)
    ok(newResolvedStatement(resolvedExpression))
  of skAssignment:
    let resolvedAssignment = ? resolveAssignment(app, file, fileScope, module,
      scope, statement.assignment)
    ok(newResolvedStatement(resolvedAssignment))
  of skSetter:
    let resolvedMutation = ? resolveSetter(app, file, fileScope, module, scope,
      statement.setter)
    ok(newResolvedStatement(resolvedMutation))

proc resolveUserFunction*(app: App, file: parser.File, fileScope: FileScope, module: Module,
    function: UserFunction): Result[ResolvedUserFunction, string] =
  if function.decorators.len > 0:
    return err(fmt"{function.loc} todo: resolve decorators in user function")

  let resolvedFunctionDef = ? resolveFunctionDef(app, file, fileScope, module, function.def)

  var scope: FunctionScope
  for arg in resolvedFunctionDef.args:
    scope.incl(arg.name)

  var resolvedStatements: seq[ResolvedStatement]
  for statement in function.statements:
    let resolvedStatement = ? resolveStatement(app, file, fileScope, module,
      scope, statement)
    resolvedStatements.add(resolvedStatement)
    if resolvedStatement.variable.isSome:
      scope.incl(resolvedStatement.variable.get)

  ok(newResolvedUserFunction(function, resolvedFunctionDef, resolvedStatements))

proc resolveFunction*(app: App,     file: parser.File, fileScope: FileScope, module: Module,
    function: Function): Result[ResolvedFunction, string] =
  case function.kind:
  of fkUser:
    let resolvedUserFunction = ? resolveUserFunction(app, file, fileScope,
      module, function.user)
    ok(newResolvedFunction(resolvedUserFunction))
  of fkExtern:
    let resolvedExternFunction = ? resolveExternFunction(app, file, fileScope,
      module, function.extern)
    ok(newResolvedFunction(resolvedExternFunction))

proc resolveModule*(app: App, file: parser.File,
    fileScope: FileScope, module: Module): Result[ResolvedModule, string] =
  ## Resolve every part of the parser Module and construct the
  ## `ResolvedModule` in one pass. Argument types along the way carry
  ## parser `Module` back-refs, so there's no need for a two-pass
  ## shell/populate structure.
  if module.decorators.len > 0:
    return err("todo: resolve decorators")

  var resolvedData: Option[ResolvedData]
  if module.data.isSome:
    let resolvedDataDef = ? resolveDataDef(app, file, fileScope, module,
      module.data.get)
    resolvedData = some(resolvedDataDef)

  var resolvedFunctions: seq[ResolvedFunction]
  for function in module.functions:
    let resolvedFunction = ? resolveFunction(app, file, fileScope, module,
      function)
    resolvedFunctions.add(resolvedFunction)

  ok(newResolvedModule(module, resolvedData, resolvedFunctions))

proc resolveGeneric*(app: App, file: parser.File, fileScope: FileScope, generic: Generic): Result[ResolvedGeneric, string] =
  if generic.decorators.len > 0:
    err(fmt"{generic.loc} todo: resolve generic decorators")
  else:
    var resolvedFunctionDefs: seq[ResolvedFunctionDef]
    for funcDef in generic.funcDefs:
      let resolvedFunctionDef = ? resolveFunctionDef(app, file, fileScope, generic, funcDef)
      resolvedFunctionDefs.add(resolvedFunctionDef)

    ok(newResolvedGeneric(generic, resolvedFunctionDefs))

proc resolveType*(app: App, file: parser.File, fileScope: FileScope, typ: Type): Result[ResolvedType, string] =
  case typ.kind:
  of tkGeneric:
    let resolvedGeneric = ? resolveGeneric(app, file, fileScope, typ.generic)
    ok(newResolvedType(resolvedGeneric))
  of tkModule:
    let resolvedModule = ? resolveModule(app, file, fileScope, typ.module)
    ok(newResolvedType(resolvedModule))

proc resolveImport*(app: App, file: parser.File, imp: Import): Result[ResolvedImport, string] =
  let impFile = ? app.findFile(imp.absPath)
  var resolvedImportedTypes: seq[ResolvedImportedType]
  case imp.kind:
  of ikExplicit:
    for impType in imp.names:
      let resolvedImportedType = ? impFile.findExportedType(impType.name)
      resolvedImportedTypes.add(newResolvedImportedType(impType, resolvedImportedType))
  of ikShorthand:
    for typ in impFile.publicTypes:
      let synthesized = newImportedType(typ.name, none(Identifier), imp.loc)
      resolvedImportedTypes.add(newResolvedImportedType(synthesized, typ))
  ok(newResolvedImport(imp, impFile, resolvedImportedTypes))

proc resolveFile*(app: App, file: parser.File): Result[ResolvedFile, string] =
  var resolvedImports: seq[ResolvedImport]
  var fileScope: FileScope
  for imp in file.imports:
    let resolvedImport = ? resolveImport(app, file, imp)
    resolvedImports.add(resolvedImport)
    for impType in resolvedImport.importedTypes:
      if impType.binding in fileScope:
        let loc = fileScope[impType.binding].loc
        return err(fmt"{impType.loc} duplicate type declaration encountered, see previous declaration at {loc}")
      fileScope[impType.binding] = impType.typ

  var resolvedTypes: seq[ResolvedType]
  for typ in file.types:
    if typ.name in fileScope:
      let loc = fileScope[typ.name].loc
      return err(fmt"{typ.loc} duplicate type declaration encountered, see previous declaration at {loc}")
    let resolvedType = ? resolveType(app, file, fileScope, typ)
    resolvedTypes.add(resolvedType)

  ok(newResolvedFile(file, resolvedImports, resolvedTypes))

proc resolve*(app: App): Result[ResolvedApp, string] =
  var resolvedFiles: seq[ResolvedFile]
  for file in app.files:
    let resolvedFile = ? resolveFile(app, file)
    resolvedFiles.add(resolvedFile)
  ok(newResolvedApp(resolvedFiles))