# Standard library imports
import results, strformat

# Parser submodules (ordered by dependency)
import parser/tokenizer
export tokenizer

import parser/core
export core

import parser/identifier
export identifier

import parser/module_ref
export module_ref

import parser/defs
export defs

import parser/literal
export literal

import parser/struct
export struct

import parser/arg
export arg

import parser/initializer
export initializer

import parser/pattern
export pattern

import parser/expression
export expression

import parser/generic
export generic

import parser/function
export function

import parser/module
export module

import parser/file
export file

proc new_error_module(): Result[Module, ParserError] =
  let code_arg = ? new_argument_definition("S32", "code")
  let message_arg = ? new_argument_definition("String", "message")
  let struct = ? new_struct(new_struct_definition(Location()), @[code_arg, message_arg])

  var generics: seq[Generic]
  var functions: seq[ExternFunction]
  new_module("Error", generics, @[struct], functions)

proc new_status_module(): Result[Module, ParserError] =
  let generic = new_generic(new_identifier("Value"), Location())

  let value_arg = ? new_argument_definition("Value", "value")
  let ok_branch = new_struct_definition(new_identifier("Ok"), Location())
  let ok_struct = ? new_struct(ok_branch, @[value_arg])

  let err_arg = ? new_argument_definition("Error", "error")
  let err_branch = new_struct_definition(new_identifier("Err"), Location())
  let err_struct = ? new_struct(err_branch, @[err_arg])

  var functions: seq[ExternFunction]
  new_module("Status", @[generic], @[ok_struct, err_struct], functions)

proc new_string_module(): Result[Module, ParserError] =
  let byte_size_fn = ? new_extern_function("String_byte_size", "U64",
      "byte_size", @["U64"])
  let read_fn = ? new_extern_function("String_read", "String", "read", @[
      "Pointer", "U64"])
  let write_fn = ? new_extern_function("String_write", "Pointer", "write", @[
      "String", "Pointer", "U64"])

  # fn get(String value, U64 index): Status[U8]
  let get_fn_name = new_identifier("get")
  let get_fn_args = @[
    ? new_argument_definition("String", "value"),
    ? new_argument_definition("U64", "index"),
  ]

  let u8_module_ref = new_module_ref("U8")
  let status_module_name = new_identifier("Status")
  let get_fn_returns = ? new_module_ref(status_module_name, @[u8_module_ref])

  let get_fn_def = ? new_function_definition(get_fn_name, get_fn_args,
      get_fn_returns, Location())
  let get_fn = new_extern_function(get_fn_def, "String_get")

  new_module("String", @[byte_size_fn, read_fn, write_fn, get_fn])

proc new_array_module(): Result[Module, ParserError] =
  let generic = new_generic(new_identifier("Item"), Location())

  let size_arg = ? new_argument_definition("U64", "size")
  let struct = ? new_struct(new_struct_definition(Location()), @[size_arg])

  let size_module_ref = new_module_ref(new_identifier("U64"))
  let size_arg_name = new_identifier("__asl__arg__size__")
  let size_arg_def = new_argument_definition(size_module_ref, size_arg_name)

  let index_module_ref = new_module_ref(new_identifier("U64"))
  let index_arg_name = new_identifier("__asl__arg__index__")
  let index_arg_def = new_argument_definition(index_module_ref, index_arg_name)

  let item_generic_name = new_identifier("Item")
  let item_module_ref = new_module_ref(item_generic_name) # Item
  let item_arg_name = new_identifier(fmt"__asl__arg__item__")
  let item_arg_def = new_argument_definition(item_module_ref, item_arg_name)

  let array_module_name = new_identifier("Array")
  let array_item_module_ref = ? new_module_ref(array_module_name, @[
      item_module_ref]) # Array[Item]
  let array_item_arg_name = new_identifier(fmt"__asl__arg__array__")
  let array_item_arg_def = new_argument_definition(array_item_module_ref, array_item_arg_name)

  let status_module_name = new_identifier("Status")
  let status_item_module_ref = ? new_module_ref(status_module_name, @[
      item_module_ref]) # Status[Item]
  let status_array_module_ref = ? new_module_ref(status_module_name, @[
      array_item_module_ref]) # Status[Array[Item]]

  let array_init_fn_name = new_identifier("init")
  let array_init_fn_def = ? new_function_definition(array_init_fn_name, @[
      size_arg_def], array_item_module_ref, Location())
  let array_init_fn = new_extern_function(array_init_fn_def,
      "Array_init")

  let array_get_fn_name = new_identifier("get")
  let array_get_fn_def = ? new_function_definition(array_get_fn_name, @[
      array_item_arg_def, index_arg_def], status_item_module_ref, Location())
  let array_get_fn = new_extern_function(array_get_fn_def,
      "Array_get")

  let array_set_fn_name = new_identifier("set")
  let array_set_fn_def = ? new_function_definition(array_set_fn_name, @[
      array_item_arg_def, index_arg_def, item_arg_def], status_array_module_ref,
      Location())
  let array_set_fn = new_extern_function(array_set_fn_def,
      "Array_set")

  new_module("Array", @[generic], @[struct], @[
    array_init_fn, array_get_fn, array_set_fn
  ])

proc builtin_modules(): Result[seq[Module], ParserError] =
  ok(@[
    ? new_module("S8", @[
      ? new_extern_function("S8_byte_size", "U64", "byte_size", @["U64"]),
      ? new_extern_function("S8_read", "S8", "read", @["Pointer",
          "U64"]),
      ? new_extern_function("S8_write", "Pointer", "write", @["S8",
          "Pointer", "U64"]),
    ]),
    ? new_module("S16", @[
      ? new_extern_function("S16_byte_size", "U64", "byte_size", @["U64"]),
      ? new_extern_function("S16_read", "S16", "read", @["Pointer",
          "U64"]),
      ? new_extern_function("S16_write", "Pointer", "write", @["S16",
          "Pointer", "U64"]),
    ]),
    ? new_module("S32", @[
      ? new_extern_function("S32_byte_size", "U64", "byte_size", @["U64"]),
      ? new_extern_function("S32_read", "S32", "read", @["Pointer",
          "U64"]),
      ? new_extern_function("S32_write", "Pointer", "write", @["S32",
          "Pointer", "U64"]),
    ]),
    ? new_module("S64", @[
      ? new_extern_function("S64_byte_size", "U64", "byte_size", @["U64"]),
      ? new_extern_function("S64_read", "S64", "read", @["Pointer",
          "U64"]),
      ? new_extern_function("S64_write", "Pointer", "write", @["S64",
          "Pointer", "U64"]),
      ? new_extern_function("S64_add_S64", "S64", "add", @["S64", "S64"]),
      ? new_extern_function("S64_subtract_S64", "S64", "subtract", @["S64",
          "S64"]),
      ? new_extern_function("S64_multiply_S64", "S64", "multiply", @["S64",
          "S64"]),
      ? new_extern_function("S64_remainder_S64", "S64", "remainder", @["S64",
          "S64"]),
      ? new_extern_function("S64_quotient_S64", "S64", "quotient", @["S64",
          "S64"]),
      ? new_extern_function("S64_compare_S64", "S8", "compare", @["S64",
          "S64"]),
      ? new_extern_function("S64_from_U8", "S64", "from", @["U8"]),
      ? new_extern_function("S64_from_U64", "S64", "from", @["U64"]),
    ]),
    ? new_module("U8", @[
      ? new_extern_function("U8_byte_size", "U64", "byte_size", @["U64"]),
      ? new_extern_function("U8_read", "U8", "read", @["Pointer",
          "U64"]),
      ? new_extern_function("U8_write", "Pointer", "write", @["U8",
          "Pointer", "U64"]),
      ? new_extern_function("U8_lshift_U8", "U8", "lshift", @["U8",
          "U64"]),
      ? new_extern_function("U8_rshift_U8", "U8", "rshift", @["U8",
          "U64"]),
      ? new_extern_function("U8_and_U8", "U8", "and", @["U8",
          "U8"]),
      ? new_extern_function("U8_or_U8", "U8", "or", @["U8",
          "U8"]),
      ? new_extern_function("U8_not", "U8", "not", @["U8"]),
      ? new_extern_function("U8_from_U64", "U8", "from", @["U64"]),
      ? new_extern_function("U8_subtract_U8", "U8", "subtract", @["U8",
          "U8"]),
    ]),
    ? new_module("U16", @[
      ? new_extern_function("U16_byte_size", "U64", "byte_size", @["U64"]),
      ? new_extern_function("U16_read", "U16", "read", @["Pointer",
          "U64"]),
      ? new_extern_function("U16_write", "Pointer", "write", @["U16",
          "Pointer", "U64"]),
    ]),
    ? new_module("U32", @[
      ? new_extern_function("U32_byte_size", "U64", "byte_size", @["U64"]),
      ? new_extern_function("U32_read", "U32", "read", @["Pointer",
          "U64"]),
      ? new_extern_function("U32_write", "Pointer", "write", @["U32",
          "Pointer", "U64"]),
    ]),
    ? new_module("U64", @[
      ? new_extern_function("U64_byte_size", "U64", "byte_size", @["U64"]),
      ? new_extern_function("U64_read", "U64", "read", @["Pointer",
          "U64"]),
      ? new_extern_function("U64_write", "Pointer", "write", @["U64",
          "Pointer", "U64"]),
      ? new_extern_function("U64_add_U64", "U64", "add", @["U64", "U64"]),
      ? new_extern_function("U64_subtract_U64", "U64", "subtract", @["U64",
          "U64"]),
      ? new_extern_function("U64_multiply_U64", "U64", "multiply", @["U64",
          "U64"]),
      ? new_extern_function("U64_remainder_U64", "U64", "remainder", @["U64",
          "U64"]),
      ? new_extern_function("U64_quotient_U64", "U64", "quotient", @["U64",
          "U64"]),
      ? new_extern_function("U64_compare_U64", "S8", "compare", @["U64",
          "U64"]),
      ? new_extern_function("U64_lshift_U64", "U64", "lshift", @["U64",
          "U64"]),
      ? new_extern_function("U64_rshift_U64", "U64", "rshift", @["U64",
          "U64"]),
      ? new_extern_function("U64_and_U64", "U64", "and", @["U64",
          "U64"]),
      ? new_extern_function("U64_or_U64", "U64", "or", @["U64",
          "U64"]),
      ? new_extern_function("U64_not", "U64", "not", @["U64"]),
    ]),
    ? new_module("F32", @[
      ? new_extern_function("F32_byte_size", "U64", "byte_size", @["U64"]),
      ? new_extern_function("F32_read", "F32", "read", @["Pointer",
          "U64"]),
      ? new_extern_function("F32_write", "Pointer", "write", @["F32",
          "Pointer", "U64"]),
    ]),
    ? new_module("F64", @[
      ? new_extern_function("F64_byte_size", "U64", "byte_size", @["U64"]),
      ? new_extern_function("F64_read", "F64", "read", @["Pointer",
          "U64"]),
      ? new_extern_function("F64_write", "Pointer", "write", @["F64",
          "Pointer", "U64"]),
    ]),
    ? new_string_module(),
    ? new_module("Pointer", @[
      ? new_extern_function("Pointer_byte_size", "U64", "byte_size", @[
          "U64"]),
      ? new_extern_function("Pointer_read", "Pointer", "read", @[
          "Pointer", "U64"]),
      ? new_extern_function("Pointer_write", "Pointer", "write", @[
          "Pointer", "Pointer", "U64"]),
    ]),
    ? new_error_module(),
    ? new_status_module(),
    ? new_array_module(),
    ? new_module("System", @[
      ? new_extern_function("System_allocate", "Pointer", "allocate", @["U64"]),
      ? new_extern_function("System_free", "U64", "free", @["Pointer"]),
      ? new_extern_function("System_box_U8", "Pointer", "box", @["U8"]),
      ? new_extern_function("System_box_U64", "Pointer", "box", @["U64"]),
      ? new_extern_function("System_box_S32", "Pointer", "box", @["S32"]),
      ? new_extern_function("System_box_S64", "Pointer", "box", @["S64"]),
      ? new_extern_function("System_box_Pointer", "Pointer", "box", @[
          "Pointer"]),
      ? new_extern_function("System_print_U8", "U64", "print", @["U8"]),
      ? new_extern_function("System_print_U16", "U64", "print", @["U16"]),
      ? new_extern_function("System_print_U32", "U64", "print", @["U32"]),
      ? new_extern_function("System_print_U64", "U64", "print", @["U64"]),
      ? new_extern_function("System_print_S8", "U64", "print", @["S8"]),
      ? new_extern_function("System_print_S16", "U64", "print", @["S16"]),
      ? new_extern_function("System_print_S32", "U64", "print", @["S32"]),
      ? new_extern_function("System_print_S64", "U64", "print", @["S64"]),
      ? new_extern_function("System_print_F32", "U64", "print", @["F32"]),
      ? new_extern_function("System_print_F64", "U64", "print", @["F64"]),
      ? new_extern_function("System_print_String", "U64", "print", @["String"]),
    ])
  ])

proc parse(parser: Parser): Result[file.File, ParserError] =
  let builtin_modules = ? builtin_modules()
  file_spec(parser, builtin_modules)

proc parse*(path: string, tokens: seq[Token]): Result[file.File, string] =
  let maybe_parsed = new_parser(path, tokens, INDENT_SIZE).parse()
  if maybe_parsed.is_ok: ok(maybe_parsed.get)
  else: err($(maybe_parsed.error))
