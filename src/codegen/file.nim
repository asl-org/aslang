import results, strformat, tables, strutils, sets

import analyzer
import func_def
import file_def
import module
import function

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
