import results, strformat, tables, options, sequtils

import parser
import module
export module

# =============================================================================
# ResolvedFile
# =============================================================================
type ResolvedFile* = ref object of RootObj
  name: string
  indent: int
  maybe_start_def: Option[ResolvedFunctionDefinition]
  modules_map: Table[Module, ResolvedModule]
  modules: seq[ResolvedModule]
  functions: seq[ResolvedFunction]

proc new_resolved_file*(name: string, indent: int, maybe_start_def: Option[
    ResolvedFunctionDefinition], modules: seq[ResolvedModule],
    modules_map: Table[Module, ResolvedModule], functions: seq[
    ResolvedFunction]): ResolvedFile =
  ResolvedFile(name: name, indent: indent, maybe_start_def: maybe_start_def,
      modules_map: modules_map, modules: modules, functions: functions)

proc path*(file: ResolvedFile): string = file.name
proc indent*(file: ResolvedFile): int = file.indent
proc start_def*(file: ResolvedFile): Result[ResolvedFunctionDefinition, string] =
  case file.maybe_start_def.is_some
  of true: ok(file.maybe_start_def.get)
  of false: err(fmt"{file.path} failed to find `start` function")
proc modules*(file: ResolvedFile): seq[
    ResolvedModule] = file.modules
proc functions*(file: ResolvedFile): seq[
    ResolvedFunction] = file.functions.map_it(it)

proc get_resolved_module*(file: ResolvedFile,
    module: parser.Module): Result[ResolvedModule, string] =
  if module in file.modules_map:
    ok(file.modules_map[module])
  else:
    err("failed to find module `{module.name.asl}`")

proc find_module*(file: ResolvedFile, module: Module): Result[
    ResolvedModule, string] =
  if module in file.modules_map:
    ok(file.modules_map[module])
  else:
    err("failed to find module `{module.name.asl}`")
