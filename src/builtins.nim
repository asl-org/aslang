import common

const print_fn =
  Function(
    name: "unsafe_print",
    defs: @[
    FunctionDefinition(
      native_function: "S8_unsafe_print",
      result: Datatype(name: "S32"),
      args: @[Variable(name: "value", datatype: Datatype(name: "S8"))]
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

const add_fn =
  Function(
    name: "unsafe_add",
    defs: @[
    # Module: S8
    FunctionDefinition(
      native_function: "S8_unsafe_add_S8",
      result: Datatype(name: "S8"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "S8")),
        Variable(name: "num2", datatype: Datatype(name: "S8")),
      ]
    ),
    FunctionDefinition(
      native_function: "S8_unsafe_add_S16",
      result: Datatype(name: "S16"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "S8")),
        Variable(name: "num2", datatype: Datatype(name: "S16")),
      ]
    ),
    FunctionDefinition(
      native_function: "S8_unsafe_add_S32",
      result: Datatype(name: "S32"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "S8")),
        Variable(name: "num2", datatype: Datatype(name: "S32")),
      ]
    ),
    FunctionDefinition(
      native_function: "S8_unsafe_add_S64",
      result: Datatype(name: "S64"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "S8")),
        Variable(name: "num2", datatype: Datatype(name: "S64")),
      ]
    ),
    FunctionDefinition(
      native_function: "S8_unsafe_add_U8",
      result: Datatype(name: "S8"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "S8")),
        Variable(name: "num2", datatype: Datatype(name: "U8")),
      ]
    ),
    FunctionDefinition(
      native_function: "S8_unsafe_add_U16",
      result: Datatype(name: "S16"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "S8")),
        Variable(name: "num2", datatype: Datatype(name: "U16")),
      ]
    ),
    FunctionDefinition(
      native_function: "S8_unsafe_add_U32",
      result: Datatype(name: "S32"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "S8")),
        Variable(name: "num2", datatype: Datatype(name: "U32")),
      ]
    ),
    FunctionDefinition(
      native_function: "S8_unsafe_add_U64",
      result: Datatype(name: "S64"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "S8")),
        Variable(name: "num2", datatype: Datatype(name: "U64")),
      ]
    ),
    FunctionDefinition(
      native_function: "S8_unsafe_add_F32",
      result: Datatype(name: "F32"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "S8")),
        Variable(name: "num2", datatype: Datatype(name: "F32")),
      ]
    ),
    FunctionDefinition(
      native_function: "S8_unsafe_add_F64",
      result: Datatype(name: "F64"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "S8")),
        Variable(name: "num2", datatype: Datatype(name: "F64")),
      ]
    ),
    # Module: S16
    FunctionDefinition(
      native_function: "S16_unsafe_add_S8",
      result: Datatype(name: "S16"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "S16")),
        Variable(name: "num2", datatype: Datatype(name: "S8")),
      ]
    ),
    FunctionDefinition(
      native_function: "S16_unsafe_add_S16",
      result: Datatype(name: "S16"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "S16")),
        Variable(name: "num2", datatype: Datatype(name: "S16")),
      ]
    ),
    FunctionDefinition(
      native_function: "S16_unsafe_add_S32",
      result: Datatype(name: "S32"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "S16")),
        Variable(name: "num2", datatype: Datatype(name: "S32")),
      ]
    ),
    FunctionDefinition(
      native_function: "S16_unsafe_add_S64",
      result: Datatype(name: "S64"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "S16")),
        Variable(name: "num2", datatype: Datatype(name: "S64")),
      ]
    ),
    FunctionDefinition(
      native_function: "S16_unsafe_add_U8",
      result: Datatype(name: "S16"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "S16")),
        Variable(name: "num2", datatype: Datatype(name: "U8")),
      ]
    ),
    FunctionDefinition(
      native_function: "S16_unsafe_add_U16",
      result: Datatype(name: "S16"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "S16")),
        Variable(name: "num2", datatype: Datatype(name: "U16")),
      ]
    ),
    FunctionDefinition(
      native_function: "S16_unsafe_add_U32",
      result: Datatype(name: "S32"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "S16")),
        Variable(name: "num2", datatype: Datatype(name: "U32")),
      ]
    ),
    FunctionDefinition(
      native_function: "S16_unsafe_add_U64",
      result: Datatype(name: "S64"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "S16")),
        Variable(name: "num2", datatype: Datatype(name: "U64")),
      ]
    ),
    FunctionDefinition(
      native_function: "S16_unsafe_add_F32",
      result: Datatype(name: "F32"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "S16")),
        Variable(name: "num2", datatype: Datatype(name: "F32")),
      ]
    ),
    FunctionDefinition(
      native_function: "S16_unsafe_add_F64",
      result: Datatype(name: "F64"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "S16")),
        Variable(name: "num2", datatype: Datatype(name: "F64")),
      ]
    ),
    # Module: S32
    FunctionDefinition(
      native_function: "S32_unsafe_add_S8",
      result: Datatype(name: "S32"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "S32")),
        Variable(name: "num2", datatype: Datatype(name: "S8")),
      ]
    ),
    FunctionDefinition(
      native_function: "S32_unsafe_add_S16",
      result: Datatype(name: "S32"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "S32")),
        Variable(name: "num2", datatype: Datatype(name: "S16")),
      ]
    ),
    FunctionDefinition(
      native_function: "S32_unsafe_add_S32",
      result: Datatype(name: "S32"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "S32")),
        Variable(name: "num2", datatype: Datatype(name: "S32")),
      ]
    ),
    FunctionDefinition(
      native_function: "S32_unsafe_add_S64",
      result: Datatype(name: "S64"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "S32")),
        Variable(name: "num2", datatype: Datatype(name: "S64")),
      ]
    ),
    FunctionDefinition(
      native_function: "S32_unsafe_add_U8",
      result: Datatype(name: "S32"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "S32")),
        Variable(name: "num2", datatype: Datatype(name: "U8")),
      ]
    ),
    FunctionDefinition(
      native_function: "S32_unsafe_add_U16",
      result: Datatype(name: "S32"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "S32")),
        Variable(name: "num2", datatype: Datatype(name: "U16")),
      ]
    ),
    FunctionDefinition(
      native_function: "S32_unsafe_add_U32",
      result: Datatype(name: "S32"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "S32")),
        Variable(name: "num2", datatype: Datatype(name: "U32")),
      ]
    ),
    FunctionDefinition(
      native_function: "S32_unsafe_add_U64",
      result: Datatype(name: "S64"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "S32")),
        Variable(name: "num2", datatype: Datatype(name: "U64")),
      ]
    ),
    FunctionDefinition(
      native_function: "S32_unsafe_add_F32",
      result: Datatype(name: "F32"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "S32")),
        Variable(name: "num2", datatype: Datatype(name: "F32")),
      ]
    ),
    FunctionDefinition(
      native_function: "S32_unsafe_add_F64",
      result: Datatype(name: "F64"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "S32")),
        Variable(name: "num2", datatype: Datatype(name: "F64")),
      ]
    ),
    # Module: S64
    FunctionDefinition(
      native_function: "S64_unsafe_add_S8",
      result: Datatype(name: "S64"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "S64")),
        Variable(name: "num2", datatype: Datatype(name: "S8")),
      ]
    ),
    FunctionDefinition(
      native_function: "S64_unsafe_add_S16",
      result: Datatype(name: "S64"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "S64")),
        Variable(name: "num2", datatype: Datatype(name: "S16")),
      ]
    ),
    FunctionDefinition(
      native_function: "S64_unsafe_add_S32",
      result: Datatype(name: "S64"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "S64")),
        Variable(name: "num2", datatype: Datatype(name: "S32")),
      ]
    ),
    FunctionDefinition(
      native_function: "S64_unsafe_add_S64",
      result: Datatype(name: "S64"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "S64")),
        Variable(name: "num2", datatype: Datatype(name: "S64")),
      ]
    ),
    FunctionDefinition(
      native_function: "S64_unsafe_add_U8",
      result: Datatype(name: "S64"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "S64")),
        Variable(name: "num2", datatype: Datatype(name: "U8")),
      ]
    ),
    FunctionDefinition(
      native_function: "S64_unsafe_add_U16",
      result: Datatype(name: "S64"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "S64")),
        Variable(name: "num2", datatype: Datatype(name: "U16")),
      ]
    ),
    FunctionDefinition(
      native_function: "S64_unsafe_add_U32",
      result: Datatype(name: "S64"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "S64")),
        Variable(name: "num2", datatype: Datatype(name: "U32")),
      ]
    ),
    FunctionDefinition(
      native_function: "S64_unsafe_add_U64",
      result: Datatype(name: "S64"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "S64")),
        Variable(name: "num2", datatype: Datatype(name: "U64")),
      ]
    ),
    FunctionDefinition(
      native_function: "S64_unsafe_add_F32",
      result: Datatype(name: "F64"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "S64")),
        Variable(name: "num2", datatype: Datatype(name: "F32")),
      ]
    ),
    FunctionDefinition(
      native_function: "S64_unsafe_add_F64",
      result: Datatype(name: "F64"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "S64")),
        Variable(name: "num2", datatype: Datatype(name: "F64")),
      ]
    ),
    # Module: U8
    FunctionDefinition(
      native_function: "U8_unsafe_add_S8",
      result: Datatype(name: "S8"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "U8")),
        Variable(name: "num2", datatype: Datatype(name: "S8")),
      ]
    ),
    FunctionDefinition(
      native_function: "U8_unsafe_add_S16",
      result: Datatype(name: "S16"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "U8")),
        Variable(name: "num2", datatype: Datatype(name: "S16")),
      ]
    ),
    FunctionDefinition(
      native_function: "U8_unsafe_add_S32",
      result: Datatype(name: "S32"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "U8")),
        Variable(name: "num2", datatype: Datatype(name: "S32")),
      ]
    ),
    FunctionDefinition(
      native_function: "U8_unsafe_add_S64",
      result: Datatype(name: "S64"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "U8")),
        Variable(name: "num2", datatype: Datatype(name: "S64")),
      ]
    ),
    FunctionDefinition(
      native_function: "U8_unsafe_add_U8",
      result: Datatype(name: "U8"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "U8")),
        Variable(name: "num2", datatype: Datatype(name: "U8")),
      ]
    ),
    FunctionDefinition(
      native_function: "U8_unsafe_add_U16",
      result: Datatype(name: "U16"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "U8")),
        Variable(name: "num2", datatype: Datatype(name: "U16")),
      ]
    ),
    FunctionDefinition(
      native_function: "U8_unsafe_add_U32",
      result: Datatype(name: "U32"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "U8")),
        Variable(name: "num2", datatype: Datatype(name: "U32")),
      ]
    ),
    FunctionDefinition(
      native_function: "U8_unsafe_add_U64",
      result: Datatype(name: "U64"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "U8")),
        Variable(name: "num2", datatype: Datatype(name: "U64")),
      ]
    ),
    FunctionDefinition(
      native_function: "U8_unsafe_add_F32",
      result: Datatype(name: "F32"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "U8")),
        Variable(name: "num2", datatype: Datatype(name: "F32")),
      ]
    ),
    FunctionDefinition(
      native_function: "U8_unsafe_add_F64",
      result: Datatype(name: "F64"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "U8")),
        Variable(name: "num2", datatype: Datatype(name: "F64")),
      ]
    ),
    # Module: U16
    FunctionDefinition(
      native_function: "U16_unsafe_add_S8",
      result: Datatype(name: "S16"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "U16")),
        Variable(name: "num2", datatype: Datatype(name: "S8")),
      ]
    ),
    FunctionDefinition(
      native_function: "U16_unsafe_add_S16",
      result: Datatype(name: "S16"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "U16")),
        Variable(name: "num2", datatype: Datatype(name: "S16")),
      ]
    ),
    FunctionDefinition(
      native_function: "U16_unsafe_add_S32",
      result: Datatype(name: "S32"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "U16")),
        Variable(name: "num2", datatype: Datatype(name: "S32")),
      ]
    ),
    FunctionDefinition(
      native_function: "U16_unsafe_add_S64",
      result: Datatype(name: "S64"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "U16")),
        Variable(name: "num2", datatype: Datatype(name: "S64")),
      ]
    ),
    FunctionDefinition(
      native_function: "U16_unsafe_add_U8",
      result: Datatype(name: "U16"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "U16")),
        Variable(name: "num2", datatype: Datatype(name: "U8")),
      ]
    ),
    FunctionDefinition(
      native_function: "U16_unsafe_add_U16",
      result: Datatype(name: "U16"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "U16")),
        Variable(name: "num2", datatype: Datatype(name: "U16")),
      ]
    ),
    FunctionDefinition(
      native_function: "U16_unsafe_add_U32",
      result: Datatype(name: "U32"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "U16")),
        Variable(name: "num2", datatype: Datatype(name: "U32")),
      ]
    ),
    FunctionDefinition(
      native_function: "U16_unsafe_add_U64",
      result: Datatype(name: "U64"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "U16")),
        Variable(name: "num2", datatype: Datatype(name: "U64")),
      ]
    ),
    FunctionDefinition(
      native_function: "U16_unsafe_add_F32",
      result: Datatype(name: "F32"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "U16")),
        Variable(name: "num2", datatype: Datatype(name: "F32")),
      ]
    ),
    FunctionDefinition(
      native_function: "U16_unsafe_add_F64",
      result: Datatype(name: "F64"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "U16")),
        Variable(name: "num2", datatype: Datatype(name: "F64")),
      ]
    ),
    # Module: U32
    FunctionDefinition(
      native_function: "U32_unsafe_add_S8",
      result: Datatype(name: "S32"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "U32")),
        Variable(name: "num2", datatype: Datatype(name: "S8")),
      ]
    ),
    FunctionDefinition(
      native_function: "U32_unsafe_add_S16",
      result: Datatype(name: "S32"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "U32")),
        Variable(name: "num2", datatype: Datatype(name: "S16")),
      ]
    ),
    FunctionDefinition(
      native_function: "U32_unsafe_add_S32",
      result: Datatype(name: "S32"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "U32")),
        Variable(name: "num2", datatype: Datatype(name: "S32")),
      ]
    ),
    FunctionDefinition(
      native_function: "U32_unsafe_add_S64",
      result: Datatype(name: "S64"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "U32")),
        Variable(name: "num2", datatype: Datatype(name: "S64")),
      ]
    ),
    FunctionDefinition(
      native_function: "U32_unsafe_add_U8",
      result: Datatype(name: "U32"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "U32")),
        Variable(name: "num2", datatype: Datatype(name: "U8")),
      ]
    ),
    FunctionDefinition(
      native_function: "U32_unsafe_add_U16",
      result: Datatype(name: "U32"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "U32")),
        Variable(name: "num2", datatype: Datatype(name: "U16")),
      ]
    ),
    FunctionDefinition(
      native_function: "U32_unsafe_add_U32",
      result: Datatype(name: "U32"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "U32")),
        Variable(name: "num2", datatype: Datatype(name: "U32")),
      ]
    ),
    FunctionDefinition(
      native_function: "U32_unsafe_add_U64",
      result: Datatype(name: "U64"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "U32")),
        Variable(name: "num2", datatype: Datatype(name: "U64")),
      ]
    ),
    FunctionDefinition(
      native_function: "U32_unsafe_add_F32",
      result: Datatype(name: "F32"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "U32")),
        Variable(name: "num2", datatype: Datatype(name: "F32")),
      ]
    ),
    FunctionDefinition(
      native_function: "U32_unsafe_add_F64",
      result: Datatype(name: "F64"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "U32")),
        Variable(name: "num2", datatype: Datatype(name: "F64")),
      ]
    ),
    # Module: U64
    FunctionDefinition(
      native_function: "U64_unsafe_add_S8",
      result: Datatype(name: "S64"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "U64")),
        Variable(name: "num2", datatype: Datatype(name: "S8")),
      ]
    ),
    FunctionDefinition(
      native_function: "U64_unsafe_add_S16",
      result: Datatype(name: "S64"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "U64")),
        Variable(name: "num2", datatype: Datatype(name: "S16")),
      ]
    ),
    FunctionDefinition(
      native_function: "U64_unsafe_add_S32",
      result: Datatype(name: "S64"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "U64")),
        Variable(name: "num2", datatype: Datatype(name: "S32")),
      ]
    ),
    FunctionDefinition(
      native_function: "U64_unsafe_add_S64",
      result: Datatype(name: "S64"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "U64")),
        Variable(name: "num2", datatype: Datatype(name: "S64")),
      ]
    ),
    FunctionDefinition(
      native_function: "U64_unsafe_add_U8",
      result: Datatype(name: "U64"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "U64")),
        Variable(name: "num2", datatype: Datatype(name: "U8")),
      ]
    ),
    FunctionDefinition(
      native_function: "U64_unsafe_add_U16",
      result: Datatype(name: "U64"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "U64")),
        Variable(name: "num2", datatype: Datatype(name: "U16")),
      ]
    ),
    FunctionDefinition(
      native_function: "U64_unsafe_add_U32",
      result: Datatype(name: "U64"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "U64")),
        Variable(name: "num2", datatype: Datatype(name: "U32")),
      ]
    ),
    FunctionDefinition(
      native_function: "U64_unsafe_add_U64",
      result: Datatype(name: "U64"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "U64")),
        Variable(name: "num2", datatype: Datatype(name: "U64")),
      ]
    ),
    FunctionDefinition(
      native_function: "U64_unsafe_add_F32",
      result: Datatype(name: "F64"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "U64")),
        Variable(name: "num2", datatype: Datatype(name: "F32")),
      ]
    ),
    FunctionDefinition(
      native_function: "U64_unsafe_add_F64",
      result: Datatype(name: "F64"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "U64")),
        Variable(name: "num2", datatype: Datatype(name: "F64")),
      ]
    ),
    # Module: F32
    FunctionDefinition(
      native_function: "F32_unsafe_add_S8",
      result: Datatype(name: "F32"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "F32")),
        Variable(name: "num2", datatype: Datatype(name: "S8")),
      ]
    ),
    FunctionDefinition(
      native_function: "F32_unsafe_add_S16",
      result: Datatype(name: "F32"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "F32")),
        Variable(name: "num2", datatype: Datatype(name: "S16")),
      ]
    ),
    FunctionDefinition(
      native_function: "F32_unsafe_add_S32",
      result: Datatype(name: "F32"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "F32")),
        Variable(name: "num2", datatype: Datatype(name: "S32")),
      ]
    ),
    FunctionDefinition(
      native_function: "F32_unsafe_add_S64",
      result: Datatype(name: "F64"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "F32")),
        Variable(name: "num2", datatype: Datatype(name: "S64")),
      ]
    ),
    FunctionDefinition(
      native_function: "F32_unsafe_add_U8",
      result: Datatype(name: "F32"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "F32")),
        Variable(name: "num2", datatype: Datatype(name: "U8")),
      ]
    ),
    FunctionDefinition(
      native_function: "F32_unsafe_add_U16",
      result: Datatype(name: "F32"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "F32")),
        Variable(name: "num2", datatype: Datatype(name: "U16")),
      ]
    ),
    FunctionDefinition(
      native_function: "F32_unsafe_add_U32",
      result: Datatype(name: "F32"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "F32")),
        Variable(name: "num2", datatype: Datatype(name: "U32")),
      ]
    ),
    FunctionDefinition(
      native_function: "F32_unsafe_add_U64",
      result: Datatype(name: "F64"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "F32")),
        Variable(name: "num2", datatype: Datatype(name: "U64")),
      ]
    ),
    FunctionDefinition(
      native_function: "F32_unsafe_add_F32",
      result: Datatype(name: "F32"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "F32")),
        Variable(name: "num2", datatype: Datatype(name: "F32")),
      ]
    ),
    FunctionDefinition(
      native_function: "F32_unsafe_add_F64",
      result: Datatype(name: "F64"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "F32")),
        Variable(name: "num2", datatype: Datatype(name: "F64")),
      ]
    ),
    # Module: F64
    FunctionDefinition(
      native_function: "F64_unsafe_add_S8",
      result: Datatype(name: "F64"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "F64")),
        Variable(name: "num2", datatype: Datatype(name: "S8")),
      ]
    ),
    FunctionDefinition(
      native_function: "F64_unsafe_add_S16",
      result: Datatype(name: "F64"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "F64")),
        Variable(name: "num2", datatype: Datatype(name: "S16")),
      ]
    ),
    FunctionDefinition(
      native_function: "F64_unsafe_add_S32",
      result: Datatype(name: "F64"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "F64")),
        Variable(name: "num2", datatype: Datatype(name: "S32")),
      ]
    ),
    FunctionDefinition(
      native_function: "F64_unsafe_add_S64",
      result: Datatype(name: "F64"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "F64")),
        Variable(name: "num2", datatype: Datatype(name: "S64")),
      ]
    ),
    FunctionDefinition(
      native_function: "F64_unsafe_add_U8",
      result: Datatype(name: "F64"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "F64")),
        Variable(name: "num2", datatype: Datatype(name: "U8")),
      ]
    ),
    FunctionDefinition(
      native_function: "F64_unsafe_add_U16",
      result: Datatype(name: "F64"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "F64")),
        Variable(name: "num2", datatype: Datatype(name: "U16")),
      ]
    ),
    FunctionDefinition(
      native_function: "F64_unsafe_add_U32",
      result: Datatype(name: "F64"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "F64")),
        Variable(name: "num2", datatype: Datatype(name: "U32")),
      ]
    ),
    FunctionDefinition(
      native_function: "F64_unsafe_add_U64",
      result: Datatype(name: "F64"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "F64")),
        Variable(name: "num2", datatype: Datatype(name: "U64")),
      ]
    ),
    FunctionDefinition(
      native_function: "F64_unsafe_add_F32",
      result: Datatype(name: "F64"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "F64")),
        Variable(name: "num2", datatype: Datatype(name: "F32")),
      ]
    ),
    FunctionDefinition(
      native_function: "F64_unsafe_add_F64",
      result: Datatype(name: "F64"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "F64")),
        Variable(name: "num2", datatype: Datatype(name: "F64")),
      ]
    ),
])

proc builtin_functions*(): seq[Function] = @[print_fn, add_fn]
