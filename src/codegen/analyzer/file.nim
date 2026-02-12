import results, sequtils, strutils, re

import resolver
import func_def
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

proc def*(file: AnalyzedFile): AnalyzedFileDefinition = file.def
proc start_function_def*(file: AnalyzedFile): AnalyzedFunctionDefinition = file.start_function_def
proc modules*(file: AnalyzedFile): seq[AnalyzedModule] = file.modules
proc functions*(file: AnalyzedFile): seq[AnalyzedUserFunction] = file.functions

proc indent(file: AnalyzedFile): int = file.def.file.indent

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
