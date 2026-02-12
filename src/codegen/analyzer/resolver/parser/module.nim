import results, strformat, tables, hashes

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
  discard ? parser.expect_at_least_one(space_spec)
  let name = ? parser.expect(identifier_spec)
  discard ? parser.expect_any(space_spec)
  discard ? parser.expect(colon_spec)
  ok(new_module_definition(name, module_keyword.location))

# =============================================================================
# Module
# =============================================================================

type Module* = ref object of RootObj
  def: ModuleDefinition
  generics_repo: Repo[Generic]
  data: Data
  structs: seq[Struct]
  functions_repo: Repo[Function]

proc new_module*(def: ModuleDefinition, generics: seq[Generic],
    data: Data, functions: seq[Function]): Result[Module, core.Error] =
  if functions.len == 0 and data.kind == DK_NONE:
    if generics.len == 0:
      return err(err_parser_empty_module(def.location, def.name.asl))
    else:
      return err(err_parser_empty_module_with_generics(def.location, def.name.asl))

  let maybe_generics_repo = new_repo(generics, @[new_index[Generic]("name",
      name, true)])
  if maybe_generics_repo.is_err:
    let error = maybe_generics_repo.error
    let generic = error.current
    let predefined_generic_location = error.previous.location
    return err(err_parser_generic_already_defined(generic.location,
          generic.name.asl, predefined_generic_location))
  let generics_repo = maybe_generics_repo.get

  case data.kind:
  of DK_UNION:
    let union = data.union
    for branch in union.branches:
      let maybe_generic = generics_repo.find("name", branch.name)
      if maybe_generic.is_ok:
        let generic = maybe_generic.get[0]
        return err(err_parser_struct_generic_conflict(branch.location,
            branch.name.asl, generic.location, generic.name.asl))
  else:
    discard

  let maybe_functions_repo = new_repo(functions, @[new_index("def", proc(
      fn: Function): Hash = fn.def.hash, true)])
  if maybe_functions_repo.is_err:
    let error = maybe_functions_repo.error
    let function = error.current
    let predefined_function_location = error.previous.location
    return err(err_parser_function_already_defined(function.location,
        function.name.asl, predefined_function_location))
  let functions_repo = maybe_functions_repo.get

  for index, function in functions:
    let maybe_generic = generics_repo.find("name", function.name)
    if maybe_generic.is_ok:
      let generic = maybe_generic.get[0]
      return err(err_parser_function_generic_conflict(function.location,
          function.name.asl, generic.location, generic.name.asl))

    case data.kind:
    of DK_UNION:
      let union = data.union
      let maybe_branch = union.find_branch(function.name)
      if maybe_branch.is_ok:
        let branch = maybe_branch.get
        return err(err_parser_function_struct_conflict(function.location,
            function.name.asl, branch.location, branch.name.asl))
    else:
      discard

  ok(Module(def: def, generics_repo: generics_repo, data: data,
      functions_repo: functions_repo))

proc hash*(module: Module): Hash = module.def.hash
proc `==`*(self: Module, other: Module): bool = self.hash == other.hash
proc def*(module: Module): ModuleDefinition = module.def
proc name*(module: Module): Identifier = module.def.name
proc location*(module: Module): Location = module.def.location
proc generics*(module: Module): seq[Generic] = module.generics_repo.items
proc data*(module: Module): Data = module.data
proc functions*(module: Module): seq[Function] = module.functions_repo.items

proc find_generic*(module: Module, name: Identifier): Result[Generic, string] =
  let maybe_generic = module.generics_repo.find("name", name)
  if maybe_generic.is_ok: ok(maybe_generic.get[0])
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
  parser.expect_any(generic_spec, indent, optional_empty_line_spec)

proc function_list_spec(parser: Parser, indent: int): Result[seq[Function],
    core.Error] =
  discard ? parser.expect_any(empty_line_spec)
  parser.expect_any(function_spec, indent + 1, optional_empty_line_spec)

proc module_spec*(parser: Parser, indent: int): Result[Module, core.Error] =
  discard ? parser.expect(indent_spec, indent)
  let def = ? parser.expect(module_definition_spec)
  discard ? parser.expect_any(empty_line_spec)
  let generics = ? parser.expect(generic_list_spec, indent + 1)
  discard ? parser.expect_any(empty_line_spec)
  let data = ? parser.expect(data_spec, indent + 1)
  discard ? parser.expect_any(empty_line_spec)
  let functions = ? parser.expect(function_list_spec, indent)
  new_module(def, generics, data, functions)
