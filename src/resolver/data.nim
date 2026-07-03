## Data-block resolution: struct / variant / union / data umbrella.
##
## The `Resolved*` types, their constructors, and direct-field
## accessors live in `types.nim`. This file owns the computed
## helpers (findField, requires, loc, name, ...) and the resolveX
## procs.

import results, strformat, tables

import tokenizer
import parser
import types
import literals
import argtypes
import funcdefs

proc accumulateGenericPosition(genericTypeIndex: var Table[ResolvedGenericArgumentType, int], field: ResolvedArgumentDefinition) =
  ## Assigns the next position to each new generic encountered in
  ## field types. Same name across multiple fields keeps its first
  ## position — the analyzer's GenericImplMap binds one generic to
  ## one concrete type per construction, so duplicate occurrences
  ## are semantically benign (any conflict surfaces at the init site
  ## via merge()). Generic-uniqueness inside an explicit requires()
  ## block is still enforced by validateRequiresConstraints.
  case field.argType.kind:
  of ratkModule: discard
  of ratkGeneric:
    let genericType = field.argType.generic
    if genericType notin genericTypeIndex:
      genericTypeIndex[genericType] = genericTypeIndex.len

# ---- ResolvedStructDef helpers ----

proc loc*(struct: ResolvedStructDef): Location = struct.parsed.loc

proc findField*(struct: ResolvedStructDef, name: Identifier): Result[ResolvedArgumentDefinition, string] =
  if name in struct.fieldIndex: ok(struct.fields[struct.fieldIndex[name]])
  else: err(fmt"{name.loc} field `{name.asl}` does not exist")

proc requires*(struct: ResolvedStructDef): seq[ResolvedGenericArgumentType] =
  var requires = newSeq[ResolvedGenericArgumentType](struct.genericTypeIndex.len)
  for genericType, index in struct.genericTypeIndex:
    requires[index] = genericType
  return requires

proc resolveStructDef*(app: App, shells: ResolvedModuleShells, file: parser.File, fileScope: FileScope, module: Module, struct: StructDef): Result[ResolvedStructDef, string] =
  var resolvedFields: seq[ResolvedArgumentDefinition]
  var genericTypeIndex: Table[ResolvedGenericArgumentType, int]
  for field in struct.fields:
    let resolvedField = ? resolveArgumentDefinition(app, shells, file, fileScope, module, field)
    genericTypeIndex.accumulateGenericPosition(resolvedField)
    resolvedFields.add(resolvedField)
  ok(newResolvedStructDef(struct, resolvedFields, genericTypeIndex))

# ---- ResolvedVariant helpers ----

proc loc*(variant: ResolvedVariant): Location = variant.parsed.loc
proc name*(variant: ResolvedVariant): Identifier = variant.parsed.name

proc findField*(variant: ResolvedVariant, name: Identifier): Result[ResolvedArgumentDefinition, string] =
  if name in variant.fieldIndex: ok(variant.fields[variant.fieldIndex[name]])
  else: err(fmt"{name.loc} field `{name.asl}` does not exist")

# NOTE: `genericTypeIndex` is the union's shared position table — mutated
# in place as each variant's fields contribute new generics (in
# declaration order); not returned because the union accumulates it.
proc resolveVariant(app: App, shells: ResolvedModuleShells, file: parser.File, fileScope: FileScope, module: Module, variant: VariantDefinition, genericTypeIndex: var Table[ResolvedGenericArgumentType, int]): Result[ResolvedVariant, string] =
  var resolvedFields: seq[ResolvedArgumentDefinition]
  for field in variant.fields:
    let resolvedField = ? resolveArgumentDefinition(app, shells, file, fileScope, module, field)
    genericTypeIndex.accumulateGenericPosition(resolvedField)
    resolvedFields.add(resolvedField)
  ok(newResolvedVariant(variant, resolvedFields))

# ---- ResolvedUnionDef helpers ----

proc loc*(union: ResolvedUnionDef): Location = union.parsed.loc

proc findVariant*(union: ResolvedUnionDef, variant: Identifier): Result[ResolvedVariant, string] =
  if variant in union.variantIndex: ok(union.variants[union.variantIndex[variant]])
  else: err(fmt"{variant.loc} union does not contain variant `{variant.asl}`")

proc requires*(union: ResolvedUnionDef): seq[ResolvedGenericArgumentType] =
  ## One union scope: a generic name shared across variants is one
  ## shared type parameter (Rust style), so dedup by underlying Generic
  ## identity. Within-variant duplicates are already impossible
  ## (caught by validateUniqueGenericFields in resolveVariant).
  var requires = newSeq[ResolvedGenericArgumentType](union.genericTypeIndex.len)
  for genericType, index in union.genericTypeIndex:
    requires[index] = genericType
  return requires

proc resolveUnionDef*(app: App, shells: ResolvedModuleShells, file: parser.File, fileScope: FileScope,
    module: Module, union: UnionDef): Result[ResolvedUnionDef, string] =
  var resolvedVariants: seq[ResolvedVariant]
  var genericTypeIndex: Table[ResolvedGenericArgumentType, int]
  for variant in union.variants:
    let resolvedVariant = ? resolveVariant(app, shells, file, fileScope, module, variant, genericTypeIndex)
    resolvedVariants.add(resolvedVariant)
  ok(newResolvedUnionDef(union, resolvedVariants, genericTypeIndex))

# ---- ResolvedData helpers ----

proc requires*(data: ResolvedData): seq[ResolvedGenericArgumentType] =
  case data.kind:
  of rdkLiteral: @[]
  of rdkStruct: data.struct.requires
  of rdkUnion: data.union.requires

proc resolveDataBlock*(app: App, shells: ResolvedModuleShells, file: parser.File,
    fileScope: FileScope, module: Module, data: DataBlock): Result[ResolvedData, string] =
  case data.kind:
  of dbkLiteral:
    let resolvedLiteralType = ? resolveLiteralDef(file, data.literal)
    ok(newResolvedData(resolvedLiteralType))
  of dbkStruct:
    let resolvedStruct = ? resolveStructDef(app, shells, file, fileScope, module,
      data.struct)
    ok(newResolvedData(resolvedStruct))
  of dbkUnion:
    let resolvedUnion = ? resolveUnionDef(app, shells, file, fileScope, module, data.union)
    ok(newResolvedData(resolvedUnion))
