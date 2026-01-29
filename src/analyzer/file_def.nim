import results, strformat, tables, hashes, sets

import resolver
import module_ref
import func_def
import module_def

type AnalyzedFileDefinition* = ref object of RootObj
  file: ResolvedFile
  modules_repo: Repo[ResolvedModule, AnalyzedModuleDefinition]
  function_defs_repo: Repo[ResolvedFunctionDefinition, AnalyzedFunctionDefinition]
  function_signatures_map: Table[Identifier, Table[uint,
      seq[AnalyzedFunctionDefinition]]]

proc new_analyzed_file_definition(file: ResolvedFile, modules: seq[
    AnalyzedModuleDefinition], function_defs: seq[
    AnalyzedFunctionDefinition]): Result[AnalyzedFileDefinition, string] =
  let maybe_modules_repo = new_repo(modules, resolved_module)
  if maybe_modules_repo.is_err: return err("new_analyzed_file_definition UNREACHABLE")
  let modules_repo = maybe_modules_repo.get

  let maybe_function_defs_repo = new_repo(function_defs, resolved_def)
  if maybe_function_defs_repo.is_err: return err("new_analyzed_file_definition UNREACHABLE")
  let function_defs_repo = maybe_function_defs_repo.get

  var function_signatures_map: Table[Identifier, Table[uint, seq[
      AnalyzedFunctionDefinition]]]
  for analyzed_function_def in function_defs:
    if analyzed_function_def.name notin function_signatures_map:
      function_signatures_map[analyzed_function_def.name] = init_table[uint,
          seq[AnalyzedFunctionDefinition]]()
    if analyzed_function_def.arity notin function_signatures_map[
        analyzed_function_def.name]:
      function_signatures_map[analyzed_function_def.name][
          analyzed_function_def.arity] = new_seq[
              AnalyzedFunctionDefinition]()
    function_signatures_map[analyzed_function_def.name][
          analyzed_function_def.arity].add(analyzed_function_def)

  ok(AnalyzedFileDefinition(file: file, modules_repo: modules_repo,
      function_defs_repo: function_defs_repo,
      function_signatures_map: function_signatures_map))

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
  let maybe_module = file_def.modules_repo.find(module)
  if maybe_module.is_ok: ok(maybe_module.get)
  else: err(fmt"module `{module.name.asl}` not found in analyzed file definition")

proc find_function_def*(file_def: AnalyzedFileDefinition,
    def: ResolvedFunctionDefinition): Result[AnalyzedFunctionDefinition, string] =
  let maybe_function_def = file_def.function_defs_repo.find(def)
  if maybe_function_def.is_ok: ok(maybe_function_def.get)
  else: err(fmt"def `{def.name.asl}` not found in analyzed file definition")

proc find_function_defs*(file_def: AnalyzedFileDefinition, name: Identifier,
    arity: uint): Result[seq[AnalyzedFunctionDefinition], string] =
  if name notin file_def.function_signatures_map:
    err(fmt"function `{name.asl}` not found in analyzed file definition")
  elif arity notin file_def.function_signatures_map[name]:
    err(fmt"function `{name.asl}` with arity `{arity}` not found in analyzed file definition")
  else:
    ok(file_def.function_signatures_map[name][arity])

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
