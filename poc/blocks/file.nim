import sequtils, strutils, results, strformat

import token, function, struct, statement, function_call, arg_def

type Module* = ref object of RootObj
  name*: string

proc `$`*(module: Module): string = module.name

type File* = ref object of RootObj
  location*: Location
  modules*: seq[Module]
  functions*: seq[Function]
  structs*: seq[Struct]
  builtins*: seq[FunctionDefinition]
  expanded*: seq[Function]

proc name*(file: File): string =
  file.location.filename

proc new_file*(filename: string): File =
  let modules = @["U8", "U16", "U32", "U64", "S8", "S16", "S32", "S64", "S64",
      "F32", "F64", "Pointer"].map_it(Module(name: it))
  let builtins = @[
    new_function_definition("U8_init", @[("U8", "a")], "U8"),
    new_function_definition("U8_from_Pointer", @[("Pointer", "p")], "U8"),
    new_function_definition("U8_lshift", @[("U8", "a"), ("U64", "b")], "U8"),
    new_function_definition("U8_rshift", @[("U8", "a"), ("U64", "b")], "U8"),
    new_function_definition("U8_and", @[("U8", "a"), ("U8", "b")], "U8"),
    new_function_definition("U8_or", @[("U8", "a"), ("U8", "b")], "U8"),
    new_function_definition("U8_not", @[("U8", "a")], "U8"),
    new_function_definition("U16_init", @[("U16", "a")], "U16"),
    new_function_definition("U32_init", @[("U32", "a")], "U32"),
    # U64
    new_function_definition("U64_init", @[("U64", "a")], "U64"),
    new_function_definition("U64_compare", @[("U64", "a"), ("U64", "b")],
        "U64"),
    new_function_definition("U64_add", @[("U64", "a"), ("U64", "b")], "U64"),
    new_function_definition("U64_subtract", @[("U64", "a"), ("U64", "b")],
        "U64"),
    new_function_definition("U64_multiply", @[("U64", "a"), ("U64", "b")],
        "U64"),
    new_function_definition("U64_quotient", @[("U64", "a"), ("U64", "b")],
        "U64"),
    new_function_definition("U64_remainder", @[("U64", "a"), ("U64", "b")],
        "U64"),
    new_function_definition("System_print_U64", @[("U64", "a")], "U64"),
    new_function_definition("S8_init", @[("S8", "a")], "S8"),
    new_function_definition("S16_init", @[("S16", "a")], "S16"),
    new_function_definition("S32_init", @[("S32", "a")], "S32"),
    # S64
    new_function_definition("S64_init", @[("S64", "a")], "S64"),
    new_function_definition("S64_from_U8", @[("U8", "a")], "S64"),
    new_function_definition("S64_add", @[("S64", "a"), ("S64", "b")], "S64"),
    new_function_definition("S64_subtract", @[("S64", "a"), ("S64", "b")],
        "S64"),
    new_function_definition("S64_multiply", @[("S64", "a"), ("S64", "b")],
        "S64"),
    new_function_definition("S64_quotient", @[("S64", "a"), ("S64", "b")],
        "S64"),
    new_function_definition("S64_remainder", @[("S64", "a"), ("S64", "b")],
        "S64"),
    new_function_definition("S64_compare", @[("S64", "a"), ("S64", "b")],
        "S64"),
    new_function_definition("System_print_S64", @[("S64", "a")], "U64"),
    new_function_definition("F32_init", @[("F32", "a")], "F32"),
    new_function_definition("F64_init", @[("F64", "a")], "F64"),
    new_function_definition("Pointer_init", @[("Pointer", "a")], "Pointer"),
    new_function_definition("Pointer_shift", @[("Pointer", "a"), ("U64", "b")],
        "Pointer"),
    new_function_definition("Pointer_write_U8", @[("Pointer", "a"), ("U8",
        "b")], "Pointer"),
    new_function_definition("System_allocate", @[("U64", "size")], "Pointer"),
    new_function_definition("System_free", @[("Pointer", "ptr")], "U64"),
  ]
  File(modules: modules, builtins: builtins, location: new_file_location(filename))

proc `$`*(file: File): string =
  @[
    file.structs.map_it($(it)).join("\n\n"),
    file.functions.map_it($(it)).join("\n\n")
  ].join("\n\n")

proc find_native_module*(file: File, module_name: Token): Result[Module, string] =
  for module in file.modules:
    if $(module) == $(module_name):
      return ok(module)
  err(fmt"{module_name} does not exist in the scope")

proc find_struct*(file: File, struct_name: Token): Result[Struct, string] =
  for struct in file.structs:
    if $(struct.name) == $(struct_name):
      return ok(struct)
  err(fmt"{struct_name} does not exist in the scope")

proc find_module*(file: File, module_name: Token): Result[void, string] =
  var maybe_found = file.find_native_module(module_name)
  if maybe_found.is_ok: return ok()

  discard ? file.find_struct(module_name)
  ok()

proc find_start_function*(file: File): Result[Function, string] =
  for function in file.functions:
    if function.is_start():
      return ok(function)
  err(fmt"{file.name} failed to find start function")

proc check_if_duplicate(file: File, fn: Function): Result[void, string] =
  for function in file.functions:
    if function.name != fn.name: continue
    if function.arity != fn.arity: continue

    var matched = true
    for (function_arg, fn_arg) in zip(function.arg_def_list, fn.arg_def_list):
      if $(function_arg.arg_type) != $(fn_arg.arg_type):
        matched = false
    if matched:
      return err(fmt"{fn.location} {fn.name} is already defined in {function.location}")
  ok()

proc check_if_duplicate(file: File, struct: Struct): Result[void, string] =
  for pre_defined_struct in file.structs:
    if pre_defined_struct.name == struct.name:
      return err(fmt"{struct.location} {struct.name} is already defined in {pre_defined_struct.location}")
  ok()

proc add_function*(file: File, function: Function): Result[void, string] =
  ? file.check_if_duplicate(function)
  file.functions.add(function)
  ok()

proc add_struct*(file: File, struct: Struct): Result[void, string] =
  ? file.check_if_duplicate(struct)
  file.structs.add(struct)
  ok()

proc expand_setter(struct: Struct, field: ArgumentDefinition,
    offset: uint): Function =
  let struct_var = fmt"__asl__{to_lower_ascii($(struct.name))}"
  let field_var = fmt"__asl__{field.arg_name}"

  let set_function_def = new_function_definition(
    fmt"{struct.name}_set_{field.arg_name}", @[
      ($(struct.name), struct_var),
      ($(field.arg_type), field_var),
    ], $(struct.name)
  )
  let set_function = new_function(set_function_def)

  let ptr_shift_call = new_function_call("Pointer_shift", @[struct_var, $(offset)])
  let ptr_shift_statement = new_statement("shifted_ptr", ptr_shift_call)
  set_function.add_arg_to_scope(new_argument_definition("Pointer",
      "shifted_ptr"))
  set_function.add_statement(ptr_shift_statement)

  let writable_type = field.native_type
  let ptr_write_call = new_function_call(
      fmt"Pointer_write_{writable_type}", @["shifted_ptr", field_var])
  let ptr_write_statement = new_statement("_", ptr_write_call)
  set_function.add_arg_to_scope(new_argument_definition("Pointer", "_"))
  set_function.add_statement(ptr_write_statement)

  let ptr_return_call = new_function_call(
      fmt"Pointer_init", @[struct_var])
  let ptr_return_statement = new_statement("result", ptr_return_call)
  set_function.add_arg_to_scope(new_argument_definition("Pointer", "result"))
  set_function.add_statement(ptr_return_statement)

  return set_function

proc expand_getter(struct: Struct, field: ArgumentDefinition,
    offset: uint): Function =
  let struct_var = fmt"__asl__{to_lower_ascii($(struct.name))}"

  let get_function_def = new_function_definition(
    fmt"{struct.name}_get_{field.arg_name}", @[
      ($(struct.name), struct_var),
    ], $(field.arg_type)
  )
  let get_function = new_function(get_function_def)

  let ptr_shift_call = new_function_call("Pointer_shift", @[struct_var, $(offset)])
  let ptr_shift_statement = new_statement("shifted_ptr", ptr_shift_call)
  get_function.add_arg_to_scope(new_argument_definition("Pointer",
      "shifted_ptr"))
  get_function.add_statement(ptr_shift_statement)

  let readable_type = field.native_type
  let ptr_read_call = new_function_call(fmt"{readable_type}_from_Pointer",
      @["shifted_ptr"])
  let ptr_read_statement = new_statement("result", ptr_read_call)
  get_function.add_arg_to_scope(new_argument_definition(readable_type,
      "result"))
  get_function.add_statement(ptr_read_statement)

  return get_function

proc expand*(file: File): Result[File, string] =
  for struct in file.structs:
    file.modules.add(Module(name: $(struct.name)))
    var struct_byte_size: uint = 0
    for field in struct.fields:
      # generate setter for struct
      let setter = expand_setter(struct, field, struct_byte_size)
      file.expanded.add(setter)

      # generate getter for struct
      let getter = expand_getter(struct, field, struct_byte_size)
      file.expanded.add(getter)

      struct_byte_size += field.byte_size

    # struct init function
    let init_function_name = new_id_token(fmt"{struct.name}_init")
    let init_function_def = new_function_definition(init_function_name,
        struct.fields, struct.name)
    let init_function = new_function(init_function_def)

    # struct allocate statement
    var temp_var_count = 0
    let ptr_alloc_call = new_function_call(new_id_token("System_allocate"), @[
        new_int_token(struct_byte_size)])
    let ptr_alloc_statement = new_statement(
        fmt"__asl_temp_var_{temp_var_count}__", ptr_alloc_call)
    init_function.add_arg_to_scope(new_argument_definition("Pointer",
        fmt"__asl_temp_var_{temp_var_count}__"))
    init_function.add_statement(ptr_alloc_statement)

    for field in struct.fields:
      # struct init statements
      let field_set_call = new_function_call(
        fmt"{struct.name}_set_{field.arg_name}", @[
        fmt"__asl_temp_var_{temp_var_count}__", $(field.arg_name)])
      temp_var_count += 1
      let field_set_statement = new_statement(
          fmt"__asl_temp_var_{temp_var_count}__", field_set_call)
      init_function.add_arg_to_scope(new_argument_definition("Pointer",
        fmt"__asl_temp_var_{temp_var_count}__"))
      init_function.add_statement(field_set_statement)

    file.expanded.add(init_function)

    # struct free function
    let free_function_def = new_function_definition(fmt"{struct.name}_free", @[(
        $(struct.name), "ptr")], "U64")
    let free_function = new_function(free_function_def)

    # struct free statement
    let ptr_free_call = new_function_call(fmt"System_free", @["ptr"])
    let ptr_free_statement = new_statement("result", ptr_free_call)
    free_function.add_arg_to_scope(new_argument_definition("U64", "result"))
    free_function.add_statement(ptr_free_statement)
    file.expanded.add(free_function)

  ok(file)
