import results, strformat, sequtils, tables, hashes

import core, identifier, module_ref, defs, struct, generic, function
export core, identifier, module_ref, defs, struct, generic, function

# =============================================================================
# UserModuleDefinition
# =============================================================================

type UserModuleDefinition* = ref object of RootObj
  name: Identifier
  location: Location

proc new_module_definition*(name: Identifier,
    location: Location): UserModuleDefinition =
  UserModuleDefinition(name: name, location: location)

proc location*(def: UserModuleDefinition): Location =
  def.location

proc asl*(def: UserModuleDefinition): string =
  fmt"module {def.name.asl}:"

proc hash*(def: UserModuleDefinition): Hash =
  def.location.hash

proc module_definition_spec*(parser: Parser): Result[UserModuleDefinition, ParserError] =
  let module_keyword = ? parser.expect(module_keyword_spec)
  discard ? parser.expect(strict_space_spec)
  let name = ? parser.expect(identifier_spec)
  discard ? parser.expect(optional_space_spec)
  discard ? parser.expect(colon_spec)
  ok(new_module_definition(name, module_keyword.location))

# =============================================================================
# UserModule
# =============================================================================

type UserModule* = ref object of RootObj
  def: UserModuleDefinition
  generics: seq[Generic]
  generics_map: Table[Identifier, int]
  data: Data
  structs: seq[Struct]
  default_struct_index: int
  structs_map: Table[Identifier, int]
  functions: seq[Function]
  functions_map: Table[Identifier, seq[int]]
  function_defs_hash_map: Table[Hash, int]

proc new_user_module*(def: UserModuleDefinition, generics: seq[Generic],
    data: Data, functions: seq[Function]): Result[UserModule, ParserError] =
  if functions.len == 0 and data.kind == DK_NONE:
    if generics.len == 0:
      return err(err_parser_empty_module(def.location, def.name.asl))
    else:
      return err(err_parser_empty_module_with_generics(def.location, def.name.asl))

  var generics_map: Table[Identifier, int]
  for index, generic in generics:
    if generic.name in generics_map:
      let predefined_generic_location = generics[generics_map[
          generic.name]].location
      return err(err_parser_generic_already_defined(generic.location,
          generic.name.asl, predefined_generic_location))
    generics_map[generic.name] = index

  var structs_map: Table[Identifier, int]
  var default_struct_index = -1
  case data.kind:
  of DK_MULTI_STRUCT:
    let structs = ? data.structs
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
        if struct.name in generics_map:
          let generic = generics[generics_map[struct.name]]
          return err(err_parser_struct_generic_conflict(struct.location,
              struct.name.asl, generic.location, generic.name.asl))

        if struct.name in structs_map:
          let predefined_struct_location = structs[structs_map[
              struct.name]].location
          return err(err_parser_struct_already_defined(struct.location,
              struct.name.asl, predefined_struct_location))

        structs_map[struct.name] = index

    var function_defs_hash_map: Table[Hash, int]
    var functions_map: Table[Identifier, seq[int]]
    for index, function in functions:
      if function.name in generics_map:
        let generic = generics[generics_map[function.name]]
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

    ok(UserModule(def: def, structs: structs, structs_map: structs_map,
        default_struct_index: default_struct_index, generics: generics,
        generics_map: generics_map, functions: functions,
        functions_map: functions_map,
        function_defs_hash_map: function_defs_hash_map))
  of DK_STRUCT:
    let struct = ? data.struct
    if struct.def.kind != SDK_DEFAULT:
      return err(err_parser_expected_default_struct(struct.location,
          struct.name.asl))
    else:
      default_struct_index = 0

    var function_defs_hash_map: Table[Hash, int]
    var functions_map: Table[Identifier, seq[int]]
    for index, function in functions:
      if function.name in generics_map:
        let generic = generics[generics_map[function.name]]
        return err(err_parser_function_generic_conflict(function.location,
            function.name.asl, generic.location, generic.name.asl))

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

    ok(UserModule(def: def, structs: @[struct], data: data,
        default_struct_index: 0, generics: generics, generics_map: generics_map,
        functions: functions, functions_map: functions_map,
        function_defs_hash_map: function_defs_hash_map))
  of DK_UNION:
    let union = ? data.union
    var function_defs_hash_map: Table[Hash, int]
    var functions_map: Table[Identifier, seq[int]]
    for index, function in functions:
      if function.name in generics_map:
        let generic = generics[generics_map[function.name]]
        return err(err_parser_function_generic_conflict(function.location,
            function.name.asl, generic.location, generic.name.asl))

      let maybe_branch = union.find_branch(function.name)
      if maybe_branch.is_ok:
        let branch = maybe_branch.get
        return err(err_parser_function_union_branch_conflict(function.location,
            function.name.asl, branch.location, branch.name.asl))

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

    ok(UserModule(def: def, data: data,
        default_struct_index: default_struct_index, generics: generics,
        generics_map: generics_map, functions: functions,
        functions_map: functions_map,
        function_defs_hash_map: function_defs_hash_map))
  of DK_NONE:
    let structs: seq[Struct] = @[]
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
        if struct.name in generics_map:
          let generic = generics[generics_map[struct.name]]
          return err(err_parser_struct_generic_conflict(struct.location,
              struct.name.asl, generic.location, generic.name.asl))

        if struct.name in structs_map:
          let predefined_struct_location = structs[structs_map[
              struct.name]].location
          return err(err_parser_struct_already_defined(struct.location,
              struct.name.asl, predefined_struct_location))

        structs_map[struct.name] = index

    var function_defs_hash_map: Table[Hash, int]
    var functions_map: Table[Identifier, seq[int]]
    for index, function in functions:
      if function.name in generics_map:
        let generic = generics[generics_map[function.name]]
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

    ok(UserModule(def: def, structs: structs, structs_map: structs_map,
        default_struct_index: default_struct_index, generics: generics,
        generics_map: generics_map, functions: functions,
        functions_map: functions_map,
        function_defs_hash_map: function_defs_hash_map))
  else:
    let structs = ? data.structs
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
        if struct.name in generics_map:
          let generic = generics[generics_map[struct.name]]
          return err(err_parser_struct_generic_conflict(struct.location,
              struct.name.asl, generic.location, generic.name.asl))

        if struct.name in structs_map:
          let predefined_struct_location = structs[structs_map[
              struct.name]].location
          return err(err_parser_struct_already_defined(struct.location,
              struct.name.asl, predefined_struct_location))

        structs_map[struct.name] = index

    var function_defs_hash_map: Table[Hash, int]
    var functions_map: Table[Identifier, seq[int]]
    for index, function in functions:
      if function.name in generics_map:
        let generic = generics[generics_map[function.name]]
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

    ok(UserModule(def: def, structs: structs, structs_map: structs_map,
        default_struct_index: default_struct_index, generics: generics,
        generics_map: generics_map, functions: functions,
        functions_map: functions_map,
        function_defs_hash_map: function_defs_hash_map))

proc new_user_module*(name: string, functions: seq[
    ExternFunction]): Result[UserModule, ParserError] =
  let name = new_identifier(name)
  let user_module_def = new_module_definition(name, name.location)
  let user_module_data = new_data()
  let user_module_functions = functions.map_it(new_function(it))
  new_user_module(user_module_def, @[], user_module_data, user_module_functions)

proc new_user_module*(name: string, generics: seq[Generic], structs: seq[
    Struct], functions: seq[ExternFunction]): Result[UserModule, ParserError] =
  let name = new_identifier(name)
  let user_module_def = new_module_definition(name, name.location)
  let user_module_data = new_data(structs)
  let user_module_functions = functions.map_it(new_function(it))
  new_user_module(user_module_def, generics, user_module_data, user_module_functions)

proc hash*(module: UserModule): Hash = module.def.hash
proc `==`*(self: UserModule, other: UserModule): bool = self.hash == other.hash
proc def*(module: UserModule): UserModuleDefinition = module.def
proc name*(module: UserModule): Identifier = module.def.name
proc location*(module: UserModule): Location = module.def.location
proc generics*(module: UserModule): seq[Generic] = module.generics
proc structs*(module: UserModule): seq[Struct] = module.structs
proc is_struct*(module: UserModule): bool = module.structs.len > 0

proc module_ref*(module: UserModule): Result[ModuleRef, ParserError] =
  if module.generics.len > 0:
    let children = module.generics.map_it(new_module_ref(it.name))
    new_module_ref(module.name, children)
  else:
    ok(new_module_ref(module.name))

proc find_generic*(module: UserModule, name: Identifier): Result[Generic, string] =
  if name notin module.generics_map:
    err(fmt"{name.location} [PE154] module `{module.name.asl}` does not have any generic named `{name.asl}`")
  else:
    ok(module.generics[module.generics_map[name]])

proc asl*(module: UserModule, indent: string): seq[string] =
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

proc generic_list_spec(parser: Parser, indent: int): Result[seq[Generic], ParserError] =
  var generics: seq[Generic]
  discard ? parser.expect(optional_empty_line_spec)
  var maybe_generic = parser.expect(generic_spec, indent + 1)
  while maybe_generic.is_ok:
    generics.add(maybe_generic.get)
    discard ? parser.expect(optional_empty_line_spec)
    maybe_generic = parser.expect(generic_spec, indent + 1)
  ok(generics)

proc function_list_spec(parser: Parser, indent: int): Result[seq[Function], ParserError] =
  var functions: seq[Function]
  discard ? parser.expect(optional_empty_line_spec)
  var maybe_function = parser.expect(function_spec, indent + 1)
  while maybe_function.is_ok:
    functions.add(maybe_function.get)
    discard ? parser.expect(optional_empty_line_spec)
    maybe_function = parser.expect(function_spec, indent + 1)
  ok(functions)

proc module_spec*(parser: Parser, indent: int): Result[UserModule, ParserError] =
  discard ? parser.expect(indent_spec, indent)
  let def = ? parser.expect(module_definition_spec)
  discard ? parser.expect(optional_empty_line_spec)
  let generics = ? parser.expect(generic_list_spec, indent)
  discard ? parser.expect(optional_empty_line_spec)
  let data = ? parser.expect(data_spec, indent)
  discard ? parser.expect(optional_empty_line_spec)
  let functions = ? parser.expect(function_list_spec, indent)
  new_user_module(def, generics, data, functions)

# =============================================================================
# NativeModule
# =============================================================================

type NativeModule* = ref object of RootObj
  user_module: UserModule

proc new_native_module*(name: string, functions: seq[
    ExternFunction]): Result[NativeModule, ParserError] =
  let user_module = ? new_user_module(name, functions)
  ok(NativeModule(user_module: user_module))

proc new_native_module*(name: string, generics: seq[Generic], structs: seq[
    Struct], functions: seq[ExternFunction]): Result[NativeModule, ParserError] =
  let user_module = ? new_user_module(name, generics, structs, functions)
  ok(NativeModule(user_module: user_module))

proc name*(module: NativeModule): Identifier =
  module.user_module.name

proc hash*(module: NativeModule): Hash =
  module.name.hash

proc generics*(module: NativeModule): seq[Generic] =
  module.user_module.generics

proc structs*(module: NativeModule): seq[Struct] =
  module.user_module.structs

proc functions*(module: NativeModule): seq[Function] =
  var functions: seq[Function]
  for function in module.user_module.functions:
    case function.kind:
    of FK_EXTERN: functions.add(new_function(function.extern_func))
    of FK_USER: discard
  functions

proc all_functions*(module: NativeModule): seq[Function] =
  module.user_module.functions

proc module_ref*(module: NativeModule): Result[ModuleRef, ParserError] =
  ok(new_module_ref(module.name))

proc find_generic*(module: NativeModule, name: Identifier): Result[Generic, string] =
  module.user_module.find_generic(name)

# =============================================================================
# Module (Unified)
# =============================================================================

type
  ModuleKind* = enum
    MK_NATIVE, MK_USER
  Module* = ref object of RootObj
    case kind: ModuleKind
    of MK_NATIVE: native: NativeModule
    of MK_USER: user: UserModule

proc new_module*(native: NativeModule): Module =
  Module(kind: MK_NATIVE, native: native)

proc new_module*(user: UserModule): Module =
  Module(kind: MK_USER, user: user)

proc kind*(module: Module): ModuleKind = module.kind

proc hash*(module: Module): Hash =
  case module.kind:
  of MK_USER: module.user.hash
  of MK_NATIVE: module.native.hash

proc `==`*(self: Module, other: Module): bool =
  self.hash == other.hash

proc module_ref*(module: Module): Result[ModuleRef, ParserError] =
  case module.kind:
  of MK_NATIVE: module.native.module_ref
  of MK_USER: module.user.module_ref

proc name*(module: Module): Identifier =
  case module.kind:
  of MK_NATIVE: module.native.name
  of MK_USER: module.user.name

proc generics*(module: Module): seq[Generic] =
  case module.kind:
  of MK_NATIVE: module.native.generics
  of MK_USER: module.user.generics

proc generics_map*(module: Module): Table[Identifier, int] =
  module.generics_map

proc user_structs*(module: Module): Result[seq[Struct], string] =
  case module.kind:
  of MK_USER: ok(module.user.structs)
  of MK_NATIVE: err(fmt"[PE161] module `{module.name.asl}` is not a user module")

proc native_structs*(module: Module): Result[seq[Struct], string] =
  case module.kind:
  of MK_NATIVE: ok(module.native.structs)
  of MK_USER: err(fmt"[PE160] module `{module.name.asl}` is not a native module")

proc structs*(module: Module): seq[Struct] =
  case module.kind:
  of MK_NATIVE: module.native.structs
  of MK_USER: module.user.structs

proc user_functions*(module: Module): Result[seq[Function], string] =
  case module.kind:
  of MK_USER: ok(module.user.functions)
  of MK_NATIVE: err(fmt"[PE161] module `{module.name.asl}` is not a user module")

proc native_functions*(module: Module): Result[seq[Function], string] =
  case module.kind:
  of MK_NATIVE: ok(module.native.functions)
  of MK_USER: err(fmt"[PE160] module `{module.name.asl}` is not a native module")

proc functions*(module: Module): seq[Function] =
  case module.kind:
  of MK_NATIVE: module.native.functions
  of MK_USER: module.user.functions

proc functions_map*(module: Module): Table[Identifier, seq[int]] =
  case module.kind:
  of MK_NATIVE: module.native.user_module.functions_map
  of MK_USER: module.functions_map

proc function_defs_hash_map*(module: Module): Table[Hash, int] =
  case module.kind:
  of MK_NATIVE: module.native.user_module.function_defs_hash_map
  of MK_USER: module.user.function_defs_hash_map

proc find_generic*(module: Module, name: Identifier): Result[Generic, string] =
  case module.kind:
  of MK_NATIVE: module.native.find_generic(name)
  of MK_USER: module.user.find_generic(name)

proc native_module*(module: Module): NativeModule =
  doAssert module.kind == MK_NATIVE, "expected a native module"
  module.native

proc user_module*(module: Module): UserModule =
  doAssert module.kind == MK_USER, "expected a user module"
  module.user

proc location*(module: Module): Location =
  case module.kind:
  of MK_NATIVE: Location()
  of MK_USER: module.user.location
