import results, strformat, sequtils, tables, hashes

import core, identifier, module_ref, defs, struct, generic, function

# =============================================================================
# ModuleDefinition
# =============================================================================

type ModuleDefinition* = ref object of RootObj
  name: Identifier
  location: Location

proc new_module_definition*(name: Identifier,
    location: Location): ModuleDefinition =
  ModuleDefinition(name: name, location: location)

proc location*(def: ModuleDefinition): Location =
  def.location

proc asl*(def: ModuleDefinition): string =
  fmt"module {def.name.asl}:"

proc hash*(def: ModuleDefinition): Hash =
  def.location.hash

proc module_definition_spec*(parser: Parser): Result[ModuleDefinition,
    core.Error] =
  let module_keyword = ? parser.expect(module_keyword_spec)
  discard ? parser.expect(strict_space_spec)
  let name = ? parser.expect(identifier_spec)
  discard ? parser.expect(optional_space_spec)
  discard ? parser.expect(colon_spec)
  ok(new_module_definition(name, module_keyword.location))

# =============================================================================
# Module
# =============================================================================

type Module* = ref object of RootObj
  def: ModuleDefinition
  generics_repo: Repo[Identifier, Generic]
  data: Data
  structs: seq[Struct]
  default_struct_index: int
  structs_map: Table[Identifier, int]
  functions: seq[Function]
  functions_map: Table[Identifier, seq[int]]
  function_defs_hash_map: Table[Hash, int]

proc new_module*(def: ModuleDefinition, generics: seq[Generic],
    data: Data, functions: seq[Function]): Result[Module, core.Error] =
  if functions.len == 0 and data.kind == DK_NONE:
    if generics.len == 0:
      return err(err_parser_empty_module(def.location, def.name.asl))
    else:
      return err(err_parser_empty_module_with_generics(def.location, def.name.asl))

  let maybe_generics_repo = new_repo(generics, name)
  var generics_repo: Repo[Identifier, Generic]
  if maybe_generics_repo.is_ok:
    generics_repo = maybe_generics_repo.get
  else:
    let error = maybe_generics_repo.error
    let generic = error.current
    let predefined_generic_location = error.previous.location
    return err(err_parser_generic_already_defined(generic.location,
          generic.name.asl, predefined_generic_location))

  var structs: seq[Struct]
  var structs_map: Table[Identifier, int]
  var default_struct_index = -1
  case data.kind:
  of DK_STRUCT:
    let struct = ? data.struct
    structs = @[struct]
    if struct.def.kind != SDK_DEFAULT:
      return err(err_parser_expected_default_struct(struct.location,
          struct.name.asl))
    else:
      default_struct_index = 0
  of DK_UNION:
    let union = ? data.union
    for branch in union.branches:
      structs.add( ? branch.struct)
    for index, struct in structs:
      case struct.def.kind:
      of SDK_DEFAULT:
        if default_struct_index == -1:
          default_struct_index = index
        else:
          let predefined_default_struct_location = structs[
              default_struct_index].location
          return err(err_parser_struct_already_defined(struct.location,
              "default", predefined_default_struct_location))
      of SDK_NAMED:
        let maybe_generic = generics_repo.find(struct.name)
        if maybe_generic.is_ok:
          let generic = maybe_generic.get
          return err(err_parser_struct_generic_conflict(struct.location,
              struct.name.asl, generic.location, generic.name.asl))

        if struct.name in structs_map:
          let predefined_struct_location = structs[structs_map[
              struct.name]].location
          return err(err_parser_struct_already_defined(struct.location,
              struct.name.asl, predefined_struct_location))

        structs_map[struct.name] = index
  of DK_NONE:
    discard
  of DK_LITERAL:
    discard

  var function_defs_hash_map: Table[Hash, int]
  var functions_map: Table[Identifier, seq[int]]
  for index, function in functions:
    let maybe_generic = generics_repo.find(function.name)
    if maybe_generic.is_ok:
      let generic = maybe_generic.get
      return err(err_parser_function_generic_conflict(function.location,
          function.name.asl, generic.location, generic.name.asl))

    if function.name in structs_map:
      let struct = structs[structs_map[function.name]]
      return err(err_parser_function_struct_conflict(function.location,
          function.name.asl, struct.location, struct.name.asl))

    let def_hash = function.def.hash
    if def_hash in function_defs_hash_map:
      let predefined_function_location = functions[function_defs_hash_map[
          def_hash]].location
      return err(err_parser_function_already_defined(function.location,
          function.name.asl, predefined_function_location))
    function_defs_hash_map[def_hash] = index

    if function.name notin functions_map:
      functions_map[function.name] = new_seq[int]()
    functions_map[function.name].add(index)

  ok(Module(def: def, structs: structs, structs_map: structs_map,
      default_struct_index: default_struct_index, generics_repo: generics_repo,
      functions: functions, functions_map: functions_map,
      function_defs_hash_map: function_defs_hash_map))

proc new_module*(name: string, functions: seq[
    ExternFunction]): Result[Module, core.Error] =
  let name = new_identifier(name)
  let module_def = new_module_definition(name, name.location)
  let module_data = new_data()
  let module_functions = functions.map_it(new_function(it))
  new_module(module_def, @[], module_data, module_functions)

proc hash*(module: Module): Hash = module.def.hash
proc `==`*(self: Module, other: Module): bool = self.hash == other.hash
proc def*(module: Module): ModuleDefinition = module.def
proc name*(module: Module): Identifier = module.def.name
proc location*(module: Module): Location = module.def.location
proc generics*(module: Module): seq[Generic] = module.generics_repo.items
proc structs*(module: Module): seq[Struct] = module.structs
proc functions*(module: Module): seq[Function] = module.functions
proc is_struct*(module: Module): bool = module.structs.len > 0

proc module_ref*(module: Module): Result[ModuleRef, core.Error] =
  if module.generics.len > 0:
    let children = module.generics.map_it(new_module_ref(it.name))
    new_module_ref(module.name, children)
  else:
    ok(new_module_ref(module.name))

proc find_generic*(module: Module, name: Identifier): Result[Generic, string] =
  let maybe_generic = module.generics_repo.find(name)
  if maybe_generic.is_ok: ok(maybe_generic.get)
  else: err(fmt"{name.location} [PE154] module `{module.name.asl}` does not have any generic named `{name.asl}`")

proc asl*(module: Module, indent: string): seq[string] =
  var lines = @[module.def.asl]
  for generic in module.generics:
    for line in generic.asl(indent):
      lines.add(indent & line)
  lines.add("\n")
  for struct in module.structs:
    for line in struct.asl(indent):
      lines.add(indent & line)
  lines.add("\n")
  for function in module.functions:
    for line in function.asl(indent):
      lines.add(indent & line)
    lines.add("\n")

  return lines

proc generic_list_spec(parser: Parser, indent: int): Result[seq[Generic],
    core.Error] =
  var generics: seq[Generic]
  var maybe_generic = parser.expect(generic_spec, indent)
  while maybe_generic.is_ok:
    generics.add(maybe_generic.get)
    discard ? parser.expect(optional_empty_line_spec)
    maybe_generic = parser.expect(generic_spec, indent)
  ok(generics)

proc function_list_spec(parser: Parser, indent: int): Result[seq[Function],
    core.Error] =
  var functions: seq[Function]
  discard ? parser.expect(optional_empty_line_spec)
  var maybe_function = parser.expect(function_spec, indent + 1)
  while maybe_function.is_ok:
    functions.add(maybe_function.get)
    discard ? parser.expect(optional_empty_line_spec)
    maybe_function = parser.expect(function_spec, indent + 1)
  ok(functions)

proc module_spec*(parser: Parser, indent: int): Result[Module, core.Error] =
  discard ? parser.expect(indent_spec, indent)
  let def = ? parser.expect(module_definition_spec)
  discard ? parser.expect(optional_empty_line_spec)
  let generics = ? parser.expect(generic_list_spec, indent + 1)
  discard ? parser.expect(optional_empty_line_spec)
  let data = ? parser.expect(data_spec, indent + 1)
  discard ? parser.expect(optional_empty_line_spec)
  let functions = ? parser.expect(function_list_spec, indent)
  new_module(def, generics, data, functions)
