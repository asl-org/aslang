import options, results, sequtils, strformat, strutils, tables
## Package façade. Consumers say `import analyzer` to get the full
## compiler stack: analyzer types and `analyze*`, plus the resolver
## layer that analyzer builds on (which itself re-exports the parser
## AST + `parse*` entry point + Location).
##
## Under the nesting convention, `src/asl.nim` only needs `import
## cli, analyzer` to reach every construct in the compiler.

import ./analyzer/resolver
export resolver

# ---- file-scope alias ----
import ./analyzer/filescope
export filescope

# ---- function-scope alias ----
import ./analyzer/funcscope
export funcscope

# ---- argument-type cluster (mutually-recursive tagged union) ----
import ./analyzer/argtype
export argtype

import ./analyzer/moduleargtype
export moduleargtype

import ./analyzer/genericargtype
export genericargtype

import ./analyzer/genericimplmap
export genericimplmap

# ---- phase-A leaves (W1+ of plan_analyzer_two_pass.md) ----
import ./analyzer/argdef
export argdef

import ./analyzer/funcdef
export funcdef

import ./analyzer/literaldef
export literaldef

import ./analyzer/structdef
export structdef

import ./analyzer/variantdef
export variantdef

import ./analyzer/uniondef
export uniondef

import ./analyzer/datadef
export datadef

import ./analyzer/moduledef
export moduledef

import ./analyzer/generic
export generic

import ./analyzer/definedtype
export definedtype

import ./analyzer/filedef
export filedef

import ./analyzer/appdef
export appdef

# ---- pattern cluster ----
import ./analyzer/literalparse
export literalparse

import ./analyzer/unionpatternscope
export unionpatternscope

import ./analyzer/literalpatternscope
export literalpatternscope

import ./analyzer/binding
export binding

import ./analyzer/unionpattern
export unionpattern

import ./analyzer/casepattern
export casepattern

# ---- body cluster: leaf nodes ----
import ./analyzer/variable
export variable

import ./analyzer/literalinit
export literalinit

import ./analyzer/getter
export getter

# ---- body cluster: mutually-recursive statement/expression web ----
import ./analyzer/statement
export statement

# ---- function cluster ----
import ./analyzer/userfunc
export userfunc

import ./analyzer/externfunc
export externfunc

import ./analyzer/function
export function

import ./analyzer/module
export module

# ---- import cluster ----
import ./analyzer/importedtype
export importedtype

import ./analyzer/importdef
export importdef

# ---- app/file (top-level) ----
import ./analyzer/file
export file

import ./analyzer/app
export app

proc findType*(fileScope: ResolvedFileScope, name: Identifier, loc: Location): Result[ResolvedType, string] =
  if name notin fileScope:
    err(fmt"{loc} UNREACHABLE: type `{name.asl}` is not defined")
  else:
    ok(fileScope[name])

proc findModuleDef*(fileScope: ResolvedFileScope, name: Identifier, loc: Location): Result[ResolvedModule, string] =
  let entry = ? fileScope.findType(name, loc)
  case entry.kind:
  of rdtkModule: ok(entry.module)
  of rdtkGeneric:
    err(fmt"{loc} UNREACHABLE: scope entry `{name.asl}` is a generic but caller expected module")

# Extract helpers — resolve an AnalyzedArgumentType to the analyzer-
# side data block (or struct / union sub-view). Route through
# `appDef.findDefinedType` so the returned data is the phase-A
# analyzed form (AnalyzedData / AnalyzedStruct / AnalyzedUnion) with
# pre-analyzed field / variant argTypes. Callers that need the
# underlying resolver types can reach `.resolved` on the fields.

proc findModuleDef*(appDef: AnalyzedAppDefinition, argType: AnalyzedArgumentType, loc: Location): Result[AnalyzedModuleDefinition, string] =
  case argType.kind:
  of aatkGeneric:
    err(fmt"{loc} todo: extract module def for a generic subject type")
  of aatkModule:
    let definedType = ? appDef.findDefinedType(newResolvedType(argType.module.module))
    case definedType.kind:
    of adtkModule: ok(definedType.module)
    of adtkGeneric:
      err(fmt"{loc} UNREACHABLE: argType is aatkModule but definedType is adtkGeneric")

proc extractDataDef*(moduleDef: AnalyzedModuleDefinition, loc: Location): Result[AnalyzedData, string] =
  if moduleDef.data.isNone:
    err(fmt"{loc} UNREACHABLE: expression does not return a data type")
  else:
    ok(moduleDef.data.get)

proc extractDataDef*(appDef: AnalyzedAppDefinition, argType: AnalyzedArgumentType, loc: Location): Result[AnalyzedData, string] =
  let moduleDef = ? findModuleDef(appDef, argType, loc)
  extractDataDef(moduleDef, loc)

proc extractStructFor*(appDef: AnalyzedAppDefinition, argType: AnalyzedArgumentType, loc: Location): Result[AnalyzedStruct, string] =
  let moduleDef = ? findModuleDef(appDef, argType, loc)
  let dataDef = ? extractDataDef(moduleDef, loc)
  case dataDef.kind:
  of adkStruct: ok(dataDef.struct)
  of adkUnion: err(fmt"{loc} expected module `{moduleDef.name.asl}` to have a struct block but found union")
  of adkLiteral: err(fmt"{loc} expected module `{moduleDef.name.asl}` to have a struct block but found literal")

proc extractUnionFor*(appDef: AnalyzedAppDefinition, argType: AnalyzedArgumentType, loc: Location): Result[AnalyzedUnion, string] =
  let moduleDef = ? findModuleDef(appDef, argType, loc)
  let dataDef = ? extractDataDef(moduleDef, loc)
  case dataDef.kind:
  of adkUnion: ok(dataDef.union)
  of adkStruct: err(fmt"{loc} expected module `{moduleDef.name.asl}` to have a union block but found struct")
  of adkLiteral: err(fmt"{loc} expected module `{moduleDef.name.asl}` to have a union block but found literal")

proc analyzeGenericArgumentType*(app: ResolvedApp, file: ResolvedFile, generic: ResolvedGeneric, genericArgType: ResolvedGenericArgumentType): Result[AnalyzedGenericArgumentType, string] =
  let genericArg = ? file.findGeneric(genericArgType.parsed.name)
  if genericArg != generic:
    err(fmt"{genericArgType.loc} generic `{genericArgType.parsed.name.asl}` does not exist in the file `{file.path}` scope")
  else:
    ok(newAnalyzedGenericArgumentType(genericArg, genericArgType.loc))

proc analyzeGenericArgumentType*(app: ResolvedApp, file: ResolvedFile, fileScope: ResolvedFileScope, module: ResolvedModule, genericArgType: ResolvedGenericArgumentType): Result[AnalyzedGenericArgumentType, string] =
  ## Resolves the generic by checking the current file's own generics
  ## first, then falling back to the file scope for imported names.
  ## A `ResolvedGenericArgumentType` whose `.parsed` refers to an
  ## imported generic still needs its ResolvedGeneric surfaced so
  ## downstream code can look up its constraint-carrying funcDefs.
  let maybeGenericArg = file.findGeneric(genericArgType.parsed.name)
  if maybeGenericArg.isOk:
    ok(newAnalyzedGenericArgumentType(maybeGenericArg.get, genericArgType.loc))
  elif genericArgType.parsed.name in fileScope:
    let typ = fileScope[genericArgType.parsed.name]
    case typ.kind:
    of rdtkGeneric:
      ok(newAnalyzedGenericArgumentType(typ.generic, genericArgType.loc))
    of rdtkModule:
      err(fmt"{genericArgType.loc} [UNREACHABLE] expected `{genericArgType.parsed.name.asl}` to be a generic but found module")
  else:
    err(fmt"{genericArgType.loc} generic `{genericArgType.parsed.name.asl}` is neither defined nor imported")

proc findArgTypeModule(file: ResolvedFile, fileScope: ResolvedFileScope, argType: ResolvedModuleArgumentType): Result[ResolvedModule, string] =
  ## Look up the ResolvedModule for a resolved argument type. The
  ## argType carries a parser Module identifier — resolver-side types
  ## intentionally do not back-ref ResolvedModule (would cycle). We
  ## look up in order:
  ##   1. Local file's typeIndex by name (fast path, most common).
  ##   2. fileScope by name (imports keyed by binding — handles the
  ##      non-aliased import case where argType.name matches the
  ##      import's binding).
  ##   3. fileScope by parser.Module identity (fallback for aliased
  ##      imports: `import { u8 as Byte }` binds "Byte" but the
  ##      argType's `.name` is the underlying "u8" — so the by-name
  ##      lookup misses; we iterate values comparing parsed modules
  ##      to find the entry).
  let maybeTypeModule = file.findModule(argType.name)
  if maybeTypeModule.isOk:
    return ok(maybeTypeModule.value)

  if argType.name in fileScope:
    let importedType = fileScope[argType.name]
    case importedType.kind:
    of rdtkGeneric: return err(fmt"{argType.loc} [UNREACHABLE] expected `{argType.name.asl}` to be a module but found generic.")
    of rdtkModule: return ok(importedType.module)

  # Aliased-import fallback: match by parser.Module identity.
  for _, importedType in fileScope:
    if importedType.kind == rdtkModule and importedType.module.parsed == argType.module:
      return ok(importedType.module)

  err(fmt"{argType.loc} module `{argType.name.asl}` is neither defined nor imported")

proc analyzeArgumentType*(app: ResolvedApp, file: ResolvedFile, fileScope: ResolvedFileScope, module: ResolvedModule, argType: ResolvedArgumentType): Result[AnalyzedArgumentType, string]
proc analyzeArgumentType*(app: ResolvedApp, file: ResolvedFile, fileScope: ResolvedFileScope, generic: ResolvedGeneric, argType: ResolvedArgumentType): Result[AnalyzedArgumentType, string]

proc analyzeModuleArgumentType*(app: ResolvedApp, file: ResolvedFile, fileScope: ResolvedFileScope, module: ResolvedModule, argType: ResolvedModuleArgumentType): Result[AnalyzedModuleArgumentType, string] =
  ## Post-task-7: the resolver already validated arity and
  ## generic-constraint satisfaction on `argType.impls`. All we need is
  ## to look up the ResolvedModule via fileScope and lift each impl
  ## through analyzeArgumentType.
  let typeModule = ? file.findArgTypeModule(fileScope, argType)
  var analyzedImpls: seq[AnalyzedArgumentType]
  for impl in argType.impls:
    let analyzedImpl = ? analyzeArgumentType(app, file, fileScope, module, impl)
    analyzedImpls.add(analyzedImpl)
  ok(newAnalyzedModuleArgumentType(argType, typeModule, analyzedImpls))

proc analyzeModuleArgumentType*(app: ResolvedApp, file: ResolvedFile, fileScope: ResolvedFileScope, generic: ResolvedGeneric, argType: ResolvedModuleArgumentType): Result[AnalyzedModuleArgumentType, string] =
  ## Generic-context twin of the module-context overload above; same
  ## post-task-7 shape (no arity check, no constraint walk).
  let typeModule = ? file.findArgTypeModule(fileScope, argType)
  var analyzedImpls: seq[AnalyzedArgumentType]
  for impl in argType.impls:
    let analyzedImpl = ? analyzeArgumentType(app, file, fileScope, generic, impl)
    analyzedImpls.add(analyzedImpl)
  ok(newAnalyzedModuleArgumentType(argType, typeModule, analyzedImpls))

proc analyzeArgumentType*(app: ResolvedApp, file: ResolvedFile, fileScope: ResolvedFileScope, module: ResolvedModule, argType: ResolvedArgumentType): Result[AnalyzedArgumentType, string] =
  case argType.kind:
  of ratkGeneric:
    let analyzedArgType = ? analyzeGenericArgumentType(app, file, fileScope, module, argType.generic)
    ok(newAnalyzedArgumentType(analyzedArgType))
  of ratkModule:
    let analyzedArgType = ? analyzeModuleArgumentType(app, file, fileScope, module, argType.module)
    ok(newAnalyzedArgumentType(analyzedArgType))

proc analyzeArgumentType*(app: ResolvedApp, file: ResolvedFile, fileScope: ResolvedFileScope, generic: ResolvedGeneric, argType: ResolvedArgumentType): Result[AnalyzedArgumentType, string] =
  case argType.kind:
  of ratkGeneric:
    let analyzedArgType = ? analyzeGenericArgumentType(app, file, generic, argType.generic)
    ok(newAnalyzedArgumentType(analyzedArgType))
  of ratkModule:
    let analyzedArgType = ? analyzeModuleArgumentType(app, file, fileScope, generic, argType.module)
    ok(newAnalyzedArgumentType(analyzedArgType))

# ============================================================
# Phase-A argument / function def analyzers (W2 of
# plans/plan_analyzer_two_pass.md). Ported from oldanalyzer.nim:479
# (analyzeArgumentDefinition) and :522 (analyzeFunctionDefinition).
#
# ⚠ KNOWN LIMITATION — SIGNATURE-PARITY IS HASH-EQUALITY, NOT
#   UNIFICATION.
#
# The impl-satisfies-base signature check (currently done at
# `analyzeValueTypeAgainstDefType` on the facade + `checkImplSatisfiesGeneric`
# on the resolver) uses hash-based `==` for AnalyzedArgumentType
# comparison. That works for fully-bound-vs-fully-bound comparisons
# but not for cases where either side carries free generics
# (post leave-as-is inference).
#
# What breaks: an impl providing `byte_size(items: Array[u8])` where
# the base generic mandates `byte_size(items: Array[Any])` — hash
# equality treats these as different types when a unification pass
# would bind `Any → u8` and accept the impl. Dormant today because
# every fixture in the test suite uses fully-bound impl types at the
# base-generic satisfaction boundary; the bug lies waiting until
# someone writes an impl whose funcDef references a partially-generic
# argument type.
#
# The fix requires routing every assignability check through
# `analyzeValueTypeAgainstDefType` + `merge` with eager chain-
# collapsing in `merge` (so `Sample → K, K → u8` collapses to
# `Sample → u8`). See `plans/plan_deferred_typing.md` §
# "Equality vs unification for analyzed types" — that plan owns the
# fix; this port preserves current behavior and does not introduce
# any new use of `==`.
# ============================================================

proc analyzeArgumentDefinition*(app: ResolvedApp, file: ResolvedFile, fileScope: ResolvedFileScope, module: ResolvedModule, argDef: ResolvedArgumentDef): Result[AnalyzedArgumentDefinition, string] =
  let analyzedArgType = ? analyzeArgumentType(app, file, fileScope, module, argDef.argType)
  ok(newAnalyzedArgumentDefinition(argDef, analyzedArgType))

proc analyzeArgumentDefinition*(app: ResolvedApp, file: ResolvedFile, fileScope: ResolvedFileScope, generic: ResolvedGeneric, argDef: ResolvedArgumentDef): Result[AnalyzedArgumentDefinition, string] =
  let analyzedArgType = ? analyzeArgumentType(app, file, fileScope, generic, argDef.argType)
  ok(newAnalyzedArgumentDefinition(argDef, analyzedArgType))

proc analyzeFunctionDefinition*(app: ResolvedApp, file: ResolvedFile, fileScope: ResolvedFileScope, module: ResolvedModule, funcDef: ResolvedFunctionDef): Result[AnalyzedFunctionDefinition, string] =
  var analyzedArgDefs: seq[AnalyzedArgumentDefinition]
  for arg in funcDef.args:
    let analyzedArgDef = ? analyzeArgumentDefinition(app, file, fileScope, module, arg)
    analyzedArgDefs.add(analyzedArgDef)
  let analyzedReturns = ? analyzeArgumentType(app, file, fileScope, module, funcDef.returns)
  ok(newAnalyzedFunctionDefinition(funcDef, analyzedArgDefs, analyzedReturns))

proc analyzeFunctionDefinition*(app: ResolvedApp, file: ResolvedFile, fileScope: ResolvedFileScope, generic: ResolvedGeneric, funcDef: ResolvedFunctionDef): Result[AnalyzedFunctionDefinition, string] =
  var analyzedArgDefs: seq[AnalyzedArgumentDefinition]
  for arg in funcDef.args:
    let analyzedArgDef = ? analyzeArgumentDefinition(app, file, fileScope, generic, arg)
    analyzedArgDefs.add(analyzedArgDef)
  let analyzedReturns = ? analyzeArgumentType(app, file, fileScope, generic, funcDef.returns)
  ok(newAnalyzedFunctionDefinition(funcDef, analyzedArgDefs, analyzedReturns))

# ============================================================
# Phase-A data-block analyzers (W3 of plan_analyzer_two_pass.md).
# Ported from oldanalyzer.nim:592 / :629 / :665 / :706. Each walks
# its fields via analyzeArgumentDefinition, delegates the
# genericTypeIndex to the resolver's already-computed table (no
# re-accumulation on the analyzer side), and wraps into the
# corresponding phase-A type.
# ============================================================

proc analyzeStruct*(app: ResolvedApp, file: ResolvedFile, fileScope: ResolvedFileScope, module: ResolvedModule, struct: ResolvedStructDef): Result[AnalyzedStruct, string] =
  var analyzedFields: seq[AnalyzedArgumentDefinition]
  for field in struct.fields:
    let analyzedField = ? analyzeArgumentDefinition(app, file, fileScope, module, field)
    analyzedFields.add(analyzedField)
  ok(newAnalyzedStruct(struct, analyzedFields))

proc analyzeVariant*(app: ResolvedApp, file: ResolvedFile, fileScope: ResolvedFileScope, module: ResolvedModule, variant: ResolvedVariant): Result[AnalyzedVariant, string] =
  var analyzedFields: seq[AnalyzedArgumentDefinition]
  for field in variant.fields:
    let analyzedField = ? analyzeArgumentDefinition(app, file, fileScope, module, field)
    analyzedFields.add(analyzedField)
  ok(newAnalyzedVariant(variant, analyzedFields))

proc analyzeUnion*(app: ResolvedApp, file: ResolvedFile, fileScope: ResolvedFileScope, module: ResolvedModule, union: ResolvedUnionDef): Result[AnalyzedUnion, string] =
  var analyzedVariants: seq[AnalyzedVariant]
  for variant in union.variants:
    let analyzedVariant = ? analyzeVariant(app, file, fileScope, module, variant)
    analyzedVariants.add(analyzedVariant)
  ok(newAnalyzedUnion(union, analyzedVariants))

proc analyzeData*(app: ResolvedApp, file: ResolvedFile, fileScope: ResolvedFileScope, module: ResolvedModule, data: ResolvedData): Result[AnalyzedData, string] =
  case data.kind:
  of rdkLiteral:
    ok(newAnalyzedData(newAnalyzedLiteralBlock(data.literal)))
  of rdkStruct:
    let analyzedStruct = ? analyzeStruct(app, file, fileScope, module, data.struct)
    ok(newAnalyzedData(analyzedStruct))
  of rdkUnion:
    let analyzedUnion = ? analyzeUnion(app, file, fileScope, module, data.union)
    ok(newAnalyzedData(analyzedUnion))

# ============================================================
# Phase-A module + generic analyzers (W4 of plan_analyzer_two_pass.md).
# Ported from oldanalyzer.nim:763 (analyzeModuleDefinition) and :811
# (analyzeGeneric).
#
# Note: `analyzeModuleDefinition`'s requires walk reads
# `module.data.get.requires` (post the resolver's struct-header merge)
# rather than the retired module-level `requires` clause. Modules
# without a data block carry an empty requires seq.
# ============================================================

proc analyzeModuleDefinition*(app: ResolvedApp, file: ResolvedFile, fileScope: ResolvedFileScope, module: ResolvedModule): Result[AnalyzedModuleDefinition, string] =
  var requires: seq[AnalyzedGenericArgumentType]
  if module.data.isSome:
    for genericArgType in module.data.get.requires:
      let analyzedArgType = ? analyzeGenericArgumentType(app, file, fileScope, module, genericArgType)
      requires.add(analyzedArgType)

  var maybeAnalyzedData: Option[AnalyzedData]
  if module.data.isSome:
    let analyzedData = ? analyzeData(app, file, fileScope, module, module.data.get)
    maybeAnalyzedData = some(analyzedData)

  var analyzedFuncDefs: seq[AnalyzedFunctionDefinition]
  for function in module.functions:
    let analyzedFuncDef = ? analyzeFunctionDefinition(app, file, fileScope, module, function.def)
    analyzedFuncDefs.add(analyzedFuncDef)

  ok(newAnalyzedModuleDefinition(module, requires, maybeAnalyzedData, analyzedFuncDefs))

proc analyzeGeneric*(app: ResolvedApp, file: ResolvedFile, fileScope: ResolvedFileScope, generic: ResolvedGeneric): Result[AnalyzedGeneric, string] =
  var analyzedFuncDefs: seq[AnalyzedFunctionDefinition]
  for funcDef in generic.funcDefs:
    let analyzedFuncDef = ? analyzeFunctionDefinition(app, file, fileScope, generic, funcDef)
    analyzedFuncDefs.add(analyzedFuncDef)
  ok(newAnalyzedGeneric(generic, analyzedFuncDefs))

# ============================================================
# Phase-A defined-type dispatcher (W5 of plan_analyzer_two_pass.md).
# Ported from oldanalyzer.nim:847.
# ============================================================

proc analyzeDefinedType*(app: ResolvedApp, file: ResolvedFile, fileScope: ResolvedFileScope, definedType: ResolvedType): Result[AnalyzedDefinedType, string] =
  case definedType.kind:
  of rdtkGeneric:
    let analyzedGeneric = ? analyzeGeneric(app, file, fileScope, definedType.generic)
    ok(newAnalyzedDefinedType(analyzedGeneric))
  of rdtkModule:
    let analyzedModule = ? analyzeModuleDefinition(app, file, fileScope, definedType.module)
    ok(newAnalyzedDefinedType(analyzedModule))

# Forward-declare the two import analyzers so analyzeFileDefinition
# can call them; their bodies live near the end of this file
# alongside the top-level analyze* entry.
proc analyzeImportedType*(app: ResolvedApp, impFile: ResolvedFile, impType: ResolvedImportedType): Result[AnalyzedImportedType, string]
proc analyzeImportDefinition*(app: ResolvedApp, file: ResolvedFile, imp: ResolvedImport): Result[AnalyzedImportDefinition, string]

# ============================================================
# Phase-A file dispatcher (W6 of plan_analyzer_two_pass.md).
# Ported from oldanalyzer.nim:951.
#
# The fileScope built here is unified — imports (keyed by binding)
# PLUS the file's local defined types. This differs from
# oldanalyzer.nim:952-958 which used imports only; the unified form
# is required because `findArgTypeModule` looks up an argType's
# underlying module by name (e.g. `Byte` aliased to `u8` produces a
# ResolvedModuleArgumentType whose `.name` is `u8`, not `Byte`),
# and imports-only would miss the underlying-name key. The unified
# scope matches what phase-B `analyzeFile` already builds via
# `newResolvedFileScope`.
# ============================================================

proc analyzeFileDefinition*(app: ResolvedApp, file: ResolvedFile): Result[AnalyzedFileDefinition, string] =
  var analyzedImports: seq[AnalyzedImportDefinition]
  for imp in file.imports:
    let analyzedImport = ? analyzeImportDefinition(app, file, imp)
    analyzedImports.add(analyzedImport)

  let (fileScope, _) = ? newResolvedFileScope(analyzedImports, file.types)

  var analyzedDefinedTypes: seq[AnalyzedDefinedType]
  for aslType in file.types:
    let analyzedDefinedType = ? analyzeDefinedType(app, file, fileScope, aslType)
    analyzedDefinedTypes.add(analyzedDefinedType)
  ok(newAnalyzedFileDefinition(file, analyzedImports, analyzedDefinedTypes, fileScope))

# ============================================================
# Phase-A app dispatcher (W7 of plan_analyzer_two_pass.md).
# Ported from oldanalyzer.nim:987. Walks every file, produces the
# per-app definition bundle. Not yet consumed by the top-level
# `analyze*` entry — that switches to two-pass orchestration at W8.
# ============================================================

proc analyzeAppDefinition*(app: ResolvedApp): Result[AnalyzedAppDefinition, string] =
  var analyzedFileDefinitions: seq[AnalyzedFileDefinition]
  for file in app.files:
    let analyzedFileDefinition = ? analyzeFileDefinition(app, file)
    analyzedFileDefinitions.add(analyzedFileDefinition)
  ok(newAnalyzedAppDefinition(app, analyzedFileDefinitions))

proc analyzeUnionCasePattern*(appDef: AnalyzedAppDefinition, app: ResolvedApp, file: ResolvedFile, fileScope: ResolvedFileScope, module: ResolvedModule, funcScope: AnalyzedFunctionScope, variantPattern: UnionPattern, union: ResolvedUnionDef, subjectImpls: seq[AnalyzedArgumentType]): Result[AnalyzedUnionPattern, string] =
  ## Look each user-supplied pattern field up on the resolved variant,
  ## convert its resolved argType to the analyzer-side value in the
  ## calling module context, and substitute the subject's impls in for
  ## any free generic positions the variant's field types touch.
  let variant = ? union.findVariant(variantPattern.name)
  var bindings: seq[AnalyzedBinding]
  for field in variantPattern.fields:
    let resolvedField = ? variant.findField(field.name)
    let analyzedFieldArgType = ? analyzeArgumentType(app, file, fileScope, module, resolvedField.argType)
    let concreteFieldArgType = analyzedFieldArgType.concrete(subjectImpls, union.genericTypeIndex)
    bindings.add((name: field.binding, argType: concreteFieldArgType))
  ok(newAnalyzedUnionPattern(variantPattern, variant, bindings))

proc analyzeCasePattern*(appDef: AnalyzedAppDefinition, app: ResolvedApp, file: ResolvedFile, fileScope: ResolvedFileScope, module: ResolvedModule, funcScope: AnalyzedFunctionScope, pattern: ResolvedCasePattern, subjectType: AnalyzedArgumentType, union: ResolvedUnionDef, subjectImpls: seq[AnalyzedArgumentType]): Result[AnalyzedCasePattern, string] =
  case pattern.kind:
  of rcpkInteger: err(fmt"{pattern.loc} UNREACHABLE: integer literals are not allowed in union case pattern")
  of rcpkVariable:
    ok(newAnalyzedCasePattern((name: pattern.variable, argType: subjectType)))
  of rcpkUnion:
    let analyzedPattern = ? analyzeUnionCasePattern(appDef, app, file, fileScope, module, funcScope, pattern.variant, union, subjectImpls)
    ok(newAnalyzedCasePattern(analyzedPattern))

proc analyzeCasePattern*(appDef: AnalyzedAppDefinition, app: ResolvedApp, file: ResolvedFile, fileScope: ResolvedFileScope, module: ResolvedModule, funcScope: AnalyzedFunctionScope, pattern: ResolvedCasePattern, subjectType: AnalyzedArgumentType): Result[AnalyzedCasePattern, string] =
  case pattern.kind:
  of rcpkUnion:
    err(fmt"{pattern.loc} UNREACHABLE: union variants are not allowed in literal case pattern")
  of rcpkInteger:
    ok(newAnalyzedCasePattern(pattern.integer))
  of rcpkVariable:
    ok(newAnalyzedCasePattern((name: pattern.variable, argType: subjectType)))

proc analyzeIntegerLiteral[T: SomeInteger](literal: Literal, expected: string): Result[void, string] =
  case literal.kind:
  of lkFloat: err(fmt"{literal.loc} expected a valid {expected} but found float")
  of lkString: err(fmt"{literal.loc} expected a valid {expected} but found string")
  of lkInteger:
    let maybeParsedInt = parseInteger[T](literal.asl)
    if maybeParsedInt.isSome: ok()
    else: err(fmt"{literal.loc} expected a valid {expected} but found `{literal.asl}`")

proc analyzeStringLiteral(literal: Literal): Result[void, string] =
  case literal.kind:
  of lkFloat: err(fmt"{literal.loc} expected a valid string literal but found float")
  of lkInteger: err(fmt"{literal.loc} expected a valid string literal but found integer")
  of lkString: ok()

proc analyzeFloatLiteral[T: SomeFloat](literal: Literal, expected: string): Result[void, string] =
  case literal.kind:
  of lkInteger: err(fmt"{literal.loc} expected a valid {expected} but found integer")
  of lkString: err(fmt"{literal.loc} expected a valid {expected} but found string")
  of lkFloat:
    # Special IEEE-754 values (`nan`, `inf`, `+inf`, `-inf`) are legal
    # in every float type — no fit-check or exact-representability
    # warning applies. The parser (`specialFloatSpec` in literals.nim)
    # narrows the accepted forms; anything else that reached `lkFloat`
    # is numeric.
    if literal.asl in ["nan", "inf", "+inf", "-inf"]:
      return ok()
    let maybeParsedFloat = parseFloat[T](literal.asl)
    if maybeParsedFloat.isNone:
      return err(fmt"{literal.loc} expected a valid {expected} but found `{literal.asl}`")
    # Exact-representability is a warning, not an error: the closest
    # approximation stored in the parsed value is still returned as
    # the literal's value. Emit to stderr with the source location
    # so users can find and (if they choose) rewrite lossy literals
    # as runtime quotients of exact-integer literals.
    # TODO(diagnostics): thread warnings through the analyzer as a
    # collected seq rather than writing to stderr from deep inside
    # the pass.
    const mantissaBits =
      when T is float32: 24
      elif T is float64: 53
    if not isExactlyRepresentable(literal.asl, mantissaBits):
      stderr.writeLine(fmt"[WARN] {literal.loc} literal `{literal.asl}` cannot be exactly represented in {expected}; using closest approximation")
    ok()

proc analyzeLiteral(literalDef: ResolvedLiteralDef, literal: Literal): Result[void, string] =
  case literalDef:
  of rltkF32: analyzeFloatLiteral[float32](literal, "32-bit float")
  of rltkF64: analyzeFloatLiteral[float64](literal, "64-bit float")
  of rltkPointer: err(fmt"{literal.loc} todo: analyze literal Pointer literal argument")
  of rltkU8: analyzeIntegerLiteral[uint8](literal, "8-bit unsigned integer")
  of rltkU16: analyzeIntegerLiteral[uint16](literal, "16-bit unsigned integer")
  of rltkU32: analyzeIntegerLiteral[uint32](literal, "32-bit unsigned integer")
  of rltkU64: analyzeIntegerLiteral[uint64](literal, "64-bit unsigned integer")
  of rltkI8: analyzeIntegerLiteral[int8](literal, "8-bit signed integer")
  of rltkI16: analyzeIntegerLiteral[int16](literal, "16-bit signed integer")
  of rltkI32: analyzeIntegerLiteral[int32](literal, "32-bit signed integer")
  of rltkI64: analyzeIntegerLiteral[int64](literal, "64-bit signed integer")
  of rltkString: literal.analyzeStringLiteral()

proc analyzeVariable*(scope: AnalyzedFunctionScope, variable: Identifier): Result[AnalyzedVariable, string] =
  if variable in scope: ok(newAnalyzedVariable(variable, scope[variable]))
  else: err(fmt"{variable.loc} variable `{variable.asl}` does not exist in scope")

proc analyzeGetter*(appDef: AnalyzedAppDefinition, app: ResolvedApp, file: ResolvedFile, fileScope: ResolvedFileScope, module: ResolvedModule, funcScope: AnalyzedFunctionScope, getter: ResolvedGetter): Result[AnalyzedGetter, string] =
  if getter.source notin funcScope:
    err(fmt"{getter.loc} variable `{getter.source.asl}` is not present in scope")
  else:
    let analyzedSourceArgType = funcScope[getter.source]
    let struct = ? extractStructFor(appDef, analyzedSourceArgType, getter.loc)
    let property = ? struct.findField(getter.property)
    # TODO: coerce the property type from the generic to concrete
    ok(newAnalyzedGetter(getter, analyzedSourceArgType, property.resolved, property.argType))

proc analyzeLiteralInitializer*(appDef: AnalyzedAppDefinition, app: ResolvedApp, file: ResolvedFile, fileScope: ResolvedFileScope, module: ResolvedModule, funcScope: AnalyzedFunctionScope, init: ResolvedLiteralInitializer): Result[AnalyzedLiteralInitializer, string] =
  let analyzedArgType = ? analyzeArgumentType(app, file, fileScope, module, init.argType)
  let argDefModule = ? findModuleDef(appDef, analyzedArgType, init.loc)
  let argDefData = ? extractDataDef(argDefModule, init.loc)
  case argDefData.kind:
  of adkStruct: err(fmt"{init.loc} statement expects a literal initializer `{argDefModule.name.asl}`")
  of adkUnion: err(fmt"{init.loc} statement expects a literal initializer `{argDefModule.name.asl}`")
  of adkLiteral:
    let maybeValidLiteral = analyzeLiteral(argDefData.literal.resolved, init.literal)
    if maybeValidLiteral.isOk: ok(newAnalyzedLiteralInitializer(init.literal, analyzedArgType))
    else: err(maybeValidLiteral.error)

# Forward declarations for the analyzeX procs in the cluster.
proc analyzeExpression*(appDef: AnalyzedAppDefinition, app: ResolvedApp, file: ResolvedFile, fileScope: ResolvedFileScope, module: ResolvedModule, funcScope: AnalyzedFunctionScope, expression: ResolvedExpression, expected: Option[AnalyzedArgumentType]): Result[AnalyzedExpression, string]

proc analyzeStatement*(appDef: AnalyzedAppDefinition, app: ResolvedApp, file: ResolvedFile, fileScope: ResolvedFileScope, module: ResolvedModule, funcScope: AnalyzedFunctionScope, statement: ResolvedStatement): Result[AnalyzedStatement, string]

proc analyzeValueTypeAgainstDefType(app: ResolvedApp, file: ResolvedFile, fileScope: ResolvedFileScope, defType: AnalyzedArgumentType, valType: AnalyzedArgumentType, loc: Location): Result[GenericImplMap, string]

proc analyzeValueTypeAgainstDefType(app: ResolvedApp, file: ResolvedFile, fileScope: ResolvedFileScope, defType: AnalyzedModuleArgumentType, valType: AnalyzedModuleArgumentType, loc: Location): Result[GenericImplMap, string] =
  if defType.module != valType.module:
    err(fmt"{loc} expected `{defType.name.asl}` but found `{valType.name.asl}`")
  else:
    var genericImplMap: GenericImplMap
    for (defImpl, valImpl) in zip(defType.impls, valType.impls):
      let valGenericImplMap = ? analyzeValueTypeAgainstDefType(app, file, fileScope, defImpl, valImpl, loc)
      genericImplMap = ? genericImplMap.merge(valGenericImplMap)
    ok(genericImplMap)

proc analyzeValueTypeAgainstDefType(app: ResolvedApp, file: ResolvedFile, fileScope: ResolvedFileScope, defType: AnalyzedModuleArgumentType, valType: AnalyzedArgumentType, loc: Location): Result[GenericImplMap, string] =
  case valType.kind:
  of aatkGeneric:
    err(fmt"{loc} expected a module {defType.asl} type but found generic type {valType.asl}")
  of aatkModule:
    analyzeValueTypeAgainstDefType(app, file, fileScope, defType, valType.module, loc)

proc analyzeValueTypeAgainstDefType(app: ResolvedApp, file: ResolvedFile, fileScope: ResolvedFileScope, defType: AnalyzedGenericArgumentType, valType: AnalyzedArgumentType, loc: Location): Result[GenericImplMap, string] =
  let funcDefs = defType.resolved.concreteImpls(valType.self)
  for funcDef in funcDefs:
    case valType.kind:
    of aatkGeneric:
      let maybeConcreteFuncDef = valType.generic.resolved.findFunctionDef(funcDef)
      if maybeConcreteFuncDef.isNone:
        return err(fmt"{loc} type `{valType.name.asl}` does not implement function `{funcDef.name.asl}` to support `{defType.resolved.name.asl}`")
    of aatkModule:
      let maybeConcreteFuncDef = valType.module.module.findFunctionDef(funcDef)
      if maybeConcreteFuncDef.isNone:
        return err(fmt"{loc} type `{valType.name.asl}` does not implement function `{funcDef.name.asl}` to support `{defType.resolved.name.asl}`")
  var genericImplMap: GenericImplMap
  genericImplMap[defType.resolved] = valType
  ok(genericImplMap)

# TODO: Return a map of generic -> argType from the recursive analysis
proc analyzeValueTypeAgainstDefType(app: ResolvedApp, file: ResolvedFile, fileScope: ResolvedFileScope, defType: AnalyzedArgumentType, valType: AnalyzedArgumentType, loc: Location): Result[GenericImplMap, string] =
  case defType.kind:
  of aatkModule: analyzeValueTypeAgainstDefType(app, file, fileScope, defType.module, valType, loc)
  of aatkGeneric: analyzeValueTypeAgainstDefType(app, file, fileScope, defType.generic, valType, loc)

proc analyzeArgumentList*(appDef: AnalyzedAppDefinition, app: ResolvedApp, file: ResolvedFile, fileScope: ResolvedFileScope, module: ResolvedModule, funcScope: AnalyzedFunctionScope, argValues: seq[AnalyzedExpression], analyzedFuncDef: AnalyzedFunctionDefinition): Result[GenericImplMap, string] =
  # Reads pre-analyzed args directly from the AnalyzedFunctionDefinition
  # — no lookup, no re-analysis. Every analyzed expression carries a
  # concrete argType post-Approach C; bare literals adopt the caller's
  # expected type or default to i32/f32/String at the
  # analyzeBareLiteral site. Per-candidate type context is threaded
  # from `analyzeFunctionCall`.
  assert(analyzedFuncDef.args.len == argValues.len,
    fmt"BUG: analyzeArgumentList arity mismatch — funcDef has {analyzedFuncDef.args.len} args, call site passed {argValues.len}. zip would silently truncate; fix by erroring (or relying on resolver / overload selection).")
  var genericImplMap: GenericImplMap
  for (analyzedArgDef, argValue) in zip(analyzedFuncDef.args, argValues):
    let argGenericImplMap = ? analyzeValueTypeAgainstDefType(app, file, fileScope, analyzedArgDef.argType, argValue.argType, argValue.loc)
    genericImplMap = ? genericImplMap.merge(argGenericImplMap)
  ok(genericImplMap)

proc analyzeArgumentList(appDef: AnalyzedAppDefinition, app: ResolvedApp, file: ResolvedFile, fileScope: ResolvedFileScope, module: ResolvedModule, funcScope: AnalyzedFunctionScope, fncall: ResolvedFunctionCall, funcDefs: seq[AnalyzedFunctionDefinition]): Result[(AnalyzedFunctionDefinition, seq[AnalyzedExpression], GenericImplMap), string] =
  # Per-candidate analysis over pre-analyzed AnalyzedFunctionDefinition
  # candidates: for each candidate, walk the call's raw arguments and
  # analyze each with the candidate's declared arg type (pre-analyzed)
  # as the expected context. Bare literals adopt the declared type when
  # concrete, or default to i32/f32/String otherwise
  # (`analyzeBareLiteral`). First candidate whose args analyze +
  # type-check wins; ambiguity fires the existing multi-match error
  # path.
  var matches: seq[(AnalyzedFunctionDefinition, seq[AnalyzedExpression], GenericImplMap)]
  var errors: seq[string]
  for index, analyzedFuncDef in funcDefs:
    var analyzedArgs: seq[AnalyzedExpression]
    var candidateErr = ""
    for i in 0..<fncall.args.len:
      let maybeAnalyzed = analyzeExpression(appDef, app, file, fileScope, module, funcScope, fncall.args[i], some(analyzedFuncDef.args[i].argType))
      if maybeAnalyzed.isErr:
        candidateErr = maybeAnalyzed.error
        break
      analyzedArgs.add(maybeAnalyzed.get)
    if candidateErr.len > 0:
      errors.add(fmt"[{index + 1}] - {candidateErr}")
      errors.add("\t" & fmt"{analyzedFuncDef.loc}: {analyzedFuncDef.asl}")
      continue
    let maybeGenericImplMap = analyzeArgumentList(appDef, app, file, fileScope, module, funcScope, analyzedArgs, analyzedFuncDef)
    if maybeGenericImplMap.isOk:
      matches.add((analyzedFuncDef, analyzedArgs, maybeGenericImplMap.get))
    else:
      errors.add(fmt"[{index + 1}] - " & maybeGenericImplMap.error)
      errors.add("\t" & fmt"{analyzedFuncDef.loc}: {analyzedFuncDef.asl}")

  if matches.len == 1:
    ok(matches[0])
  else:
    var message: seq[string]
    if matches.len == 0:
      message.add(fmt"{fncall.loc} failed to find matching function:")
    else:
      message.add(fmt"{fncall.loc} ambiguous function call — multiple candidates match:")
    message.add(errors)
    err(message.join("\n"))

proc analyzeFunctionCall*(appDef: AnalyzedAppDefinition, app: ResolvedApp, file: ResolvedFile, fileScope: ResolvedFileScope, module: ResolvedModule, funcScope: AnalyzedFunctionScope, fncall: ResolvedFunctionCall): Result[AnalyzedFunctionCall, string] =
  let typ = ? fileScope.findType(fncall.parsed.root, fncall.loc)
  let public =
    case typ.kind:
    of rdtkModule: (module != typ.module)
    of rdtkGeneric: true # generic func defs are not required to be explicitly marked public
  let definedType = ? appDef.findDefinedType(typ)
  let funcDefs = ? definedType.findFunctionDefs(fncall.parsed.name, fncall.parsed.args.len, public)

  let (matchingFuncDef, analyzedArgs, genericImpls) = ? analyzeArgumentList(appDef, app, file, fileScope, module, funcScope, fncall, funcDefs)
  # Return type comes pre-analyzed from the AnalyzedFunctionDefinition;
  # apply the caller's inferred generic-impl substitution to concretize
  # any free generics the return type touches.
  let concreteReturns = matchingFuncDef.returns.concrete(genericImpls)
  ok(newAnalyzedFunctionCall(fncall, matchingFuncDef.resolved, analyzedArgs, concreteReturns))

proc analyzeCaseBlock*(appDef: AnalyzedAppDefinition, app: ResolvedApp, file: ResolvedFile, fileScope: ResolvedFileScope, module: ResolvedModule, funcScope: AnalyzedFunctionScope, caseBlock: ResolvedCaseBlock, subjectType: AnalyzedArgumentType, union: ResolvedUnionDef, subjectImpls: seq[AnalyzedArgumentType]): Result[AnalyzedCaseBlock, string] =
  let analyzedCasePattern = ? analyzeCasePattern(appDef, app, file, fileScope, module, funcScope, caseBlock.pattern, subjectType, union, subjectImpls)
  var caseScope = funcScope.clone()
  for binding in analyzedCasePattern.bindings:
    caseScope[binding.name] = binding.argType
  var analyzedStatements: seq[AnalyzedStatement]
  for statement in caseBlock.statements:
    let analyzedStatement = ? analyzeStatement(appDef, app, file, fileScope, module, caseScope, statement)
    analyzedStatements.add(analyzedStatement)
    if analyzedStatement.arg.isSome:
      let newArg = analyzedStatement.arg.get
      caseScope[newArg.name] = newArg.argType
  ok(newAnalyzedCaseBlock(caseBlock, analyzedCasePattern, analyzedStatements))

proc analyzeCaseBlock*(appDef: AnalyzedAppDefinition, app: ResolvedApp, file: ResolvedFile, fileScope: ResolvedFileScope, module: ResolvedModule, funcScope: AnalyzedFunctionScope, caseBlock: ResolvedCaseBlock, subjectType: AnalyzedArgumentType): Result[AnalyzedCaseBlock, string] =
  let analyzedCasePattern = ? analyzeCasePattern(appDef, app, file, fileScope, module, funcScope, caseBlock.pattern, subjectType)
  var caseScope = funcScope.clone()
  for binding in analyzedCasePattern.bindings:
    caseScope[binding.name] = binding.argType
  var analyzedStatements: seq[AnalyzedStatement]
  for statement in caseBlock.statements:
    let analyzedStatement = ? analyzeStatement(appDef, app, file, fileScope, module, caseScope, statement)
    analyzedStatements.add(analyzedStatement)
    if analyzedStatement.arg.isSome:
      let newArg = analyzedStatement.arg.get
      caseScope[newArg.name] = newArg.argType
  ok(newAnalyzedCaseBlock(caseBlock, analyzedCasePattern, analyzedStatements))

proc verifyUniformReturnType(cases: seq[AnalyzedCaseBlock]): Result[void, string] =
  let expected = cases[0].argType
  for c in cases:
    if c.argType != expected:
      return err(fmt"{c.loc} todo: return an error message telling that the case block return types are not same")
  ok()

proc analyzeCases*(appDef: AnalyzedAppDefinition, app: ResolvedApp, file: ResolvedFile, fileScope: ResolvedFileScope, module: ResolvedModule, funcScope: AnalyzedFunctionScope, cases: seq[ResolvedCaseBlock], subjectType: AnalyzedArgumentType, union: ResolvedUnionDef, subjectImpls: seq[AnalyzedArgumentType], loc: Location): Result[seq[AnalyzedCaseBlock], string] =
  var patternScope = newAnalyzedUnionPatternScope(cases.len)
  for id, caseBlock in cases:
    patternScope = ? patternScope.update(id, caseBlock.pattern)

  ? hasUncoveredCases(patternScope, union.variants.len, loc)

  assert(cases.len > 0, "UNREACHABLE: zero-case match should have been caught by the resolver")

  var analyzedCaseBlocks: seq[AnalyzedCaseBlock]
  for caseBlock in cases:
    let analyzedCaseBlock = ? analyzeCaseBlock(appDef, app, file, fileScope, module, funcScope, caseBlock, subjectType, union, subjectImpls)
    analyzedCaseBlocks.add(analyzedCaseBlock)
  ? verifyUniformReturnType(analyzedCaseBlocks)
  ok(analyzedCaseBlocks)

proc analyzeCases*(appDef: AnalyzedAppDefinition, app: ResolvedApp, file: ResolvedFile, fileScope: ResolvedFileScope, module: ResolvedModule, funcScope: AnalyzedFunctionScope, cases: seq[ResolvedCaseBlock], subjectType: AnalyzedArgumentType, literal: ResolvedLiteralDef, loc: Location): Result[seq[AnalyzedCaseBlock], string] =
  var patternScope = ? newAnalyzedLiteralPatternScope(literal, cases.len)
  for id, caseBlock in cases:
    patternScope = ? patternScope.update(id, caseBlock.pattern)

  ? hasUncoveredCases(patternScope, loc)

  assert(cases.len > 0, "UNREACHABLE: zero-case match should have been caught by the resolver")

  var analyzedCaseBlocks: seq[AnalyzedCaseBlock]
  for caseBlock in cases:
    let analyzedCaseBlock = ? analyzeCaseBlock(appDef, app, file, fileScope, module, funcScope, caseBlock, subjectType)
    analyzedCaseBlocks.add(analyzedCaseBlock)
  ? verifyUniformReturnType(analyzedCaseBlocks)
  ok(analyzedCaseBlocks)

proc analyzeMatchExpression*(appDef: AnalyzedAppDefinition, app: ResolvedApp, file: ResolvedFile, fileScope: ResolvedFileScope, module: ResolvedModule, funcScope: AnalyzedFunctionScope, match: ResolvedMatchExpression): Result[AnalyzedMatchExpression, string] =
  let analyzedSubjectExpr = ? analyzeExpression(appDef, app, file, fileScope, module, funcScope, match.subject, none(AnalyzedArgumentType))
  let subjectArgType = analyzedSubjectExpr.argType
  let analyzedSubjectDataType = ? extractDataDef(appDef, subjectArgType, analyzedSubjectExpr.loc)
  case analyzedSubjectDataType.kind:
  of adkStruct:
    err(fmt"{match.loc} match block only supports literal and union types but subject expression returns `{subjectArgType.name.asl}` a struct type")
  of adkLiteral:
    if match.cases.len == 0:
      err(fmt"{match.loc} UNREACHABLE: match block does not contain any case blocks")
    else:
      let analyzedCases = ? analyzeCases(appDef, app, file, fileScope, module, funcScope, match.cases, subjectArgType, analyzedSubjectDataType.literal.resolved, match.loc)
      ok(newAnalyzedMatchExpression(match, analyzedSubjectExpr, analyzedCases, analyzedCases[0].argType))
  of adkUnion:
    if match.cases.len == 0:
      err(fmt"{match.loc} UNREACHABLE: match block does not contain any case blocks")
    else:
      case subjectArgType.kind:
      of aatkGeneric:
        err(fmt"{match.loc} UNREACHABLE: match block does not support generic types in subject expression")
      of aatkModule:
        let impls = subjectArgType.module.impls
        let analyzedCases = ? analyzeCases(appDef, app, file, fileScope, module, funcScope, match.cases, subjectArgType, analyzedSubjectDataType.union.resolved, impls, match.loc)
        ok(newAnalyzedMatchExpression(match, analyzedSubjectExpr, analyzedCases, analyzedCases[0].argType))

proc analyzeKeywordArgument*(appDef: AnalyzedAppDefinition, app: ResolvedApp, file: ResolvedFile, fileScope: ResolvedFileScope, module: ResolvedModule, funcScope: AnalyzedFunctionScope, kwarg: ResolvedKeywordArgument, analyzedField: ResolvedArgumentDef, analyzedFieldArgType: AnalyzedArgumentType): Result[AnalyzedKeywordArgument, string] =
  # Field's declared type is the expected context — bare literals in
  # kwarg values adapt when concrete, default when generic.
  let analyzedExpression = ? analyzeExpression(appDef, app, file, fileScope, module, funcScope, kwarg.expression, some(analyzedFieldArgType))
  # TODO: Utilize the returned generic impl map
  discard ? analyzeValueTypeAgainstDefType(app, file, fileScope, analyzedFieldArgType, analyzedExpression.argType, analyzedExpression.loc)
  ok(newAnalyzedKeywordArgument(kwarg, analyzedField, analyzedExpression))

proc receiverArgType(receiver: ResolvedModule): AnalyzedArgumentType =
  ## Builds an AnalyzedArgumentType pointing at the receiver module with
  ## no impls. Used for default-kind struct initializers and union
  ## initializers (where impls live in the analyzer's deferred-inference
  ## thread, not at the call site).
  let resolvedSelfArg = receiver.self
  let analyzedModuleArg = newAnalyzedModuleArgumentType(resolvedSelfArg, receiver)
  newAnalyzedArgumentType(analyzedModuleArg)

proc analyzeUnionRef(appDef: AnalyzedAppDefinition, app: ResolvedApp, file: ResolvedFile, fileScope: ResolvedFileScope, module: ResolvedModule, unionRef: ResolvedUnionRef): Result[AnalyzedUnionRef, string] =
  ## Walks the resolver's already-checked `impls` seq once and
  ## produces the analyzer-side equivalents. Empty in → empty out.
  ## See `analyzeStructRef` for the parser-Module -> ResolvedModule lookup.
  let resolvedModule = ? fileScope.findModuleDef(unionRef.module.name, unionRef.loc)
  var analyzedImpls = newSeq[AnalyzedArgumentType](unionRef.impls.len)
  for i, resolvedImpl in unionRef.impls:
    analyzedImpls[i] = ? analyzeArgumentType(app, file, fileScope, module, resolvedImpl)
  ok(newAnalyzedUnionRef(unionRef, resolvedModule, analyzedImpls))

proc analyzeUnionInitializer*(appDef: AnalyzedAppDefinition, app: ResolvedApp, file: ResolvedFile, fileScope: ResolvedFileScope, module: ResolvedModule, funcScope: AnalyzedFunctionScope, init: ResolvedUnionInitializer): Result[AnalyzedUnionInitializer, string] =
  ## Single code path over the union initializer:
  ## - If the surface form supplied explicit impls, the resolver has
  ##   already threaded them into `analyzedImpls`. We seed implMap
  ##   positionally from that seq up front, then skip the merge-from-
  ##   kwarg step so no inference happens.
  ## - If the surface form was bare, `analyzedImpls` is empty. The seed
  ##   loop is a no-op and the kwarg walk accumulates the implMap via
  ##   value-vs-field type matches (leave-as-is).
  ## Result-type construction is a single loop over the union's
  ## genericTypeIndex: fill bound positions from implMap, leave uncovered
  ## positions as free generics for downstream unification.
  let analyzedUnionRef = ? analyzeUnionRef(appDef, app, file, fileScope, module, init.unionRef)
  let receiver = analyzedUnionRef.module
  if receiver.data.isNone:
    return err(fmt"{init.loc} module `{receiver.name.asl}` is not a union")
  let dataDef = receiver.data.get
  case dataDef.kind:
  of rdkLiteral: return err(fmt"{init.loc} module `{receiver.name.asl}` is a literal")
  of rdkStruct: return err(fmt"{init.loc} module `{receiver.name.asl}` is a struct")
  of rdkUnion: discard
  let resolvedUnion = dataDef.union
  let resolvedVariant = ? resolvedUnion.findVariant(init.variant)
  let analyzedImpls = analyzedUnionRef.analyzedImpls
  let hasExplicitImpls = analyzedImpls.len > 0

  # Seed implMap positionally from the resolver-checked explicit impls
  # (empty seq → no-op, preserving the bare/leave-as-is path).
  var implMap: GenericImplMap
  for genericArgType, position in resolvedUnion.genericTypeIndex:
    if position < analyzedImpls.len:
      # `genericArgType.parsed` is the parser-side Generic;
      # GenericImplMap keys on ResolvedGeneric. Translate through
      # analyzeArgumentType so the resolved generic is looked up via
      # the file scope.
      let analyzedGeneric = ? analyzeArgumentType(app, file, fileScope, module, newResolvedArgumentType(genericArgType))
      implMap[analyzedGeneric.generic.resolved] = analyzedImpls[position]

  # Walk kwargs. Substitute the variant's field type via implMap before
  # type-checking — equivalent to direct match on the bare path
  # (implMap seeded from kwargs), full concretization on the explicit-
  # impls path (implMap already seeded, merge-from-kwarg skipped so no
  # inference happens).
  var analyzedKwargs: seq[AnalyzedKeywordArgument]
  for kwarg in init.kwargs:
    let resolvedField = ? resolvedVariant.findField(kwarg.name)
    let analyzedFieldArgType = ? analyzeArgumentType(app, file, fileScope, module, resolvedField.argType)
    # Concretize the field type via the current implMap before analyzing
    # the value so bare-literal kwargs adopt the concrete instantiation
    # when known, and default (i32/f32/String) when the field is still
    # a free generic on the bare path.
    let fieldType = analyzedFieldArgType.concrete(implMap)
    let analyzedExpression = ? analyzeExpression(appDef, app, file, fileScope, module, funcScope, kwarg.expression, some(fieldType))
    let local = ? analyzeValueTypeAgainstDefType(app, file, fileScope, fieldType, analyzedExpression.argType, analyzedExpression.loc)
    if not hasExplicitImpls:
      implMap = ? implMap.merge(local)
    analyzedKwargs.add(newAnalyzedKeywordArgument(kwarg, resolvedField, analyzedExpression))

  # Build the result type. One loop over the union's genericTypeIndex
  # positions: bound positions read from implMap (seeded from explicit
  # impls or accumulated via kwargs), free positions get a fresh
  # AnalyzedGenericArgumentType for downstream unification.
  var impls = newSeq[AnalyzedArgumentType](resolvedUnion.genericTypeIndex.len)
  for genericArgType, position in resolvedUnion.genericTypeIndex:
    let analyzedGeneric = ? analyzeArgumentType(app, file, fileScope, module, newResolvedArgumentType(genericArgType))
    if analyzedGeneric.generic.resolved in implMap:
      impls[position] = implMap[analyzedGeneric.generic.resolved]
    else:
      impls[position] = analyzedGeneric
  let resolvedSelfArg = receiver.self
  let analyzedModuleArg = newAnalyzedModuleArgumentType(resolvedSelfArg, receiver, impls)
  let argType = newAnalyzedArgumentType(analyzedModuleArg)

  ok(newAnalyzedUnionInitializer(init, analyzedUnionRef, argType, resolvedVariant, analyzedKwargs))

proc analyzeStructRef(appDef: AnalyzedAppDefinition, app: ResolvedApp, file: ResolvedFile, fileScope: ResolvedFileScope, module: ResolvedModule, structRef: ResolvedStructRef): Result[AnalyzedStructRef, string] =
  ## Walks the resolver's already-checked `impls` seq once and
  ## produces the analyzer-side equivalents. Empty in → empty out.
  ## The parser Module carried on `structRef.module` is looked up here
  ## into a ResolvedModule via `fileScope.findModuleDef` — the resolver
  ## keeps struct/union refs parser-level to break the ref cycle;
  ## analyzer types can hold the resolved view freely.
  let resolvedModule = ? fileScope.findModuleDef(structRef.module.name, structRef.loc)
  var analyzedImpls = newSeq[AnalyzedArgumentType](structRef.impls.len)
  for i, resolvedImpl in structRef.impls:
    analyzedImpls[i] = ? analyzeArgumentType(app, file, fileScope, module, resolvedImpl)
  ok(newAnalyzedStructRef(structRef, resolvedModule, analyzedImpls))

proc analyzeStructInitializer*(appDef: AnalyzedAppDefinition, app: ResolvedApp, file: ResolvedFile, fileScope: ResolvedFileScope, module: ResolvedModule, funcScope: AnalyzedFunctionScope, init: ResolvedStructInitializer): Result[AnalyzedStructInitializer, string] =
  ## Single code path over the struct initializer. Receiver is the
  ## resolver's already-resolved module; result argType wraps the
  ## analyzedImpls seq (empty when the surface form was bare — matches
  ## the receiverArgType() no-impls shape; non-empty when explicit
  ## impls were supplied and arity+constraint-checked at resolve time).
  ## TODO: Inference for uncovered generic positions on the bare path
  ## still lives with the caller of receiverArgType — folded into the
  ## same seq-based build here.
  let analyzedStructRef = ? analyzeStructRef(appDef, app, file, fileScope, module, init.structRef)
  let receiver = analyzedStructRef.module
  if receiver.data.isNone:
    return err(fmt"{init.loc} module `{receiver.name.asl}` is not a struct")
  let dataDef = receiver.data.get
  case dataDef.kind:
  of rdkLiteral: err(fmt"{init.loc} module `{receiver.name.asl}` is a literal")
  of rdkUnion: err(fmt"{init.loc} module `{receiver.name.asl}` is a union")
  of rdkStruct:
    var analyzedKwargs: seq[AnalyzedKeywordArgument]
    for kwarg in init.kwargs:
      let resolvedField = ? dataDef.struct.findField(kwarg.name)
      let analyzedFieldArgType = ? analyzeArgumentType(app, file, fileScope, module, resolvedField.argType)
      let analyzedKwarg = ? analyzeKeywordArgument(appDef, app, file, fileScope, module, funcScope, kwarg, resolvedField, analyzedFieldArgType)
      analyzedKwargs.add(analyzedKwarg)
    let argType =
      if analyzedStructRef.analyzedImpls.len == 0:
        receiverArgType(receiver)
      else:
        let resolvedSelfArg = receiver.self
        let analyzedModuleArg = newAnalyzedModuleArgumentType(resolvedSelfArg, receiver, analyzedStructRef.analyzedImpls)
        newAnalyzedArgumentType(analyzedModuleArg)
    ok(newAnalyzedStructInitializer(init, analyzedStructRef, argType, analyzedKwargs))

proc analyzeInitializer*(appDef: AnalyzedAppDefinition, app: ResolvedApp, file: ResolvedFile, fileScope: ResolvedFileScope, module: ResolvedModule, funcScope: AnalyzedFunctionScope, init: ResolvedInitializer): Result[AnalyzedInitializer, string] =
  case init.kind:
  of rikLiteral:
    let analyzedLiteralInit = ? analyzeLiteralInitializer(appDef, app, file, fileScope, module, funcScope, init.literal)
    ok(newAnalyzedInitializer(analyzedLiteralInit))
  of rikStruct:
    let analyzedStructInit = ? analyzeStructInitializer(appDef, app, file, fileScope, module, funcScope, init.struct)
    ok(newAnalyzedInitializer(analyzedStructInit))
  of rikUnion:
    let analyzedUnionInit = ? analyzeUnionInitializer(appDef, app, file, fileScope, module, funcScope, init.union)
    ok(newAnalyzedInitializer(analyzedUnionInit))

proc defaultLiteralArgType(fileScope: ResolvedFileScope, literal: Literal): Result[AnalyzedArgumentType, string] =
  ## Look up the default module for a bare-literal kind. Integer → i32,
  ## Float → f32, String → String. The default must be reachable via the
  ## file scope — `@std` auto-injection in .asl files puts these three
  ## in scope; if the caller is analyzing a file that skipped that
  ## injection (or a fixture that omits the type entirely), the lookup
  ## fails with a user-facing error naming the missing default.
  let defaultName = case literal.kind:
    of lkInteger: "i32"
    of lkFloat: "f32"
    of lkString: "String"
  let identResult = newIdentifier(defaultName, literal.loc)
  assert identResult.isOk,
    fmt"BUG: default literal type name `{defaultName}` should always satisfy newIdentifier"
  let ident = identResult.get
  if ident notin fileScope:
    return err(fmt"{literal.loc} bare literal defaults to `{defaultName}` but it is not in scope; ensure `@std` auto-injection or an explicit import brings it in")
  let module = ? fileScope.findModuleDef(ident, literal.loc)
  ok(receiverArgType(module))

proc analyzeBareLiteral(appDef: AnalyzedAppDefinition, app: ResolvedApp, file: ResolvedFile, fileScope: ResolvedFileScope, module: ResolvedModule, funcScope: AnalyzedFunctionScope, literal: Literal, expected: Option[AnalyzedArgumentType]): Result[AnalyzedLiteralInitializer, string] =
  ## Approach C — pick a concrete type for the bare literal.
  ##   - `expected = some(module)`  → adopt the module type. If the
  ##     module's data def is struct/union the caller wrote a literal
  ##     where an initializer was expected → error with a clear message.
  ##   - `expected = some(generic)` → default (the binding contributes
  ##     to the generic-impl map at the call site).
  ##   - `expected = none`          → default (bare assignment / bare
  ##     statement).
  ## Then fit-check the value against the chosen module's literal spec.
  let concreteArgType =
    if expected.isSome and expected.get.kind == aatkModule:
      expected.get
    else:
      ? defaultLiteralArgType(fileScope, literal)
  let argDefModule = ? findModuleDef(appDef, concreteArgType, literal.loc)
  let argDefData = ? extractDataDef(argDefModule, literal.loc)
  case argDefData.kind:
  of adkStruct: err(fmt"{literal.loc} expected a struct initializer of type `{argDefModule.name.asl}` but found bare literal")
  of adkUnion: err(fmt"{literal.loc} expected a union initializer of type `{argDefModule.name.asl}` but found bare literal")
  of adkLiteral:
    ? analyzeLiteral(argDefData.literal.resolved, literal)
    ok(newAnalyzedLiteralInitializer(literal, concreteArgType))

proc analyzeExpression*(appDef: AnalyzedAppDefinition, app: ResolvedApp, file: ResolvedFile, fileScope: ResolvedFileScope, module: ResolvedModule, funcScope: AnalyzedFunctionScope, expression: ResolvedExpression, expected: Option[AnalyzedArgumentType]): Result[AnalyzedExpression, string] =
  case expression.kind:
  of rekLiteral:
    let bareLit = ? analyzeBareLiteral(appDef, app, file, fileScope, module, funcScope, expression.literal, expected)
    ok(newAnalyzedExpression(newAnalyzedInitializer(bareLit)))
  of rekVariable:
    let analyzedVariable = ? analyzeVariable(funcScope, expression.variable)
    ok(newAnalyzedExpression(analyzedVariable))
  of rekGetter:
    let analyzedGetter = ? analyzeGetter(appDef, app, file, fileScope, module, funcScope, expression.getter)
    ok(newAnalyzedExpression(analyzedGetter))
  of rekInitializer:
    let analyzedInit = ? analyzeInitializer(appDef, app, file, fileScope, module, funcScope, expression.init)
    ok(newAnalyzedExpression(analyzedInit))
  of rekFunctionCall:
    let analyzedFunctionCall = ? analyzeFunctionCall(appDef, app, file, fileScope, module, funcScope, expression.fncall)
    ok(newAnalyzedExpression(analyzedFunctionCall))
  of rekMatchExpr:
    let analyzedMatchExpr = ? analyzeMatchExpression(appDef, app, file, fileScope, module, funcScope, expression.match)
    ok(newAnalyzedExpression(analyzedMatchExpr))

proc analyzeAssignment*(appDef: AnalyzedAppDefinition, app: ResolvedApp, file: ResolvedFile, fileScope: ResolvedFileScope, module: ResolvedModule, funcScope: AnalyzedFunctionScope, assignment: ResolvedAssignment): Result[AnalyzedAssignment, string] =
  let analyzedExpr = ? analyzeExpression(appDef, app, file, fileScope, module, funcScope, assignment.expression, none(AnalyzedArgumentType))
  ok(newAnalyzedAssignment(assignment, analyzedExpr))

proc analyzeSetter*(appDef: AnalyzedAppDefinition, app: ResolvedApp, file: ResolvedFile, fileScope: ResolvedFileScope, module: ResolvedModule, funcScope: AnalyzedFunctionScope, setter: ResolvedSetter): Result[AnalyzedSetter, string] =
  let analyzedGetter = ? analyzeGetter(appDef, app, file, fileScope, module, funcScope, setter.getter)
  # RHS must match the getter's field type — thread that as expected.
  let analyzedExpression = ? analyzeExpression(appDef, app, file, fileScope, module, funcScope, setter.expression, some(analyzedGetter.argType))
  # TODO: Ensure that the getter field type and the expression type are same
  ok(newAnalyzedSetter(setter, analyzedGetter, analyzedExpression))

proc analyzeStatement*(appDef: AnalyzedAppDefinition, app: ResolvedApp, file: ResolvedFile, fileScope: ResolvedFileScope, module: ResolvedModule, funcScope: AnalyzedFunctionScope, statement: ResolvedStatement): Result[AnalyzedStatement, string] =
  case statement.kind:
  of rskExpr:
    let analyzedExpr = ? analyzeExpression(appDef, app, file, fileScope, module, funcScope, statement.expression, none(AnalyzedArgumentType))
    ok(newAnalyzedStatement(analyzedExpr))
  of rskAssignment:
    let analyzedAssignment = ? analyzeAssignment(appDef, app, file, fileScope, module, funcScope, statement.assignment)
    ok(newAnalyzedStatement(analyzedAssignment))
  of rskSetter:
    let analyzedMutation = ? analyzeSetter(appDef, app, file, fileScope, module, funcScope, statement.setter)
    ok(newAnalyzedStatement(analyzedMutation))

proc analyzeUserFunction*(appDef: AnalyzedAppDefinition, app: ResolvedApp, file: ResolvedFile, fileScope: ResolvedFileScope, module: ResolvedModule, function: ResolvedUserFunction): Result[AnalyzedUserFunction, string] =
  ## Seeds funcScope from the resolved arg definitions (converting each
  ## resolved argType to the analyzer-side AnalyzedArgumentType in the
  ## calling module context), then walks statements.
  var funcScope: AnalyzedFunctionScope
  for argDef in function.def.args:
    let analyzedArgType = ? analyzeArgumentType(app, file, fileScope, module, argDef.argType)
    funcScope[argDef.name] = analyzedArgType

  var analyzedStatements: seq[AnalyzedStatement]
  for statement in function.statements:
    let analyzedStatement = ? analyzeStatement(appDef, app, file, fileScope, module, funcScope, statement)
    analyzedStatements.add(analyzedStatement)
    if analyzedStatement.arg.isSome:
      let newArg = analyzedStatement.arg.get
      funcScope[newArg.name] = newArg.argType

  if function.statements.len == 0:
    err(fmt"{function.loc} UNREACHABLE: should have been caught by the resolver")
  else:
    let analyzedReturns = ? analyzeArgumentType(app, file, fileScope, module, function.def.returns)
    if analyzedStatements[^1].argType != analyzedReturns:
      err(fmt"{function.statements[^1].loc} function does not return the expected return type")
    else:
      ok(newAnalyzedUserFunction(function, function.def, analyzedStatements))

proc analyzeModule*(appDef: AnalyzedAppDefinition, app: ResolvedApp, file: ResolvedFile, fileScope: ResolvedFileScope, module: ResolvedModule): Result[AnalyzedModule, string] =
  var analyzedFunctions: seq[AnalyzedFunction]
  for function in module.functions:
    case function.kind:
    of rfkExtern:
      analyzedFunctions.add(newAnalyzedFunction(newAnalyzedExternFunction(function.extern, function.def)))
    of rfkUser:
      let analyzedUserFunction = ? analyzeUserFunction(appDef, app, file, fileScope, module, function.user)
      analyzedFunctions.add(newAnalyzedFunction(analyzedUserFunction))
  ok(newAnalyzedModule(module, analyzedFunctions))

proc analyzeImportedType*(app: ResolvedApp, impFile: ResolvedFile, impType: ResolvedImportedType): Result[AnalyzedImportedType, string] =
  let maybeImportedType = impFile.findType(impType.typ.name)
  if maybeImportedType.isErr:
    err(fmt"{impType.loc} type `{impType.typ.name.asl}` is not defined in the file")
  else:
    ok(newAnalyzedImportedType(impType, maybeImportedType.get))

proc analyzeImportDefinition*(app: ResolvedApp, file: ResolvedFile, imp: ResolvedImport): Result[AnalyzedImportDefinition, string] =
  let maybeImportedFile = app.findFile(imp.impFile)
  if maybeImportedFile.isNone:
    err(fmt"{imp.loc} UNREACHABLE: file `{imp.impFile.path}` does not exist")
  else:
    let analyzedImpFile = maybeImportedFile.get
    var importedTypes: seq[AnalyzedImportedType]
    for impType in imp.importedTypes:
      let analyzedImportedType = ? analyzeImportedType(app, analyzedImpFile, impType)
      importedTypes.add(analyzedImportedType)
    ok(newAnalyzedImportDefinition(imp, importedTypes))

proc analyzeFile(appDef: AnalyzedAppDefinition, app: ResolvedApp, file: ResolvedFile): Result[AnalyzedFile, string] =
  ## Build the fileScope from imports (name → resolved defined type in
  ## the imported file) + this file's own defined types, then drive
  ## per-module body analysis.
  var analyzedImports: seq[AnalyzedImportDefinition]
  for imp in file.imports:
    let analyzedImport = ? analyzeImportDefinition(app, file, imp)
    analyzedImports.add(analyzedImport)

  let (fileScope, _) = ? newResolvedFileScope(analyzedImports, file.types)
  var analyzedModules: seq[AnalyzedModule]
  for typ in file.types:
    case typ.kind:
    of rdtkGeneric: discard # generics are already resolved since it is only a definition type
    of rdtkModule:
      let analyzedModule = ? analyzeModule(appDef, app, file, fileScope, typ.module)
      analyzedModules.add(analyzedModule)
  ok(newAnalyzedFile(file, analyzedImports, analyzedModules))

proc analyze*(app: ResolvedApp): Result[AnalyzedApp, string] =
  ## Two-pass orchestration (W8a/W8b of plan_analyzer_two_pass.md).
  ##
  ## Pass 1 — `analyzeAppDefinition(app)` — walks every file, every
  ##   module + generic, every struct/union/literal, every funcDef
  ##   signature across the whole app. Any def-site error (malformed
  ##   requires, bad signature, missing impl-satisfies-generic) fires
  ##   here before any body walker touches the AST — the guarantee
  ##   phase A always gave us.
  ##
  ## Pass 2 — the existing per-file `analyzeFile` walk — analyzes
  ##   each function body. As of W8b the AnalyzedAppDefinition from
  ##   pass 1 is threaded through every body walker; call sites read
  ##   pre-analyzed funcDef signatures via
  ##   `appDef.findFunctionDef(funcDef)` inside `analyzeArgumentList`
  ##   instead of re-analyzing per candidate.
  let appDef = ? analyzeAppDefinition(app)
  var analyzedFiles: seq[AnalyzedFile]
  for file in app.files:
    let analyzedFile = ? analyzeFile(appDef, app, file)
    analyzedFiles.add(analyzedFile)
  ok(newAnalyzedApp(app, analyzedFiles))