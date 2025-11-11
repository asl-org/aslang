import results, sequtils, strformat, tables, hashes, strutils

import resolver/deps_analyzer

type
  ResolvedModuleRefKind = enum
    RMRK_NATIVE, RMRK_USER, RMRK_GENERIC
  ResolvedModuleRef = ref object of RootObj
    location: Location
    case kind: ResolvedModuleRefKind
    of RMRK_NATIVE: native_module: TypedNativeModule
    of RMRK_GENERIC: generic: TypedGeneric
    of RMRK_USER:
      user_module: TypedModule
      children: seq[ResolvedModuleRef]
      concrete_map: Table[TypedGeneric, ResolvedModuleRef]

proc new_resolved_module_ref(native_module: TypedNativeModule,
    location: Location): ResolvedModuleRef =
  ResolvedModuleRef(kind: RMRK_NATIVE, native_module: native_module,
      location: location)

proc new_resolved_module_ref(generic: TypedGeneric,
    location: Location): ResolvedModuleRef =
  ResolvedModuleRef(kind: RMRK_GENERIC, generic: generic,
      location: location)

proc new_resolved_module_ref(user_module: TypedModule, children: seq[
    ResolvedModuleRef], location: Location): ResolvedModuleRef =
  var concrete_map: Table[TypedGeneric, ResolvedModuleRef]
  for (generic, child) in zip(user_module.generics, children):
    concrete_map[generic] = child
  ResolvedModuleRef(kind: RMRK_USER, user_module: user_module,
      concrete_map: concrete_map, children: children, location: location)

proc can_be_argument(module_ref: ResolvedModuleRef): Result[void, string] =
  case module_ref.kind:
  of RMRK_NATIVE: ok() # native modules can be passed as an argument
  of RMRK_GENERIC: ok() # generic arguments can be passed as an argument too.
  of RMRK_USER:
    let module = module_ref.user_module
    if module.structs.len > 0: ok()
    else: err(fmt"{module_ref.location} module `{module.name.asl}` can not be passed as an argument")

# proc native_module(module_ref: ResolvedModuleRef): Result[TypedNativeModule, string] =
#   case module_ref.kind:
#   of RMRK_NATIVE: ok(module_ref.native_module)
#   else: err(fmt"{module_ref.location} expected a native module")

# proc user_module(module_ref: ResolvedModuleRef): Result[TypedModule, string] =
#   case module_ref.kind:
#   of RMRK_NATIVE: err(fmt"{module_ref.location} expected a user module")
#   of RMRK_GENERIC: ok(module_ref.module)
#   of RMRK_USER: ok(module_ref.user_module)

# proc generic(module_ref: ResolvedModuleRef): Result[TypedGeneric, string] =
#   case module_ref.kind:
#   of RMRK_GENERIC: ok(module_ref.generic)
#   else: err(fmt"{module_ref.location} expected a generic")

proc find_function(module_ref: ResolvedModuleRef,
    def: TypedFunctionDefinition): Result[TypedFunctionDefinition, string] =
  case module_ref.kind:
  of RMRK_NATIVE: module_ref.native_module.find_function(def)
  of RMRK_GENERIC: module_ref.generic.find_function(def)
  of RMRK_USER: module_ref.user_module.find_function(def)

proc concretize(module_ref: ResolvedModuleRef, concrete_map: Table[TypedGeneric,
    ResolvedModuleRef]): ResolvedModuleRef =
  case module_ref.kind:
  of RMRK_NATIVE: module_ref
  of RMRK_GENERIC: concrete_map[module_ref.generic]
  of RMRK_USER:
    var concretized_children: seq[ResolvedModuleRef]
    for child in module_ref.children:
      concretized_children.add(child.concretize(concrete_map))
    new_resolved_module_ref(module_ref.user_module, concretized_children,
        module_ref.location)

proc hash(module_ref: ResolvedModuleRef): Hash =
  case module_ref.kind:
  of RMRK_NATIVE: module_ref.native_module.hash
  of RMRK_GENERIC: module_ref.generic.hash
  of RMRK_USER:
    var acc = module_ref.user_module.hash
    for child in module_ref.children:
      acc = acc !& child.hash
    acc

proc `==`(self: ResolvedModuleRef, other: ResolvedModuleRef): bool =
  self.hash == other.hash

proc asl(module_ref: ResolvedModuleRef): string =
  case module_ref.kind:
  of RMRK_NATIVE: module_ref.native_module.asl
  of RMRK_GENERIC: module_ref.generic.asl
  of RMRK_USER:
    var parent_str = module_ref.user_module.asl
    var children_args: seq[string]
    for child in module_ref.children:
      children_args.add(child.asl)
    let children_str = children_args.join(", ")
    fmt"{parent_str}[{children_str}]"

proc resolve_def*(file: TypedFile, module: TypedModule, generic: TypedGeneric,
    module_ref: TypedModuleRef): Result[ResolvedModuleRef, string] =
  case module_ref.kind:
  of TMRK_NATIVE:
    let untyped_module = ? module_ref.native_module
    let typed_module = ? file.find_module(untyped_module)
    ok(new_resolved_module_ref(typed_module, module_ref.location))
  of TMRK_GENERIC:
    let untyped_generic = ? module_ref.generic
    let typed_generic = ? module.find_generic(untyped_generic)
    if typed_generic != generic:
      return err(fmt"{module_ref.location} expected generic `{generic.name.asl}` but found `{typed_generic.name.asl}`")

    ok(new_resolved_module_ref(typed_generic, module_ref.location))
  of TMRK_USER:
    let untyped_module = ? module_ref.user_module
    let typed_module = ? file.find_module(untyped_module)
    if typed_module == module:
      return err(fmt"{module_ref.location} module `{typed_module.name.asl}` can not be passed as an argument to generic constraint `{generic.name.asl}`")

    let children = ? module_ref.children
    if children.len != typed_module.generics.len:
      return err(fmt"{module_ref.location} module `{typed_module.name.asl}` expects `{typed_module.generics.len}` generics but found `{children.len}`")

    var resolved_children: seq[ResolvedModuleRef]
    for (typed_generic, child) in zip(typed_module.generics, children):
      let resolved_child = ? resolve_def(file, module, generic, child)
      resolved_children.add(resolved_child)
      # NOTE: Check that resolved child satifies constraints.
      for def in typed_generic.concrete_defs(child.self()):
        discard ? resolved_child.find_function(def)
    ok(new_resolved_module_ref(typed_module, resolved_children,
        module_ref.location))

proc resolve_def*(file: TypedFile, module: TypedModule,
    module_ref: TypedModuleRef): Result[ResolvedModuleRef, string] =
  case module_ref.kind:
  of TMRK_NATIVE:
    let untyped_module = ? module_ref.native_module
    let typed_module = ? file.find_module(untyped_module)
    ok(new_resolved_module_ref(typed_module, module_ref.location))
  of TMRK_GENERIC:
    let untyped_generic = ? module_ref.generic
    let typed_generic = ? module.find_generic(untyped_generic)

    ok(new_resolved_module_ref(typed_generic, module_ref.location))
  of TMRK_USER:
    let untyped_module = ? module_ref.user_module
    let typed_module = ? file.find_module(untyped_module)

    let children = ? module_ref.children
    if children.len != typed_module.generics.len:
      return err(fmt"{module_ref.location} module `{typed_module.name.asl}` expects `{typed_module.generics.len}` generics but found `{children.len}`")

    var resolved_children: seq[ResolvedModuleRef]
    for (typed_generic, child) in zip(typed_module.generics, children):
      let resolved_child = ? resolve_def(file, module, child)
      resolved_children.add(resolved_child)
      # NOTE: Check that resolved child satifies constraints.
      for def in typed_generic.concrete_defs(child.self()):
        discard ? resolved_child.find_function(def)
    ok(new_resolved_module_ref(typed_module, resolved_children,
        module_ref.location))

proc resolve_def*(file: TypedFile, module_ref: TypedModuleRef): Result[
    ResolvedModuleRef, string] =
  case module_ref.kind:
  of TMRK_NATIVE:
    let untyped_module = ? module_ref.native_module
    let typed_module = ? file.find_module(untyped_module)
    ok(new_resolved_module_ref(typed_module, module_ref.location))
  of TMRK_GENERIC:
    err(fmt"{module_ref.location} file level functions do not support generics")
  of TMRK_USER:
    let untyped_module = ? module_ref.user_module
    let typed_module = ? file.find_module(untyped_module)

    let children = ? module_ref.children
    if children.len != typed_module.generics.len:
      return err(fmt"{module_ref.location} module `{typed_module.name.asl}` expects `{typed_module.generics.len}` generics but found `{children.len}`")

    var resolved_children: seq[ResolvedModuleRef]
    for (typed_generic, child) in zip(typed_module.generics, children):
      let resolved_child = ? resolve_def(file, child)
      resolved_children.add(resolved_child)
      # NOTE: Check that resolved child satifies constraints.
      for def in typed_generic.concrete_defs(child.self()):
        discard ? resolved_child.find_function(def)
    ok(new_resolved_module_ref(typed_module, resolved_children,
        module_ref.location))

type ResolvedArgumentDefinition = ref object of RootObj
  name: Identifier
  module_ref: ResolvedModuleRef

proc new_resolved_argument_definition(module_ref: ResolvedModuleRef,
    name: Identifier): ResolvedArgumentDefinition =
  ResolvedArgumentDefinition(name: name, module_ref: module_ref)

proc concretize(arg: ResolvedArgumentDefinition, concrete_map: Table[
    TypedGeneric, ResolvedModuleRef]): ResolvedArgumentDefinition =
  let concretized_module_ref = arg.module_ref.concretize(concrete_map)
  new_resolved_argument_definition(concretized_module_ref, arg.name)

proc asl(arg: ResolvedArgumentDefinition): string =
  fmt"{arg.module_ref.asl} {arg.name.asl}"

proc resolve_def(file: TypedFile, module: TypedModule, generic: TypedGeneric,
    arg: TypedArgumentDefinition): Result[ResolvedArgumentDefinition, string] =
  let resolved_module_ref = ? resolve_def(file, module, generic, arg.module_ref)
  ? resolved_module_ref.can_be_argument
  ok(new_resolved_argument_definition(resolved_module_ref, arg.name))

proc resolve_def(file: TypedFile, module: TypedModule,
    arg: TypedArgumentDefinition): Result[ResolvedArgumentDefinition, string] =
  let resolved_module_ref = ? resolve_def(file, module, arg.module_ref)
  ? resolved_module_ref.can_be_argument
  ok(new_resolved_argument_definition(resolved_module_ref, arg.name))

proc resolve_def(file: TypedFile, arg: TypedArgumentDefinition): Result[
    ResolvedArgumentDefinition, string] =
  let resolved_module_ref = ? resolve_def(file, arg.module_ref)
  ? resolved_module_ref.can_be_argument
  ok(new_resolved_argument_definition(resolved_module_ref, arg.name))

type ResolvedFunctionDefinition = ref object of RootObj
  name: Identifier
  args: seq[ResolvedArgumentDefinition]
  returns: ResolvedModuleRef
  location: Location

proc new_resolved_function_definition(name: Identifier, args: seq[
    ResolvedArgumentDefinition], returns: ResolvedModuleRef,
    location: Location): ResolvedFunctionDefinition =
  ResolvedFunctionDefinition(name: name, args: args, returns: returns,
      location: location)

proc arity(def: ResolvedFunctionDefinition): uint = def.args.len.uint
proc concretize(def: ResolvedFunctionDefinition, concrete_map: Table[
    TypedGeneric, ResolvedModuleRef]): ResolvedFunctionDefinition =
  var concretized_args: seq[ResolvedArgumentDefinition]
  for arg in def.args:
    concretized_args.add(arg.concretize(concrete_map))
  let concretized_returns = def.returns.concretize(concrete_map)
  new_resolved_function_definition(def.name, concretized_args,
      concretized_returns, def.location)

proc asl(def: ResolvedFunctionDefinition): string =
  let args = def.args.map_it(it.asl).join(", ")
  fmt"fn {def.name.asl}({args}): {def.returns.asl}"

proc resolve_def(file: TypedFile, module: TypedModule, generic: TypedGeneric,
    def: TypedFunctionDefinition): Result[ResolvedFunctionDefinition, string] =
  var resolved_args: seq[ResolvedArgumentDefinition]
  for arg in def.args:
    let resolved_arg = ? resolve_def(file, module, generic, arg)
    resolved_args.add(resolved_arg)
  let resolved_returns = ? resolve_def(file, module, generic, def.returns)
  ok(new_resolved_function_definition(def.name, resolved_args, resolved_returns, def.location))

proc resolve_def(file: TypedFile, module: TypedModule,
    def: TypedFunctionDefinition): Result[ResolvedFunctionDefinition, string] =
  var resolved_args: seq[ResolvedArgumentDefinition]
  for arg in def.args:
    let resolved_arg = ? resolve_def(file, module, arg)
    resolved_args.add(resolved_arg)
  let resolved_returns = ? resolve_def(file, module, def.returns)
  ok(new_resolved_function_definition(def.name, resolved_args, resolved_returns, def.location))

proc resolve_def(file: TypedFile, def: TypedFunctionDefinition): Result[
    ResolvedFunctionDefinition, string] =
  var resolved_args: seq[ResolvedArgumentDefinition]
  for arg in def.args:
    let resolved_arg = ? resolve_def(file, arg)
    resolved_args.add(resolved_arg)
  let resolved_returns = ? resolve_def(file, def.returns)
  ok(new_resolved_function_definition(def.name, resolved_args, resolved_returns, def.location))

type ResolvedGeneric = ref object of RootObj
  name: Identifier
  defs: seq[ResolvedFunctionDefinition]
  defs_map: Table[Identifier, Table[uint, seq[ResolvedFunctionDefinition]]]
  location: Location

proc new_resolved_generic(name: Identifier, defs: seq[
    ResolvedFunctionDefinition], location: Location): ResolvedGeneric =
  var defs_map: Table[Identifier, Table[uint, seq[ResolvedFunctionDefinition]]]
  for def in defs:
    if def.name notin defs_map:
      defs_map[def.name] = init_table[uint, seq[ResolvedFunctionDefinition]]()
    if def.arity notin defs_map[def.name]:
      defs_map[def.name][def.arity] = new_seq[ResolvedFunctionDefinition]()
    defs_map[def.name][def.arity].add(def)
  ResolvedGeneric(name: name, defs: defs, defs_map: defs_map,
      location: location)

proc find_function_defs(generic: ResolvedGeneric, name: Identifier,
    arity: uint): Result[seq[ResolvedFunctionDefinition], string] =
  if name notin generic.defs_map:
    err(fmt"generic `{generic.name.asl}` does not have any constraint named `{name.asl}`")
  elif arity notin generic.defs_map[name]:
    err(fmt"generic `{generic.name.asl}` does not have any constraint named `{name.asl}` with arity `{arity}`")
  else:
    ok(generic.defs_map[name][arity])

proc resolve_def(file: TypedFile, module: TypedModule,
    generic: TypedGeneric): Result[ResolvedGeneric, string] =
  var resolved_defs: seq[ResolvedFunctionDefinition]
  for def in generic.defs:
    let resolved_def = ? resolve_def(file, module, generic, def)
    resolved_defs.add(resolved_def)
  ok(new_resolved_generic(generic.name, resolved_defs, generic.location))

type
  ResolvedStructKind = enum
    RSK_DEFAULT, RSK_NAMED
  ResolvedStruct = ref object of RootObj
    location: Location
    fields: seq[ResolvedArgumentDefinition]
    fields_map: Table[Identifier, ResolvedArgumentDefinition]
    case kind: ResolvedStructKind
    of RSK_DEFAULT: discard
    of RSK_NAMED: name: Identifier

proc new_resolved_struct(fields: seq[ResolvedArgumentDefinition],
    location: Location): ResolvedStruct =
  var fields_map: Table[Identifier, ResolvedArgumentDefinition]
  for field in fields: fields_map[field.name] = field
  ResolvedStruct(kind: RSK_DEFAULT, fields: fields, fields_map: fields_map,
      location: location)

proc new_resolved_struct(name: Identifier, fields: seq[
    ResolvedArgumentDefinition], location: Location): ResolvedStruct =
  var fields_map: Table[Identifier, ResolvedArgumentDefinition]
  for field in fields: fields_map[field.name] = field
  ResolvedStruct(kind: RSK_NAMED, name: name, fields: fields,
      fields_map: fields_map, location: location)

proc concretize(struct: ResolvedStruct, concrete_map: Table[TypedGeneric,
    ResolvedModuleRef]): ResolvedStruct =
  var concretized_fields: seq[ResolvedArgumentDefinition]
  for field in struct.fields:
    concretized_fields.add(field.concretize(concrete_map))

  case struct.kind:
  of RSK_DEFAULT: new_resolved_struct(concretized_fields, struct.location)
  of RSK_NAMED: new_resolved_struct(struct.name, concretized_fields,
      struct.location)

proc find_field(struct: ResolvedStruct, field: Identifier): Result[
    ResolvedArgumentDefinition, string] =
  if field in struct.fields_map:
    ok(struct.fields_map[field])
  else:
    err(fmt"{field.location} field is not defined in the struct")

proc resolve_def(file: TypedFile, module: TypedModule,
    struct: TypedStruct): Result[ResolvedStruct, string] =
  var resolved_fields: seq[ResolvedArgumentDefinition]
  for field in struct.fields:
    let resolved_field = ? resolve_def(file, module, field)
    resolved_fields.add(resolved_field)

  case struct.kind:
  of TSK_DEFAULT:
    ok(new_resolved_struct(resolved_fields, struct.location))
  of TSK_NAMED:
    let struct_name = ? struct.name
    ok(new_resolved_struct(struct_name, resolved_fields, struct.location))

type ResolvedModuleDefinition = ref object of RootObj
  name: Identifier
  location: Location
  generics: seq[ResolvedGeneric]
  generics_map: Table[TypedGeneric, ResolvedGeneric]
  structs: seq[ResolvedStruct]
  default_struct_index: int
  structs_map: Table[Identifier, ResolvedStruct]
  function_defs: seq[ResolvedFunctionDefinition]
  function_defs_map: Table[TypedFunctionDefinition, ResolvedFunctionDefinition]
  function_signatures_map: Table[Identifier, Table[uint, seq[
      ResolvedFunctionDefinition]]]

proc new_resolved_module_definition(
    name: Identifier,
    generics: seq[(TypedGeneric, ResolvedGeneric)],
    structs: seq[ResolvedStruct],
    function_defs: seq[(TypedFunctionDefinition, ResolvedFunctionDefinition)],
    location: Location): ResolvedModuleDefinition =
  var generics_map: Table[TypedGeneric, ResolvedGeneric]
  var resolved_generics: seq[ResolvedGeneric]
  for (typed_generic, resolved_generic) in generics:
    generics_map[typed_generic] = resolved_generic
    resolved_generics.add(resolved_generic)

  var default_struct_index = -1
  var structs_map: Table[Identifier, ResolvedStruct]
  var resolved_structs: seq[ResolvedStruct]
  for index, resolved_struct in structs.pairs:
    resolved_structs.add(resolved_struct)
    case resolved_struct.kind:
    of RSK_DEFAULT: default_struct_index = index
    of RSK_NAMED: structs_map[resolved_struct.name] = resolved_struct

  var function_defs_map: Table[TypedFunctionDefinition, ResolvedFunctionDefinition]
  var resolved_function_defs: seq[ResolvedFunctionDefinition]
  var function_signatures_map: Table[Identifier, Table[uint,
      seq[ResolvedFunctionDefinition]]]
  for (typed_function_def, resolved_function_def) in function_defs:
    function_defs_map[typed_function_def] = resolved_function_def
    resolved_function_defs.add(resolved_function_def)

    if resolved_function_def.name notin function_signatures_map:
      function_signatures_map[resolved_function_def.name] = init_table[uint,
          seq[ResolvedFunctionDefinition]]()
    if resolved_function_def.arity notin function_signatures_map[
        resolved_function_def.name]:
      function_signatures_map[resolved_function_def.name][
          resolved_function_def.arity] = new_seq[ResolvedFunctionDefinition]()
    function_signatures_map[resolved_function_def.name][
        resolved_function_def.arity].add(resolved_function_def)

  ResolvedModuleDefinition(
    name: name, location: location,
    generics: resolved_generics, generics_map: generics_map,
    structs: resolved_structs, structs_map: structs_map,
    function_defs: resolved_function_defs, function_defs_map: function_defs_map,
    function_signatures_map: function_signatures_map
  )

proc find_generic(module_def: ResolvedModuleDefinition,
    generic: TypedGeneric): Result[ResolvedGeneric, string] =
  if generic notin module_def.generics_map:
    err(fmt"module `{module_def.name.asl}` does not have any generic named `{generic.name.asl}`")
  else:
    ok(module_def.generics_map[generic])

proc find_struct(module_def: ResolvedModuleDefinition): Result[ResolvedStruct, string] =
  if module_def.default_struct_index == -1:
    err(fmt"module `{module_def.name.asl}` does not have a default struct")
  else:
    ok(module_def.structs[module_def.default_struct_index])

proc find_struct(module_def: ResolvedModuleDefinition,
    name: Identifier): Result[ResolvedStruct, string] =
  if name notin module_def.structs_map:
    err(fmt"module `{module_def.name.asl}` does not have struct named `{name.asl}`")
  else:
    ok(module_def.structs_map[name])

proc find_function_def(module_def: ResolvedModuleDefinition,
    function_def: TypedFunctionDefinition): Result[ResolvedFunctionDefinition, string] =
  if function_def notin module_def.function_defs_map:
    err(fmt"module `{module_def.name.asl}` does not have any function named `{function_def.name.asl}`")
  else:
    ok(module_def.function_defs_map[function_def])

proc find_function_defs(module_def: ResolvedModuleDefinition,
    name: Identifier, arity: uint): Result[seq[
    ResolvedFunctionDefinition], string] =
  if name notin module_def.function_signatures_map:
    err(fmt"module `{module_def.name.asl}` does not have any function named `{name.asl}`")
  elif arity notin module_def.function_signatures_map[name]:
    err(fmt"module `{module_def.name.asl}` does not have any function named `{name.asl}` with arity `{arity}`")
  else:
    ok(module_def.function_signatures_map[name][arity])

proc resolve_def(file: TypedFile, module: TypedModule): Result[
    ResolvedModuleDefinition, string] =
  var generics: seq[(TypedGeneric, ResolvedGeneric)]
  for generic in module.generics:
    let resolved_generic = ? resolve_def(file, module, generic)
    generics.add((generic, resolved_generic))

  var structs: seq[ResolvedStruct]
  for struct in module.structs:
    let resolved_struct = ? resolve_def(file, module, struct)
    structs.add(resolved_struct)

  var function_defs: seq[(TypedFunctionDefinition,
      ResolvedFunctionDefinition)]
  for function in module.functions:
    let resolved_def = ? resolve_def(file, module, function.def)
    function_defs.add((function.def, resolved_def))

  ok(new_resolved_module_definition(module.name, generics, structs,
      function_defs, module.location))

type ResolvedNativeFunctionDefinition = ref object of RootObj
  native: string
  def: ResolvedFunctionDefinition

proc new_resolved_native_function_definition(native: string,
    def: ResolvedFunctionDefinition): ResolvedNativeFunctionDefinition =
  ResolvedNativeFunctionDefinition(native: native, def: def)

proc name*(def: ResolvedNativeFunctionDefinition): Identifier = def.def.name
proc arity*(def: ResolvedNativeFunctionDefinition): uint = def.def.arity.uint

proc resolve_def(file: TypedFile, function: TypedNativeFunction): Result[
    ResolvedNativeFunctionDefinition, string] =
  let resolved_def = ? resolve_def(file, function.def)
  ok(new_resolved_native_function_definition(function.native, resolved_def))

type ResolvedNativeModuleDefinition = ref object of RootObj
  name: Identifier
  functions: seq[ResolvedNativeFunctionDefinition]
  function_signatures_map: Table[Identifier, Table[uint, seq[
      ResolvedNativeFunctionDefinition]]]

proc new_resolved_native_module_definition(name: Identifier, functions: seq[
    ResolvedNativeFunctionDefinition]): ResolvedNativeModuleDefinition =
  var function_signatures_map: Table[Identifier, Table[uint, seq[
      ResolvedNativeFunctionDefinition]]]
  for function in functions:
    if function.name notin function_signatures_map:
      function_signatures_map[function.name] = init_table[uint, seq[
          ResolvedNativeFunctionDefinition]]()
    if function.arity notin function_signatures_map[function.name]:
      function_signatures_map[function.name][function.arity] = new_seq[
          ResolvedNativeFunctionDefinition]()
    function_signatures_map[function.name][function.arity].add(function)
  ResolvedNativeModuleDefinition(name: name, functions: functions,
      function_signatures_map: function_signatures_map)

proc find_function_defs(module_def: ResolvedNativeModuleDefinition,
    name: Identifier, arity: uint): Result[seq[
    ResolvedNativeFunctionDefinition], string] =
  if name notin module_def.function_signatures_map:
    err(fmt"native module `{module_def.name.asl}` does not have any function named `{name.asl}`")
  elif arity notin module_def.function_signatures_map[name]:
    err(fmt"native module `{module_def.name.asl}` does not have any function named `{name.asl}` with arity `{arity}`")
  else:
    ok(module_def.function_signatures_map[name][arity])

proc resolve_def(file: TypedFile, def: TypedNativeModule): Result[
    ResolvedNativeModuleDefinition, string] =
  var resolved_functions: seq[ResolvedNativeFunctionDefinition]
  for function in def.functions:
    let resolved_function = ? resolve_def(file, function)
    resolved_functions.add(resolved_function)
  ok(new_resolved_native_module_definition(def.name, resolved_functions))

type ResolvedFileDefinition = ref object of RootObj
  native_modules: seq[ResolvedNativeModuleDefinition]
  native_modules_map: Table[TypedNativeModule, ResolvedNativeModuleDefinition]
  modules: seq[ResolvedModuleDefinition]
  modules_map: Table[TypedModule, ResolvedModuleDefinition]
  function_defs: seq[ResolvedFunctionDefinition]
  function_defs_map: Table[TypedFunctionDefinition, ResolvedFunctionDefinition]
  function_signatures_map: Table[Identifier, Table[uint,
      seq[ResolvedFunctionDefinition]]]

proc new_resolved_file_definition(
    native_modules: seq[(TypedNativeModule, ResolvedNativeModuleDefinition)],
    modules: seq[(TypedModule, ResolvedModuleDefinition)],
    function_defs: seq[(TypedFunctionDefinition,
        ResolvedFunctionDefinition)]): ResolvedFileDefinition =
  var native_modules_map: Table[TypedNativeModule, ResolvedNativeModuleDefinition]
  var resolved_native_modules: seq[ResolvedNativeModuleDefinition]
  for (typed_module, resolved_module) in native_modules:
    native_modules_map[typed_module] = resolved_module
    resolved_native_modules.add(resolved_module)

  var modules_map: Table[TypedModule, ResolvedModuleDefinition]
  var resolved_modules: seq[ResolvedModuleDefinition]
  for (typed_module, resolved_module) in modules:
    modules_map[typed_module] = resolved_module
    resolved_modules.add(resolved_module)

  var function_defs_map: Table[TypedFunctionDefinition, ResolvedFunctionDefinition]
  var function_signatures_map: Table[Identifier, Table[uint,
      seq[ResolvedFunctionDefinition]]]
  var resolved_function_defs: seq[ResolvedFunctionDefinition]
  for (typed_function_def, resolved_function_def) in function_defs:
    function_defs_map[typed_function_def] = resolved_function_def
    resolved_function_defs.add(resolved_function_def)

    if resolved_function_def.name notin function_signatures_map:
      function_signatures_map[resolved_function_def.name] = init_table[uint,
          seq[ResolvedFunctionDefinition]]()
    if resolved_function_def.arity notin function_signatures_map[
        resolved_function_def.name]:
      function_signatures_map[resolved_function_def.name][
          resolved_function_def.arity] = new_seq[ResolvedFunctionDefinition]()
    function_signatures_map[resolved_function_def.name][
          resolved_function_def.arity].add(resolved_function_def)

  ResolvedFileDefinition(
    native_modules: resolved_native_modules,
    native_modules_map: native_modules_map,
    modules: resolved_modules, modules_map: modules_map,
    function_defs: resolved_function_defs, function_defs_map: function_defs_map
  )

proc find_module_def(file_def: ResolvedFileDefinition,
    module: TypedNativeModule): Result[ResolvedNativeModuleDefinition, string] =
  if module in file_def.native_modules_map:
    ok(file_def.native_modules_map[module])
  else:
    err(fmt"module `{module.name.asl}` not found in resolved file definition")

proc find_module_def(file_def: ResolvedFileDefinition,
    module: TypedModule): Result[ResolvedModuleDefinition, string] =
  if module in file_def.modules_map:
    ok(file_def.modules_map[module])
  else:
    err(fmt"module `{module.name.asl}` not found in resolved file definition")

proc find_function_defs(file_def: ResolvedFileDefinition, name: Identifier,
    arity: uint): Result[seq[ResolvedFunctionDefinition], string] =
  if name notin file_def.function_signatures_map:
    err(fmt"function `{name.asl}` not found in resolved file definition")
  elif arity notin file_def.function_signatures_map[name]:
    err(fmt"function `{name.asl}` with arity `{arity}` not found in resolved file definition")
  else:
    ok(file_def.function_signatures_map[name][arity])

proc resolve_def(file: TypedFile): Result[ResolvedFileDefinition, string] =
  var native_modules: seq[(TypedNativeModule, ResolvedNativeModuleDefinition)]
  for module in file.native_modules:
    let resolved_module_def = ? resolve_def(file, module)
    native_modules.add((module, resolved_module_def))

  var modules: seq[(TypedModule, ResolvedModuleDefinition)]
  for module in file.modules:
    let resolved_module_def = ? resolve_def(file, module)
    modules.add((module, resolved_module_def))

  var function_defs: seq[(TypedFunctionDefinition, ResolvedFunctionDefinition)]
  for function in file.functions:
    let resolved_function_def = ? resolve_def(file, function.def)
    function_defs.add((function.def, resolved_function_def))

  ok(new_resolved_file_definition(native_modules, modules, function_defs))

type FunctionScope = ref object of RootObj
  table: Table[Identifier, ResolvedModuleRef]

proc get(scope: FunctionScope, name: Identifier): Result[ResolvedModuleRef, string] =
  if name notin scope.table:
    return err(fmt"{name.location} argument `{name.asl}` is not present in the scope")
  ok(scope.table[name])

proc set(scope: FunctionScope, arg: ResolvedArgumentDefinition): Result[
    FunctionScope, string] =
  scope.table[arg.name] = arg.module_ref
  ok(scope)

type
  ResolvedFunctionRefKind = enum
    RFRK_LOCAL, RFRK_MODULE
  ResolvedFunctionRef = ref object of RootObj
    name: Identifier
    defs: seq[ResolvedFunctionDefinition]
    case kind: ResolvedFunctionRefKind
    of RFRK_LOCAL: discard
    of RFRK_MODULE: module_ref: ResolvedModuleRef

proc new_resolved_function_ref(name: Identifier, defs: seq[
    ResolvedFunctionDefinition]): ResolvedFunctionRef =
  ResolvedFunctionRef(kind: RFRK_LOCAL, name: name, defs: defs)

proc new_resolved_function_ref(module_ref: ResolvedModuleRef, name: Identifier,
    defs: seq[ResolvedFunctionDefinition]): ResolvedFunctionRef =
  ResolvedFunctionRef(kind: RFRK_MODULE, module_ref: module_ref, name: name, defs: defs)

proc resolve(file_def: ResolvedFileDefinition, file: TypedFile,
    module_def: ResolvedModuleDefinition, module: TypedModule,
    fnref: TypedFunctionRef): Result[ResolvedFunctionRef, string] =
  case fnref.kind:
  of TFRK_LOCAL:
    let resolved_function_defs = ? file_def.find_function_defs(fnref.name, fnref.arity)
    ok(new_resolved_function_ref(fnref.name, resolved_function_defs))
  of TFRK_MODULE:
    let typed_module_ref = ? fnref.module_ref
    let resolved_module_ref = ? resolve_def(file, module, typed_module_ref)
    case resolved_module_ref.kind:
    of RMRK_NATIVE:
      let typed_native_module = resolved_module_ref.native_module
      let resolved_native_module_def = ? file_def.find_module_def(typed_native_module)
      let resolved_native_function_defs = ? resolved_native_module_def.find_function_defs(
          fnref.name, fnref.arity)
      let resolved_function_defs = resolved_native_function_defs.map_it(it.def)
      ok(new_resolved_function_ref(resolved_module_ref, fnref.name,
          resolved_function_defs))
    of RMRK_GENERIC:
      let typed_generic = resolved_module_ref.generic
      let resolved_generic = ? module_def.find_generic(typed_generic)

      let resolved_function_defs = ? resolved_generic.find_function_defs(
          fnref.name, fnref.arity)
      ok(new_resolved_function_ref(resolved_module_ref, fnref.name,
          resolved_function_defs))
    of RMRK_USER:
      let typed_user_module = resolved_module_ref.user_module
      let resolved_user_module_def = ? file_def.find_module_def(typed_user_module)
      let resolved_function_defs = ? resolved_user_module_def.find_function_defs(
          fnref.name, fnref.arity)
      var concrete_function_defs = resolved_function_defs.map_it(it.concretize(
          resolved_module_ref.concrete_map))
      ok(new_resolved_function_ref(resolved_module_ref, fnref.name,
          concrete_function_defs))

type
  ResolvedArgumentKind = enum
    RAK_VARIABLE, RAK_LITERAL
  ResolvedArgument = ref object of RootObj
    module_ref: ResolvedModuleRef
    case kind: ResolvedArgumentKind
    of RAK_LITERAL: literal: Literal
    of RAK_VARIABLE: variable: Identifier

proc new_resolved_argument(module_ref: ResolvedModuleRef,
    variable: Identifier): ResolvedArgument =
  ResolvedArgument(kind: RAK_VARIABLE, module_ref: module_ref,
      variable: variable)

proc new_resolved_argument(module_ref: ResolvedModuleRef,
    literal: Literal): ResolvedArgument =
  ResolvedArgument(kind: RAK_LITERAL, module_ref: module_ref, literal: literal)

proc location(arg: ResolvedArgument): Location =
  case arg.kind:
  of RAK_LITERAL: arg.literal.location
  of RAK_VARIABLE: arg.variable.location

proc resolve(module: ResolvedNativeModuleDefinition, literal: Literal): Result[
    void, string] =
  err(fmt"todo: resolve literal")

proc resolve(file_def: ResolvedFileDefinition, file: TypedFile,
    module_def: ResolvedModuleDefinition, module: TypedModule,
    scope: FunctionScope, args: seq[Argument],
    argdefs: seq[ResolvedArgumentDefinition]): Result[seq[ResolvedArgument], string] =
  var resolved_args: seq[ResolvedArgument]
  for (arg, def) in zip(args, argdefs):
    case arg.kind:
    of AK_VARIABLE:
      let variable = ? arg.variable
      let arg_module_ref = ? scope.get(variable)
      if arg_module_ref != def.module_ref:
        return err(fmt"{arg.location} expected `{variable.asl}` to be of type `{def.module_ref.asl}` but found `{arg_module_ref.asl}`")
      resolved_args.add(new_resolved_argument(arg_module_ref, variable))
    of AK_LITERAL:
      let literal = ? arg.literal
      case def.module_ref.kind:
      of RMRK_NATIVE:
        let native_module = def.module_ref.native_module
        let resolved_native_module = ? file_def.find_module_def(native_module)
        ? resolve(resolved_native_module, literal)
        resolved_args.add(new_resolved_argument(def.module_ref, literal))
      else:
        return err(fmt"{literal.location} module `{def.module_ref.asl}` does not support literals")
  ok(resolved_args)

type ResolvedFunctionCall = ref object of RootObj
  fnref: ResolvedFunctionRef
  def: ResolvedFunctionDefinition
  args: seq[ResolvedArgument]

proc new_resolved_function_call(fnref: ResolvedFunctionRef,
    def: ResolvedFunctionDefinition, args: seq[
    ResolvedArgument]): ResolvedFunctionCall =
  ResolvedFunctionCall(fnref: fnref, def: def, args: args)

proc returns(fncall: ResolvedFunctionCall): ResolvedModuleRef =
  fncall.def.returns

proc resolve(file_def: ResolvedFileDefinition, file: TypedFile,
    module_def: ResolvedModuleDefinition, module: TypedModule,
    scope: FunctionScope, fncall: TypedFunctionCall): Result[
        ResolvedFunctionCall, string] =
  let resolved_function_ref = ? resolve(file_def, file, module_def, module, fncall.fnref)
  var error_message = @[fmt"{fncall.location} failed to find matching function call:"]
  for function_def in resolved_function_ref.defs:
    let maybe_resolved_args = resolve(file_def, file, module_def, module, scope,
        fncall.args, function_def.args)
    if maybe_resolved_args.is_ok:
      return ok(new_resolved_function_call(resolved_function_ref, function_def,
          maybe_resolved_args.get))
    error_message.add(function_def.asl)
  err(error_message.join("\n"))

type ResolvedStructRef = ref object of RootObj
  module_ref: ResolvedModuleRef
  struct: ResolvedStruct

proc new_resolved_struct_ref(module_ref: ResolvedModuleRef,
    struct: ResolvedStruct): ResolvedStructRef =
  ResolvedStructRef(module_ref: module_ref, struct: struct)

proc resolve(file_def: ResolvedFileDefinition, file: TypedFile,
    module_def: ResolvedModuleDefinition, module: TypedModule,
    scope: FunctionScope, struct_ref: TypedStructRef): Result[ResolvedStructRef, string] =
  let resolved_module_ref = ? resolve_def(file, module, struct_ref.module_ref)
  case resolved_module_ref.kind:
  of RMRK_NATIVE:
    err(fmt"{struct_ref.location} native module `{resolved_module_ref.native_module.name.asl}` is not a struct")
  of RMRK_GENERIC:
    err(fmt"{struct_ref.location} generic `{resolved_module_ref.generic.name.asl}` is not a struct")
  of RMRK_USER:
    let typed_module = resolved_module_ref.user_module
    let resolved_module_def = ? file_def.find_module_def(typed_module)
    case struct_ref.kind:
    of TSRK_DEFAULT:
      let maybe_struct = resolved_module_def.find_struct()
      if maybe_struct.is_ok:
        let resolved_struct = maybe_struct.get
        let resolved_concretized_struct = resolved_struct.concretize(
            resolved_module_ref.concrete_map)
        ok(new_resolved_struct_ref(resolved_module_ref,
            resolved_concretized_struct))
      else:
        err(fmt"{struct_ref.location} module `{resolved_module_def.name.asl}` does not have a default struct")
    of TSRK_NAMED:
      let struct_name = ? struct_ref.name
      let maybe_struct = resolved_module_def.find_struct(struct_name)
      if maybe_struct.is_ok:
        let resolved_struct = maybe_struct.get
        let resolved_concretized_struct = resolved_struct.concretize(
            resolved_module_ref.concrete_map)
        ok(new_resolved_struct_ref(resolved_module_ref,
            resolved_concretized_struct))
      else:
        err(fmt"{struct_ref.location} module `{resolved_module_def.name.asl}` does not have a struct named `{struct_name.asl}`")

type ResolvedStructInit = ref object of RootObj
  struct_ref: ResolvedStructRef
  fields: seq[ResolvedArgument]

proc new_resolved_struct_init(struct_ref: ResolvedStructRef, fields: seq[
    ResolvedArgument]): ResolvedStructInit =
  ResolvedStructInit(struct_ref: struct_ref, fields: fields)

proc returns(struct_init: ResolvedStructInit): ResolvedModuleRef =
  struct_init.struct_ref.module_ref

proc resolve(file_def: ResolvedFileDefinition, file: TypedFile,
    module_def: ResolvedModuleDefinition, module: TypedModule,
    scope: FunctionScope, init: TypedStructInit): Result[ResolvedStructInit, string] =
  let resolved_struct_ref = ? resolve(file_def, file, module_def, module, scope,
      init.struct_ref)
  var args: seq[Argument]
  for field in resolved_struct_ref.struct.fields:
    args.add( ? init.get(field.name))
  let resolved_fields = ? resolve(file_def, file, module_def, module, scope,
      args, resolved_struct_ref.struct.fields)
  ok(new_resolved_struct_init(resolved_struct_ref, resolved_fields))

type
  ResolvedInitializerKind = enum
    RIK_STRUCT
  ResolvedInitializer = ref object of RootObj
    case kind: ResolvedInitializerKind
    of RIK_STRUCT: struct: ResolvedStructInit

proc new_resolved_initializer(struct: ResolvedStructInit): ResolvedInitializer =
  ResolvedInitializer(kind: RIK_STRUCT, struct: struct)

proc returns(init: ResolvedInitializer): ResolvedModuleRef =
  case init.kind:
  of RIK_STRUCT: init.struct.returns

proc resolve(file_def: ResolvedFileDefinition, file: TypedFile,
    module_def: ResolvedModuleDefinition, module: TypedModule,
    scope: FunctionScope, init: TypedInitializer): Result[ResolvedInitializer, string] =
  case init.kind:
  of TIK_STRUCT:
    let struct_init = ? init.struct
    let resolved_struct_init = ? resolve(file_def, file, module_def, module,
        scope, struct_init)
    ok(new_resolved_initializer(resolved_struct_init))
  of TIK_LITERAL:
    let literal_init = ? init.literal
    err(fmt"{init.location} todo: resolve initializer")


type ResolvedStructGet = ref object of RootObj
  variable: ResolvedArgumentDefinition
  field: ResolvedArgumentDefinition

proc new_resolved_struct_get(variable: ResolvedArgumentDefinition,
    field: ResolvedArgumentDefinition): ResolvedStructGet =
  ResolvedStructGet(variable: variable, field: field)

proc returns(struct_get: ResolvedStructGet): ResolvedModuleRef =
  struct_get.field.module_ref

proc resolve(file_def: ResolvedFileDefinition, file: TypedFile,
    module_def: ResolvedModuleDefinition, module: TypedModule,
    scope: FunctionScope, struct_get: TypedStructGet): Result[ResolvedStructGet, string] =
  let resolved_module_ref = ? scope.get(struct_get.variable)
  let resolved_variable = new_resolved_argument_definition(resolved_module_ref,
      struct_get.variable)
  case resolved_module_ref.kind:
  of RMRK_NATIVE: err(fmt"{struct_get.location} variable `{struct_get.variable.asl}` is not a struct but native module")
  of RMRK_GENERIC: err(fmt"{struct_get.location} variable `{struct_get.variable.asl}` is not a struct but generic")
  of RMRK_USER:
    let typed_module = resolved_module_ref.user_module
    let resolved_module_def = ? file_def.find_module_def(typed_module)
    if resolved_module_def.structs.len == 0:
      err(fmt"{struct_get.location} module `{resolved_module_def.name.asl}` is not a struct")
    elif resolved_module_def.structs.len > 1:
      err(fmt"{struct_get.location} module `{resolved_module_def.name.asl}` is a union")
    else:
      let maybe_default_struct = resolved_module_def.find_struct()
      if maybe_default_struct.is_err:
        err(fmt"{struct_get.location} module `{resolved_module_def.name.asl}` does not have a default struct")
      else:
        let resolved_struct = maybe_default_struct.get
        let resolved_field_module_ref = ? resolved_struct.find_field(
            struct_get.field)
        let resolved_field = resolved_field_module_ref.concretize(
            resolved_module_ref.concrete_map)
        ok(new_resolved_struct_get(resolved_variable, resolved_field))

type
  ResolvedExpressionKind = enum
    REK_FNCALL, REK_INIT, REK_STRUCT_GET
  ResolvedExpression = ref object of RootObj
    case kind: ResolvedExpressionKind
    of REK_FNCALL: fncall: ResolvedFunctionCall
    of REK_INIT: init: ResolvedInitializer
    of REK_STRUCT_GET: struct_get: ResolvedStructGet

proc new_resolved_expression(fncall: ResolvedFunctionCall): ResolvedExpression =
  ResolvedExpression(kind: REK_FNCALL, fncall: fncall)

proc new_resolved_expression(init: ResolvedInitializer): ResolvedExpression =
  ResolvedExpression(kind: REK_INIT, init: init)

proc new_resolved_expression(struct_get: ResolvedStructGet): ResolvedExpression =
  ResolvedExpression(kind: REK_STRUCT_GET, struct_get: struct_get)

proc returns(expression: ResolvedExpression): ResolvedModuleRef =
  case expression.kind:
  of REK_FNCALL: expression.fncall.returns
  of REK_INIT: expression.init.returns
  of REK_STRUCT_GET: expression.struct_get.returns

proc resolve(file_def: ResolvedFileDefinition, file: TypedFile,
    module_def: ResolvedModuleDefinition, module: TypedModule,
    scope: FunctionScope, expression: TypedExpression): Result[
        ResolvedExpression, string] =
  case expression.kind:
  of TEK_FNCALL:
    let fncall = ? expression.fncall
    let resolved_function_call = ? resolve(file_def, file, module_def, module,
        scope, fncall)
    ok(new_resolved_expression(resolved_function_call))
  of TEK_INIT:
    let init = ? expression.init
    let resolved_init = ? resolve(file_def, file, module_def, module, scope, init)
    ok(new_resolved_expression(resolved_init))
  of TEK_STRUCT_GET:
    let struct_get = ? expression.struct_get
    let resolved_struct_get = ? resolve(file_def, file, module_def, module,
        scope, struct_get)
    ok(new_resolved_expression(resolved_struct_get))
  of TEK_VARIABLE:
    let variable = ? expression.variable
    err(fmt"{expression.location} todo: resolve module function expression")
  of TEK_MATCH:
    err(fmt"{expression.location} todo: resolve module function expression")

type ResolvedStatement = ref object of RootObj
  arg: Identifier
  expression: ResolvedExpression

proc new_resolved_statement(arg: Identifier,
    expression: ResolvedExpression): ResolvedStatement =
  ResolvedStatement(arg: arg, expression: expression)

proc return_arg(statement: ResolvedStatement): ResolvedArgumentDefinition =
  new_resolved_argument_definition(statement.expression.returns, statement.arg)

proc resolve(file_def: ResolvedFileDefinition, file: TypedFile,
    module_def: ResolvedModuleDefinition, module: TypedModule,
        scope: FunctionScope, statement: TypedStatement): Result[
            ResolvedStatement, string] =
  let resolved_expression = ? resolve(file_def, file, module_def, module, scope,
      statement.expression)
  ok(new_resolved_statement(statement.arg, resolved_expression))

proc resolve(file_def: ResolvedFileDefinition, file: TypedFile,
    module_def: ResolvedModuleDefinition, module: TypedModule,
        scope: FunctionScope, match: TypedMatch): Result[void, string] =
  err(fmt"{match.location} todo: resolve module function match")

type ResolvedFunction = ref object of RootObj
  def: ResolvedFunctionDefinition
  steps: seq[ResolvedStatement]

proc new_resolved_function(def: ResolvedFunctionDefinition, steps: seq[
    ResolvedStatement]): ResolvedFunction =
  ResolvedFunction(def: def, steps: steps)

proc resolve(file_def: ResolvedFileDefinition, file: TypedFile,
    module_def: ResolvedModuleDefinition, module: TypedModule,
        function: TypedFunction): Result[ResolvedFunction, string] =
  var scope = FunctionScope()
  let resolved_function_def = ? module_def.find_function_def(function.def)
  for arg in resolved_function_def.args:
    scope = ? scope.set(arg)

  var resolved_steps: seq[ResolvedStatement]
  for step in function.steps:
    let resolved_function_step = ? resolve(file_def, file, module_def, module,
        scope, step)
    resolved_steps.add(resolved_function_step)
    scope = ? scope.set(resolved_function_step.return_arg)
  ok(new_resolved_function(resolved_function_def, resolved_steps))

proc resolve(file_def: ResolvedFileDefinition, file: TypedFile,
    function: TypedFunction): Result[void, string] =
  # let resolved_function_def = ? module_def.find_function_def(function.def)
  # var scope = FunctionScope()
  # for step in function.steps:
  #   ? resolve(file_def, file, module_def, module, scope, step)
  err(fmt"todo: resolve function")

proc resolve(file_def: ResolvedFileDefinition, file: TypedFile,
    module_def: ResolvedModuleDefinition, module: TypedModule): Result[void, string] =
  var resolved_functions: seq[ResolvedFunction]
  for function in module.functions:
    let resolved_function = ? resolve(file_def, file, module_def, module, function)
    resolved_functions.add(resolved_function)
  err(fmt"todo: resolve module function")

proc resolve(file_def: ResolvedFileDefinition, file: TypedFile): Result[void, string] =
  for module in file.modules:
    let module_def = ? file_def.find_module_def(module)
    ? resolve(file_def, file, module_def, module)

  for function in file.functions:
    ? resolve(file_def, file, function)
  err(fmt"todo: resolve file")

proc resolve_v2*(file: TypedFile): Result[void, string] =
  let resolved_file_def = ? resolve_def(file)
  ? resolve(resolved_file_def, file)
  err(fmt"todo: resolve file")
