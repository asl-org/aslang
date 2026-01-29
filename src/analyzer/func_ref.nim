import results, sequtils, strformat, tables, hashes, sets

import resolver
import module_ref
import arg_def
import func_def
import generic
import module_def
import file_def

type FunctionScope* = ref object of RootObj
  table: Table[Identifier, AnalyzedModuleRef]

proc get*(scope: FunctionScope, name: Identifier): Result[AnalyzedModuleRef, string] =
  if name notin scope.table:
    return err(fmt"{name.location} argument `{name.asl}` is not present in the scope")
  ok(scope.table[name])

proc set*(scope: FunctionScope, arg: AnalyzedArgumentDefinition): Result[
    FunctionScope, string] =
  if arg.name in scope.table:
    return err(fmt"{arg.location} argument `{arg.name.asl}` can not be mutated")
  scope.table[arg.name] = arg.module_ref
  ok(scope)

proc clone*(scope: FunctionScope): FunctionScope =
  var table: Table[Identifier, AnalyzedModuleRef]
  for name, module_ref in scope.table:
    table[name] = module_ref
  FunctionScope(table: table)

type
  AnalyzedFunctionRefKind* = enum
    RFRK_LOCAL, RFRK_MODULE
  AnalyzedFunctionRef* = ref object of RootObj
    name: Identifier
    concrete_defs: seq[AnalyzedFunctionDefinition]
    original_defs: seq[AnalyzedFunctionDefinition]
    case kind: AnalyzedFunctionRefKind
    of RFRK_LOCAL: discard
    of RFRK_MODULE: module_ref: AnalyzedModuleRef

proc new_analyzed_function_ref(name: Identifier, original_defs: seq[
    AnalyzedFunctionDefinition], concrete_defs: seq[
    AnalyzedFunctionDefinition]): AnalyzedFunctionRef =
  AnalyzedFunctionRef(kind: RFRK_LOCAL, name: name,
      original_defs: original_defs, concrete_defs: concrete_defs)

proc new_analyzed_function_ref(module_ref: AnalyzedModuleRef, name: Identifier,
    original_defs: seq[AnalyzedFunctionDefinition], concrete_defs: seq[
    AnalyzedFunctionDefinition]): AnalyzedFunctionRef =
  AnalyzedFunctionRef(kind: RFRK_MODULE, module_ref: module_ref, name: name,
      original_defs: original_defs, concrete_defs: concrete_defs)

proc kind*(fnref: AnalyzedFunctionRef): AnalyzedFunctionRefKind = fnref.kind
proc location*(fnref: AnalyzedFunctionRef): Location = fnref.location
proc module_ref*(fnref: AnalyzedFunctionRef): AnalyzedModuleRef =
  do_assert fnref.kind == RFRK_MODULE, "expected a module function ref"
  fnref.module_ref

proc defs*(fnref: AnalyzedFunctionRef): seq[(AnalyzedFunctionDefinition,
    AnalyzedFunctionDefinition)] =
  zip(fnref.original_defs, fnref.concrete_defs)

proc generic_impls*(fnref: AnalyzedFunctionRef): Table[ResolvedModule, seq[
    HashSet[AnalyzedImpl]]] =
  var impl_set: Table[ResolvedModule, seq[HashSet[AnalyzedImpl]]]
  case fnref.kind:
  of RFRK_LOCAL: discard
  of RFRK_MODULE: impl_set = impl_set.merge(fnref.module_ref.generic_impls)
  return impl_set

proc asl*(fnref: AnalyzedFunctionRef): string =
  case fnref.kind:
  of RFRK_LOCAL: fmt"{fnref.name.asl}"
  of RFRK_MODULE: fmt"{fnref.module_ref.asl}.{fnref.name.asl}"

proc analyze*(file_def: AnalyzedFileDefinition,
    module_def: AnalyzedModuleDefinition,
        fnref: ResolvedFunctionRef): Result[
    AnalyzedFunctionRef, string] =
  case fnref.kind:
  of RFRK_LOCAL:
    let analyzed_function_defs = ? file_def.find_function_defs(fnref.name, fnref.arity)
    ok(new_analyzed_function_ref(fnref.name, analyzed_function_defs,
        analyzed_function_defs))
  of RFRK_MODULE:
    let resolved_module_ref = ? fnref.module_ref
    let analyzed_module_ref = ? analyze_def(file_def.file,
        module_def.resolved_module, resolved_module_ref)
    case analyzed_module_ref.kind:
    of AMRK_GENERIC:
      let resolved_generic = analyzed_module_ref.generic
      let analyzed_generic = ? module_def.find_generic(resolved_generic)
      let analyzed_function_defs = ? analyzed_generic.find_function_defs(
          fnref.name, fnref.arity)
      ok(new_analyzed_function_ref(analyzed_module_ref, fnref.name,
          analyzed_function_defs, analyzed_function_defs))
    of AMRK_MODULE:
      let analyzed_module_def = ? file_def.find_module_def(
          analyzed_module_ref.module)
      let analyzed_function_defs = ? analyzed_module_def.find_function_defs(
          fnref.name, fnref.arity, fnref.location)
      let analyzed_concrete_function_defs = analyzed_function_defs.map_it(
          it.concretize(analyzed_module_ref.concrete_map))
      ok(new_analyzed_function_ref(analyzed_module_ref, fnref.name,
          analyzed_function_defs, analyzed_concrete_function_defs))

proc analyze*(file_def: AnalyzedFileDefinition,
    fnref: ResolvedFunctionRef): Result[AnalyzedFunctionRef, string] =
  case fnref.kind:
  of RFRK_LOCAL:
    let analyzed_function_defs = ? file_def.find_function_defs(fnref.name, fnref.arity)
    ok(new_analyzed_function_ref(fnref.name, analyzed_function_defs,
        analyzed_function_defs))
  of RFRK_MODULE:
    let resolved_module_ref = ? fnref.module_ref
    let analyzed_module_ref = ? analyze_def(file_def.file, resolved_module_ref)
    case analyzed_module_ref.kind:
    of AMRK_GENERIC:
      err("{fnref.location} local function calls do not support generics")
    of AMRK_MODULE:
      let analyzed_module_def = ? file_def.find_module_def(
          analyzed_module_ref.module)
      let analyzed_function_defs = ? analyzed_module_def.find_function_defs(
          fnref.name, fnref.arity, fnref.location)
      var analyzed_concrete_function_defs = analyzed_function_defs.map_it(
          it.concretize(analyzed_module_ref.concrete_map))
      ok(new_analyzed_function_ref(analyzed_module_ref, fnref.name,
          analyzed_function_defs, analyzed_concrete_function_defs))
