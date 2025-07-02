import strformat, strutils, results

import arg_def, token, function, function_call, statement

type StructDefinition* = ref object of RootObj
  name*: Token
  location*: Location

proc `$`*(struct_definition: StructDefinition): string =
  fmt"struct {struct_definition.name}:"

proc new_struct_definition*(name: Token, location: Location): StructDefinition =
  StructDefinition(name: name, location: location)

type Struct* = ref object of RootObj
  struct_def*: StructDefinition
  fields*: seq[ArgumentDefinition]

proc location*(struct: Struct): Location =
  struct.struct_def.location

proc name*(struct: Struct): Token =
  struct.struct_def.name

proc `$`*(struct: Struct): string =
  let prefix = " ".repeat(struct.struct_def.location.column - 1)
  let child_prefix = " ".repeat(struct.struct_def.location.column + 1)
  var lines = @[prefix & $(struct.struct_def)]
  for field in struct.fields:
    lines.add(child_prefix & fmt"{field.arg_type} {field.arg_name}")
  return lines.join("\n")

proc c*(struct: Struct): string =
  raise new_exception(IOError, "TODO: To be implemented")

proc add_field*(struct: Struct, field: ArgumentDefinition): void =
  struct.fields.add(field)

proc new_struct*(struct_def: StructDefinition): Struct =
  Struct(struct_def: struct_def)

proc find_field*(struct: Struct, field_name: Token): Result[ArgumentDefinition, string] =
  for field in struct.fields:
    if $(field.arg_name) == $(field_name):
      return ok(field)
  return err(fmt"{field_name.location} {struct.name} does not have any field named {field_name}")

proc expand_set(struct: Struct, field: ArgumentDefinition,
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

proc expand_get(struct: Struct, field: ArgumentDefinition,
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

proc expand*(struct: Struct, field: ArgumentDefinition, offset: uint): (
    Function, Function) =
  (struct.expand_get(field, offset), struct.expand_set(field, offset))

proc expand_init*(struct: Struct, struct_byte_size: uint): Function =
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

  return init_function

proc expand_free*(struct: Struct): Function =
  # struct free function
  let free_function_def = new_function_definition(fmt"{struct.name}_free", @[(
      $(struct.name), "ptr")], "U64")
  let free_function = new_function(free_function_def)

  # struct free statement
  let ptr_free_call = new_function_call(fmt"System_free", @["ptr"])
  let ptr_free_statement = new_statement("result", ptr_free_call)
  free_function.add_arg_to_scope(new_argument_definition("U64", "result"))
  free_function.add_statement(ptr_free_statement)
  return free_function
