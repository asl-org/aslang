import common

const print_fn =
  Function(
    name: "unsafe_print",
    defs: @[
    FunctionDefinition(
      native_function: "S8_unsafe_print",
      result: Datatype(name: "S32"),
      args: @[Variable(name: "value", datatype: Datatype(name: "S8"))],
    ),
    FunctionDefinition(
      native_function: "S16_unsafe_print",
      result: Datatype(name: "S32"),
      args: @[Variable(name: "value", datatype: Datatype(name: "S16"))]
    ),
    FunctionDefinition(
      native_function: "S32_unsafe_print",
      result: Datatype(name: "S32"),
      args: @[Variable(name: "value", datatype: Datatype(name: "S32"))]
    ),
    FunctionDefinition(
      native_function: "S64_unsafe_print",
      result: Datatype(name: "S32"),
      args: @[Variable(name: "value", datatype: Datatype(name: "S64"))]
    ),
    FunctionDefinition(
      native_function: "U8_unsafe_print",
      result: Datatype(name: "S32"),
      args: @[Variable(name: "value", datatype: Datatype(name: "U8"))]
    ),
    FunctionDefinition(
      native_function: "U16_unsafe_print",
      result: Datatype(name: "S32"),
      args: @[Variable(name: "value", datatype: Datatype(name: "U16"))]
    ),
    FunctionDefinition(
      native_function: "U32_unsafe_print",
      result: Datatype(name: "S32"),
      args: @[Variable(name: "value", datatype: Datatype(name: "U32"))]
    ),
    FunctionDefinition(
      native_function: "U64_unsafe_print",
      result: Datatype(name: "S32"),
      args: @[Variable(name: "value", datatype: Datatype(name: "U64"))]
    ),
    FunctionDefinition(
      native_function: "F32_unsafe_print",
      result: Datatype(name: "S32"),
      args: @[Variable(name: "value", datatype: Datatype(name: "F32"))]
    ),
    FunctionDefinition(
      native_function: "F64_unsafe_print",
      result: Datatype(name: "S32"),
      args: @[Variable(name: "value", datatype: Datatype(name: "F64"))]
    ),
])

proc builtin_functions*(): seq[Function] = @[
  print_fn
]
