import results, strformat, tables, hashes, sets

import resolver
import module_ref
import func_def
import module_def

type AnalyzedFileDefinition* = ref object of RootObj
  file: ResolvedFile
  modules_repo: Repo[AnalyzedModuleDefinition]
  function_defs_repo: Repo[AnalyzedFunctionDefinition]

proc new_analyzed_file_definition(file: ResolvedFile, modules: seq[
    AnalyzedModuleDefinition], function_defs: seq[
    AnalyzedFunctionDefinition]): Result[AnalyzedFileDefinition, string] =
  let maybe_modules_repo = new_repo(modules, @[new_index[
      AnalyzedModuleDefinition]("name", resolved_module, true)])
  if maybe_modules_repo.is_err: return err("new_analyzed_file_definition UNREACHABLE")
  let modules_repo = maybe_modules_repo.get

  let maybe_function_defs_repo = new_repo(function_defs, @[
    new_index[AnalyzedFunctionDefinition]("def", resolved_def, true),
    new_index[AnalyzedFunctionDefinition]("name_and_arity", proc(
        def: AnalyzedFunctionDefinition): (Identifier, uint) = (def.name,
        def.arity)),
  ])
  if maybe_function_defs_repo.is_err: return err("new_analyzed_file_definition UNREACHABLE")
  let function_defs_repo = maybe_function_defs_repo.get

  ok(AnalyzedFileDefinition(file: file, modules_repo: modules_repo,
      function_defs_repo: function_defs_repo))

proc file*(def: AnalyzedFileDefinition): ResolvedFile = def.file
proc modules*(def: AnalyzedFileDefinition): seq[
    AnalyzedModuleDefinition] = def.modules_repo.items
proc function_defs*(def: AnalyzedFileDefinition): seq[
    AnalyzedFunctionDefinition] =
  def.function_defs_repo.items

proc generic_impls*(file: AnalyzedFileDefinition): Table[ResolvedModule, seq[
    HashSet[AnalyzedImpl]]] =
  var impl_set: Table[ResolvedModule, seq[HashSet[AnalyzedImpl]]]
  for module in file.modules: impl_set = impl_set.merge(
      module.generic_impls())
  for function_def in file.function_defs:
    impl_set = impl_set.merge(function_def.generic_impls())
  return impl_set

proc h*(file: AnalyzedFileDefinition): seq[string] =
  var lines: seq[string]
  for module in file.modules:
    lines.add(module.h)
  for fndef in file.function_defs:
    lines.add(fndef.h)
  return lines

proc c*(file: AnalyzedFileDefinition): seq[string] =
  var lines: seq[string]
  for module in file.modules:
    lines.add(module.c)
  return lines

proc find_module_def*(file_def: AnalyzedFileDefinition,
    module: ResolvedModule): Result[AnalyzedModuleDefinition, string] =
  let maybe_module = file_def.modules_repo.find("name", module)
  if maybe_module.is_ok: ok(maybe_module.get[0])
  else: err(fmt"module `{module.name.asl}` not found in analyzed file definition")

proc find_function_def*(file_def: AnalyzedFileDefinition,
    def: ResolvedFunctionDefinition): Result[AnalyzedFunctionDefinition, string] =
  let maybe_function_def = file_def.function_defs_repo.find("def", def)
  if maybe_function_def.is_ok: ok(maybe_function_def.get[0])
  else: err(fmt"def `{def.name.asl}` not found in analyzed file definition")

proc find_function_defs*(file_def: AnalyzedFileDefinition, name: Identifier,
    arity: uint): Result[seq[AnalyzedFunctionDefinition], string] =
  let maybe_def = file_def.function_defs_repo.find("name_and_arity", (name, arity))
  if maybe_def.is_err:
    err(fmt"function `{name.asl}` with arity `{arity}` not found in analyzed file definition")
  else:
    ok(maybe_def.get)

proc analyze_def*(file: ResolvedFile): Result[AnalyzedFileDefinition, string] =
  var modules: seq[AnalyzedModuleDefinition]
  for module in file.modules:
    let analyzed_module_def = ? analyze_def(file, module)
    modules.add(analyzed_module_def)

  var function_defs: seq[AnalyzedFunctionDefinition]
  for function in file.functions:
    let analyzed_function_def = ? analyze_def(file, function)
    function_defs.add(analyzed_function_def)

  new_analyzed_file_definition(file, modules, function_defs)
