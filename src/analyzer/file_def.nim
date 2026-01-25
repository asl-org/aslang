import results, strformat, tables, hashes, sets

import resolver
import module_ref
import func_def
import module_def

type AnalyzedFileDefinition* = ref object of RootObj
  file: ResolvedFile
  modules: seq[AnalyzedModuleDefinition]
  modules_map: Table[ResolvedModule, AnalyzedModuleDefinition]
  function_defs: seq[AnalyzedFunctionDefinition]
  function_defs_map: Table[ResolvedFunctionDefinition, AnalyzedFunctionDefinition]
  function_signatures_map: Table[Identifier, Table[uint,
      seq[AnalyzedFunctionDefinition]]]

proc new_analyzed_file_definition(file: ResolvedFile, modules: seq[(
    ResolvedModule, AnalyzedModuleDefinition)], function_defs: seq[(
    ResolvedFunctionDefinition,
    AnalyzedFunctionDefinition)]): AnalyzedFileDefinition =
  var modules_map: Table[ResolvedModule, AnalyzedModuleDefinition]
  var analyzedmodules: seq[AnalyzedModuleDefinition]
  for (resolved_module, analyzed_module) in modules:
    modules_map[resolved_module] = analyzed_module
    analyzedmodules.add(analyzed_module)

  var function_defs_map: Table[ResolvedFunctionDefinition, AnalyzedFunctionDefinition]
  var function_signatures_map: Table[Identifier, Table[uint, seq[
      AnalyzedFunctionDefinition]]]
  var analyzed_function_defs: seq[AnalyzedFunctionDefinition]
  for (resolved_function_def, analyzed_function_def) in function_defs:
    function_defs_map[resolved_function_def] = analyzed_function_def
    analyzed_function_defs.add(analyzed_function_def)

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

  AnalyzedFileDefinition(file: file,
      modules: analyzed_modules,
      modules_map: modules_map, function_defs: analyzed_function_defs,
      function_defs_map: function_defs_map,
      function_signatures_map: function_signatures_map)

proc file*(def: AnalyzedFileDefinition): ResolvedFile = def.file
proc modules*(def: AnalyzedFileDefinition): seq[
    AnalyzedModuleDefinition] = def.modules

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
  if module in file_def.modules_map:
    ok(file_def.modules_map[module])
  else:
    err(fmt"module `{module.name.asl}` not found in analyzed file definition")

proc find_function_def*(file_def: AnalyzedFileDefinition,
    def: ResolvedFunctionDefinition): Result[AnalyzedFunctionDefinition, string] =
  if def in file_def.function_defs_map:
    ok(file_def.function_defs_map[def])
  else:
    err(fmt"def `{def.name.asl}` not found in analyzed file definition")

proc find_function_defs*(file_def: AnalyzedFileDefinition, name: Identifier,
    arity: uint): Result[seq[AnalyzedFunctionDefinition], string] =
  if name notin file_def.function_signatures_map:
    err(fmt"function `{name.asl}` not found in analyzed file definition")
  elif arity notin file_def.function_signatures_map[name]:
    err(fmt"function `{name.asl}` with arity `{arity}` not found in analyzed file definition")
  else:
    ok(file_def.function_signatures_map[name][arity])

proc analyze_def*(file: ResolvedFile): Result[AnalyzedFileDefinition, string] =
  var modules: seq[(ResolvedModule, AnalyzedModuleDefinition)]
  for module in file.modules:
    let analyzed_module_def = ? analyze_def(file, module)
    modules.add((module, analyzed_module_def))

  var function_defs: seq[(ResolvedFunctionDefinition,
      AnalyzedFunctionDefinition)]
  for function in file.functions:
    let analyzed_function_def = ? analyze_def(file, function)
    function_defs.add((function.def, analyzed_function_def))

  ok(new_analyzed_file_definition(file, modules, function_defs))
