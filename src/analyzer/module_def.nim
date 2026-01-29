import results, sequtils, strformat, tables, hashes, sets, options

import resolver
import module_ref
import func_def
import generic
import struct

type AnalyzedModuleDefinition* = ref object of RootObj
  resolved_module: ResolvedModule
  generics_repo: Repo[ResolvedGeneric, AnalyzedGeneric]
  structs: seq[AnalyzedStruct]
  default_struct_index: int
  structs_map: Table[Identifier, AnalyzedStruct]
  function_defs_repo: Repo[ResolvedFunctionDefinition, AnalyzedFunctionDefinition]
  function_signatures_map: Table[Identifier, Table[uint, seq[
      AnalyzedFunctionDefinition]]]

proc new_analyzed_module_definition(resolved_module: ResolvedModule,
    generics: seq[AnalyzedGeneric], structs: seq[AnalyzedStruct],
    function_defs: seq[AnalyzedFunctionDefinition]): Result[
    AnalyzedModuleDefinition, string] =
  let maybe_generics_repo = new_repo(generics, resolved_generic)
  if maybe_generics_repo.is_err: return err("new_analyzed_module_definition UNREACHABLE")
  let generics_repo = maybe_generics_repo.get

  var default_struct_index = -1
  var structs_map: Table[Identifier, AnalyzedStruct]
  var analyzed_structs: seq[AnalyzedStruct]
  for index, analyzed_struct in structs.pairs:
    analyzed_structs.add(analyzed_struct)
    case analyzed_struct.kind:
    of RSK_DEFAULT: default_struct_index = index
    of RSK_NAMED: structs_map[analyzed_struct.name] = analyzed_struct

  let maybe_function_defs_repo = new_repo(function_defs, resolved_def)
  if maybe_function_defs_repo.is_err: return err("new_analyzed_module_definition UNREACHABLE")
  let function_defs_repo = maybe_function_defs_repo.get

  var function_signatures_map: Table[Identifier, Table[uint,
      seq[AnalyzedFunctionDefinition]]]
  for analyzed_function_def in function_defs:
    if analyzed_function_def.name notin function_signatures_map:
      function_signatures_map[analyzed_function_def.name] = init_table[uint,
          seq[AnalyzedFunctionDefinition]]()
    if analyzed_function_def.arity notin function_signatures_map[
        analyzed_function_def.name]:
      function_signatures_map[analyzed_function_def.name][
          analyzed_function_def.arity] = new_seq[AnalyzedFunctionDefinition]()
    function_signatures_map[analyzed_function_def.name][
        analyzed_function_def.arity].add(analyzed_function_def)

  ok(AnalyzedModuleDefinition(resolved_module: resolved_module,
      generics_repo: generics_repo, structs: analyzed_structs,
      structs_map: structs_map, function_defs_repo: function_defs_repo,
      function_signatures_map: function_signatures_map))

proc id*(module_def: AnalyzedModuleDefinition): uint64 = module_def.id
proc resolved_module*(module_def: AnalyzedModuleDefinition): ResolvedModule = module_def.resolved_module
proc name*(module_def: AnalyzedModuleDefinition): Identifier = module_def.resolved_module.name
proc structs*(module_def: AnalyzedModuleDefinition): seq[
    AnalyzedStruct] = module_def.structs
proc generics*(module_def: AnalyzedModuleDefinition): seq[
    AnalyzedGeneric] = module_def.generics_repo.items
proc function_defs(module_def: AnalyzedModuleDefinition): seq[
    AnalyzedFunctionDefinition] =
  module_def.function_defs_repo.items
proc hash*(module_def: AnalyzedModuleDefinition): Hash = module_def.resolved_module.hash
proc `==`*(self: AnalyzedModuleDefinition,
    other: AnalyzedModuleDefinition): bool =
  self.hash == other.hash

proc generic_impls*(def: AnalyzedModuleDefinition): Table[ResolvedModule,
    seq[HashSet[AnalyzedImpl]]] =
  var impl_set: Table[ResolvedModule, seq[HashSet[AnalyzedImpl]]]
  for generic in def.generics: impl_set = impl_set.merge(generic.generic_impls())
  for struct in def.structs: impl_set = impl_set.merge(struct.generic_impls())
  for function in def.function_defs: impl_set = impl_set.merge(
      function.generic_impls())
  return impl_set

proc asl*(def: AnalyzedModuleDefinition, indent: string): seq[string] =
  var lines: seq[string]
  for generic in def.generics:
    lines.add(generic.asl(indent))

  if def.generics.len > 0:
    lines.add("\n")

  for struct in def.structs:
    lines.add(struct.asl(indent))
  return lines

proc h*(def: AnalyzedModuleDefinition): seq[string] =
  var lines: seq[string]
  for generic in def.generics:
    lines.add(generic.c(def.name.asl))

  if def.structs.len > 0:
    # internal functions for structs
    # byte size
    lines.add(fmt"U64 {def.name.asl}_byte_size(U64 items);")
    # read
    lines.add(fmt"Pointer {def.name.asl}_read(Pointer __asl_ptr, U64 offset);")
    # write
    lines.add(fmt"Pointer {def.name.asl}_write(Pointer value, Pointer __asl_ptr, U64 offset);")

    # struct
    if def.structs.len == 1:
      let struct = def.structs[0]
      lines.add(struct.h(def.name.asl))
    # union
    else:
      # union branch id getter
      lines.add(fmt"U64 {def.name.asl}_get_id(Pointer __asl_ptr);")

      # union branch id setter
      lines.add(fmt"Pointer {def.name.asl}_set_id(Pointer __asl_ptr, U64 id);")
      for index, struct in def.structs:
        lines.add(struct.h(def.name.asl, some(index.uint64)))

  # TODO: Understand that function can not have same name so use function id as prefix
  lines.add(def.function_defs.map_it(it.h))

  return lines

proc c*(def: AnalyzedModuleDefinition): seq[string] =
  var lines: seq[string]
  for generic in def.generics:
    lines.add(generic.c(def.name.asl))

  if def.structs.len > 0:
    # internal functions for structs
    # byte size
    lines.add(fmt"U64 {def.name.asl}_byte_size(U64 items)")
    lines.add("{")
    lines.add("return Pointer_byte_size(items);")
    lines.add("}")
    # read
    lines.add(fmt"Pointer {def.name.asl}_read(Pointer __asl_ptr, U64 offset)")
    lines.add("{")
    lines.add("return Pointer_read(__asl_ptr, offset);")
    lines.add("}")
    # write
    lines.add(fmt"Pointer {def.name.asl}_write(Pointer value, Pointer __asl_ptr, U64 offset)")
    lines.add("{")
    lines.add("return Pointer_write(value, __asl_ptr, offset);")
    lines.add("}")

    # struct
    if def.structs.len == 1:
      let struct = def.structs[0]
      lines.add(struct.c(def.name.asl))
    # union
    else:
      # union branch id getter
      lines.add(fmt"U64 {def.name.asl}_get_id(Pointer __asl_ptr)")
      lines.add("{")
      lines.add(fmt"return U64_read(__asl_ptr, 0);")
      lines.add("}")

      # union branch id setter
      lines.add(fmt"Pointer {def.name.asl}_set_id(Pointer __asl_ptr, U64 id)")
      lines.add("{")
      lines.add(fmt"return U64_write(id, __asl_ptr, 0);")
      lines.add("}")
      for index, struct in def.structs:
        lines.add(struct.c(def.name.asl, some(index.uint64)))

  return lines

proc find_generic*(module_def: AnalyzedModuleDefinition,
    generic: ResolvedGeneric): Result[AnalyzedGeneric, string] =
  let maybe_generic = module_def.generics_repo.find(generic)
  if maybe_generic.is_ok: ok(maybe_generic.get)
  else: err(fmt"module `{module_def.name.asl}` does not have any generic named `{generic.name.asl}`")

proc find_struct*(module_def: AnalyzedModuleDefinition): Result[
    AnalyzedStruct, string] =
  if module_def.default_struct_index == -1:
    err(fmt"module `{module_def.name.asl}` does not have a default struct")
  else:
    ok(module_def.structs[module_def.default_struct_index])

proc find_struct*(module_def: AnalyzedModuleDefinition,
    name: Identifier): Result[AnalyzedStruct, string] =
  if name notin module_def.structs_map:
    err(fmt"module `{module_def.name.asl}` does not have struct named `{name.asl}`")
  else:
    ok(module_def.structs_map[name])

proc find_function_def*(module_def: AnalyzedModuleDefinition,
    function_def: ResolvedFunctionDefinition): Result[
        AnalyzedFunctionDefinition, string] =
  let maybe_function_def = module_def.function_defs_repo.find(function_def)
  if maybe_function_def.is_ok: ok(maybe_function_def.get)
  else: err(fmt"module `{module_def.name.asl}` does not have any function named `{function_def.name.asl}`")

proc find_function_defs*(module_def: AnalyzedModuleDefinition,
    name: Identifier, arity: uint, location: Location): Result[seq[
    AnalyzedFunctionDefinition], string] =
  if name notin module_def.function_signatures_map:
    err(fmt"{location} module `{module_def.name.asl}` does not have any function named `{name.asl}`")
  elif arity notin module_def.function_signatures_map[name]:
    err(fmt"{location} module `{module_def.name.asl}` does not have any function named `{name.asl}` with arity `{arity}`")
  else:
    ok(module_def.function_signatures_map[name][arity])

proc analyze_def*(file: ResolvedFile, module: ResolvedModule): Result[
    AnalyzedModuleDefinition, string] =
  var generics: seq[AnalyzedGeneric]
  for generic in module.generics:
    let analyzed_generic = ? analyze_def(file, generic, module)
    generics.add(analyzed_generic)

  var structs: seq[AnalyzedStruct]
  for struct in module.structs:
    let analyzed_struct = ? analyze_def(file, module, struct)
    structs.add(analyzed_struct)

  var function_defs: seq[AnalyzedFunctionDefinition]
  for function in module.functions:
    let analyzed_def = ? analyze_def(file, module, function)
    function_defs.add(analyzed_def)

  new_analyzed_module_definition(module, generics, structs, function_defs)
