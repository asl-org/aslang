import results, sequtils, strformat, tables, hashes, strutils, sets, re

import resolver
import module_ref
import func_def
import module_def
import file_def
import function
import module

type AnalyzedFile* = ref object of RootObj
  def: AnalyzedFileDefinition
  start_function_def: AnalyzedFunctionDefinition
  modules: seq[AnalyzedModule]
  functions: seq[AnalyzedUserFunction]

proc new_analyzed_file(def: AnalyzedFileDefinition,
    start_function_def: AnalyzedFunctionDefinition, modules: seq[
    AnalyzedModule], functions: seq[AnalyzedUserFunction]): AnalyzedFile =
  AnalyzedFile(def: def, start_function_def: start_function_def,
      modules: modules, functions: functions)

proc indent(file: AnalyzedFile): int = file.def.file.indent

proc generic_impls*(file: AnalyzedFile): Result[Table[
    AnalyzedModuleDefinition, seq[seq[(AnalyzedModuleDefinition, seq[
    AnalyzedFunctionDefinition])]]], string] =
  var impl_set: Table[ResolvedModule, seq[HashSet[AnalyzedImpl]]]
  impl_set = impl_set.merge(file.def.generic_impls)
  for module in file.modules: impl_set = impl_set.merge(module.generic_impls)
  for function in file.functions: impl_set = impl_set.merge(
      function.generic_impls)

  # Assign index to module for each generic
  var impl_map: Table[AnalyzedModuleDefinition, seq[seq[(
      AnalyzedModuleDefinition, seq[AnalyzedFunctionDefinition])]]]
  for module, children in impl_set.pairs:
    var analyzed_children: seq[seq[(AnalyzedModuleDefinition, seq[
        AnalyzedFunctionDefinition])]]
    for impls in children:
      var analyzed_impls: seq[(AnalyzedModuleDefinition, seq[
          AnalyzedFunctionDefinition])]
      for impl in impls:
        case impl.module_ref.kind:
        of AMRK_GENERIC:
          echo "[INTERNAL ERROR] - If you see this something is seriously wrong"
        of AMRK_MODULE:
          let module_def = ? file.def.find_module_def(
              impl.module_ref.module)
          var analyzed_function_defs: seq[AnalyzedFunctionDefinition]
          for def in impl.defs:
            let analyzed_function_def = ? module_def.find_function_def(def)
            analyzed_function_defs.add(analyzed_function_def)
          analyzed_impls.add((module_def,
              analyzed_function_defs))
      analyzed_children.add(analyzed_impls)

    let analyzed_module_def = ? file.def.find_module_def(module)
    impl_map[analyzed_module_def] = analyzed_children
  return ok(impl_map)

proc asl*(file: AnalyzedFile): string =
  let indent = " ".repeat(file.indent)
  var lines: seq[string]
  for module in file.modules:
    lines.add(module.asl(indent))
    lines.add("\n")
  for function in file.functions:
    lines.add(function.asl(indent))
    lines.add("\n")
  lines.map_it(it.strip(leading = false)).join("\n").replace(re"\n{3,}", "\n\n")

proc c*(file: AnalyzedFile): Result[string, string] =
  var lines: seq[string]
  lines.add(file.def.h)
  lines.add(file.def.c)

  let generic_impls = ? file.generic_impls
  for module in file.modules:
    let impls = generic_impls.get_or_default(module.def, @[])
    lines.add(module.c(impls))
  for function in file.functions:
    lines.add(function.c)

  let code = @[
    "#include \"runtime.h\"\n",
    lines.join("\n"),
    "\n",
    "int main(int argc, char** argv) {",
    fmt"return {file.start_function_def.c_name}(argc);",
    "}"
  ].join("\n")
  ok(code)

proc analyze(file_def: AnalyzedFileDefinition,
    start_function_def: AnalyzedFunctionDefinition): Result[AnalyzedFile, string] =
  var analyzed_modules: seq[AnalyzedModule]
  for module in file_def.file.modules:
    let module_def = ? file_def.find_module_def(module)
    let analyzed_module = ? analyze(file_def, module_def)
    analyzed_modules.add(analyzed_module)

  var analyzed_functions: seq[AnalyzedUserFunction]
  for function in file_def.file.functions:
    let analyzed_function = ? analyze(file_def, function)
    analyzed_functions.add(analyzed_function)
  ok(new_analyzed_file(file_def, start_function_def, analyzed_modules,
      analyzed_functions))

proc analyze*(file: ResolvedFile): Result[AnalyzedFile, string] =
  let analyzed_file_def = ? analyze_def(file)
  let resolved_start_function_def = ? file.start_def
  let analyzed_start_function = ? analyzed_file_def.find_function_def(resolved_start_function_def)

  let analyzed_file = ? analyze(analyzed_file_def, analyzed_start_function)
  ok(analyzed_file)
