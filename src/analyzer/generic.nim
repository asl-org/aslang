import results, strformat, tables, hashes, sets

import resolver
import module_ref
import func_def

type AnalyzedGeneric* = ref object of RootObj
  resolved_generic: ResolvedGeneric
  defs: seq[AnalyzedFunctionDefinition]
  defs_map: Table[Identifier, Table[uint, seq[AnalyzedFunctionDefinition]]]

proc new_analyzed_generic(resolved_generic: ResolvedGeneric, defs: seq[
    AnalyzedFunctionDefinition]): AnalyzedGeneric =
  var defs_map: Table[Identifier, Table[uint, seq[AnalyzedFunctionDefinition]]]
  for def in defs:
    if def.name notin defs_map:
      defs_map[def.name] = init_table[uint, seq[
          AnalyzedFunctionDefinition]]()
    if def.arity notin defs_map[def.name]:
      defs_map[def.name][def.arity] = new_seq[AnalyzedFunctionDefinition]()
    defs_map[def.name][def.arity].add(def)
  AnalyzedGeneric(resolved_generic: resolved_generic, defs: defs,
      defs_map: defs_map)

proc defs*(generic: AnalyzedGeneric): seq[
    AnalyzedFunctionDefinition] = generic.defs
proc resolved_generic*(generic: AnalyzedGeneric): ResolvedGeneric = generic.resolved_generic
proc name*(generic: AnalyzedGeneric): Identifier = generic.resolved_generic.name

proc generic_impls*(generic: AnalyzedGeneric): Table[ResolvedModule, seq[
    HashSet[AnalyzedImpl]]] =
  var impl_set: Table[ResolvedModule, seq[HashSet[AnalyzedImpl]]]
  for def in generic.defs: impl_set = impl_set.merge(def.generic_impls())
  return impl_set

proc asl*(generic: AnalyzedGeneric, indent: string): seq[string] =
  if generic.defs.len == 0:
    @[fmt"generic {generic.name.asl}"]
  else:
    var lines = @[fmt"generic {generic.name.asl}:"]
    for def in generic.defs:
      lines.add(indent & def.asl)
    lines

proc c*(generic: AnalyzedGeneric, prefix: string): seq[string] =
  var lines: seq[string]
  for def in generic.defs:
    lines.add(def.h)
  # TODO: provide implementation of generic calls
  return lines

proc find_function_defs*(generic: AnalyzedGeneric, name: Identifier,
    arity: uint): Result[seq[AnalyzedFunctionDefinition], string] =
  if name notin generic.defs_map:
    err(fmt"generic `{generic.name.asl}` does not have any constraint named `{name.asl}`")
  elif arity notin generic.defs_map[name]:
    err(fmt"generic `{generic.name.asl}` does not have any constraint named `{name.asl}` with arity `{arity}`")
  else:
    ok(generic.defs_map[name][arity])

# Helper for resolving ResolvedGeneric with ResolvedModule
proc analyze_def*(file: ResolvedFile, generic: ResolvedGeneric,
    module: ResolvedModule): Result[AnalyzedGeneric, string] =
  var analyzed_defs: seq[AnalyzedFunctionDefinition]
  for def in generic.defs:
    let analyzed_def = ? analyze_def(file, module, generic, def)
    analyzed_defs.add(analyzed_def)
  ok(new_analyzed_generic(generic, analyzed_defs))
