import results, strformat, tables, options, sequtils

import parser
import defs
import expression
import module

# =============================================================================
# ResolvedFile
# =============================================================================
type ResolvedFile* = ref object of RootObj
  name: string
  indent: int
  maybe_start_def: Option[ResolvedFunctionDefinition]
  modules_repo: Repo[Module, ResolvedModule]
  functions: seq[ResolvedFunction]

proc new_resolved_file*(name: string, indent: int, maybe_start_def: Option[
    ResolvedFunctionDefinition], modules: seq[ResolvedModule], functions: seq[
    ResolvedFunction]): Result[ResolvedFile, string] =
  let maybe_modules_repo = new_repo(modules, parsed_module)
  if maybe_modules_repo.is_err: return err("new_resolved_file UNREACHABLE")
  let modules_repo = maybe_modules_repo.get
  ok(ResolvedFile(name: name, indent: indent, maybe_start_def: maybe_start_def,
      modules_repo: modules_repo, functions: functions))

proc path*(file: ResolvedFile): string = file.name
proc indent*(file: ResolvedFile): int = file.indent
proc start_def*(file: ResolvedFile): Result[ResolvedFunctionDefinition, string] =
  case file.maybe_start_def.is_some
  of true: ok(file.maybe_start_def.get)
  of false: err(fmt"{file.path} failed to find `start` function")

proc modules*(file: ResolvedFile): seq[ResolvedModule] = file.modules_repo.items
proc functions*(file: ResolvedFile): seq[
    ResolvedFunction] = file.functions.map_it(it)

proc find_module*(file: ResolvedFile, module: Module): Result[
    ResolvedModule, string] =
  let maybe_module = file.modules_repo.find(module)
  if maybe_module.is_ok: ok(maybe_module.get)
  else: err("failed to find module `{module.name.asl}`")
