import "../common"

let bitwise_xor_fn =
  Function(
    name: "xor",
    defs: @[
    # Module: S8
    FunctionDefinition(
      native_function: "S8_xor_S8",
      result: Datatype(name: "S8"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "S8")),
        Variable(name: "num2", datatype: Datatype(name: "S8")),
      ]
    ),
    FunctionDefinition(
      native_function: "S8_xor_S16",
      result: Datatype(name: "S16"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "S8")),
        Variable(name: "num2", datatype: Datatype(name: "S16")),
      ]
    ),
    FunctionDefinition(
      native_function: "S8_xor_S32",
      result: Datatype(name: "S32"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "S8")),
        Variable(name: "num2", datatype: Datatype(name: "S32")),
      ]
    ),
    FunctionDefinition(
      native_function: "S8_xor_S64",
      result: Datatype(name: "S64"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "S8")),
        Variable(name: "num2", datatype: Datatype(name: "S64")),
      ]
    ),
    FunctionDefinition(
      native_function: "S8_xor_U8",
      result: Datatype(name: "S8"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "S8")),
        Variable(name: "num2", datatype: Datatype(name: "U8")),
      ]
    ),
    FunctionDefinition(
      native_function: "S8_xor_U16",
      result: Datatype(name: "S16"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "S8")),
        Variable(name: "num2", datatype: Datatype(name: "U16")),
      ]
    ),
    FunctionDefinition(
      native_function: "S8_xor_U32",
      result: Datatype(name: "S32"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "S8")),
        Variable(name: "num2", datatype: Datatype(name: "U32")),
      ]
    ),
    FunctionDefinition(
      native_function: "S8_xor_U64",
      result: Datatype(name: "S64"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "S8")),
        Variable(name: "num2", datatype: Datatype(name: "U64")),
      ]
    ),
    # Module: S16
    FunctionDefinition(
      native_function: "S16_xor_S8",
      result: Datatype(name: "S16"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "S16")),
        Variable(name: "num2", datatype: Datatype(name: "S8")),
      ]
    ),
    FunctionDefinition(
      native_function: "S16_xor_S16",
      result: Datatype(name: "S16"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "S16")),
        Variable(name: "num2", datatype: Datatype(name: "S16")),
      ]
    ),
    FunctionDefinition(
      native_function: "S16_xor_S32",
      result: Datatype(name: "S32"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "S16")),
        Variable(name: "num2", datatype: Datatype(name: "S32")),
      ]
    ),
    FunctionDefinition(
      native_function: "S16_xor_S64",
      result: Datatype(name: "S64"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "S16")),
        Variable(name: "num2", datatype: Datatype(name: "S64")),
      ]
    ),
    FunctionDefinition(
      native_function: "S16_xor_U8",
      result: Datatype(name: "S16"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "S16")),
        Variable(name: "num2", datatype: Datatype(name: "U8")),
      ]
    ),
    FunctionDefinition(
      native_function: "S16_xor_U16",
      result: Datatype(name: "S16"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "S16")),
        Variable(name: "num2", datatype: Datatype(name: "U16")),
      ]
    ),
    FunctionDefinition(
      native_function: "S16_xor_U32",
      result: Datatype(name: "S32"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "S16")),
        Variable(name: "num2", datatype: Datatype(name: "U32")),
      ]
    ),
    FunctionDefinition(
      native_function: "S16_xor_U64",
      result: Datatype(name: "S64"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "S16")),
        Variable(name: "num2", datatype: Datatype(name: "U64")),
      ]
    ),
    # Module: S32
    FunctionDefinition(
      native_function: "S32_xor_S8",
      result: Datatype(name: "S32"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "S32")),
        Variable(name: "num2", datatype: Datatype(name: "S8")),
      ]
    ),
    FunctionDefinition(
      native_function: "S32_xor_S16",
      result: Datatype(name: "S32"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "S32")),
        Variable(name: "num2", datatype: Datatype(name: "S16")),
      ]
    ),
    FunctionDefinition(
      native_function: "S32_xor_S32",
      result: Datatype(name: "S32"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "S32")),
        Variable(name: "num2", datatype: Datatype(name: "S32")),
      ]
    ),
    FunctionDefinition(
      native_function: "S32_xor_S64",
      result: Datatype(name: "S64"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "S32")),
        Variable(name: "num2", datatype: Datatype(name: "S64")),
      ]
    ),
    FunctionDefinition(
      native_function: "S32_xor_U8",
      result: Datatype(name: "S32"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "S32")),
        Variable(name: "num2", datatype: Datatype(name: "U8")),
      ]
    ),
    FunctionDefinition(
      native_function: "S32_xor_U16",
      result: Datatype(name: "S32"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "S32")),
        Variable(name: "num2", datatype: Datatype(name: "U16")),
      ]
    ),
    FunctionDefinition(
      native_function: "S32_xor_U32",
      result: Datatype(name: "S32"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "S32")),
        Variable(name: "num2", datatype: Datatype(name: "U32")),
      ]
    ),
    FunctionDefinition(
      native_function: "S32_xor_U64",
      result: Datatype(name: "S64"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "S32")),
        Variable(name: "num2", datatype: Datatype(name: "U64")),
      ]
    ),
    # Module: S64
    FunctionDefinition(
      native_function: "S64_xor_S8",
      result: Datatype(name: "S64"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "S64")),
        Variable(name: "num2", datatype: Datatype(name: "S8")),
      ]
    ),
    FunctionDefinition(
      native_function: "S64_xor_S16",
      result: Datatype(name: "S64"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "S64")),
        Variable(name: "num2", datatype: Datatype(name: "S16")),
      ]
    ),
    FunctionDefinition(
      native_function: "S64_xor_S32",
      result: Datatype(name: "S64"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "S64")),
        Variable(name: "num2", datatype: Datatype(name: "S32")),
      ]
    ),
    FunctionDefinition(
      native_function: "S64_xor_S64",
      result: Datatype(name: "S64"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "S64")),
        Variable(name: "num2", datatype: Datatype(name: "S64")),
      ]
    ),
    FunctionDefinition(
      native_function: "S64_xor_U8",
      result: Datatype(name: "S64"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "S64")),
        Variable(name: "num2", datatype: Datatype(name: "U8")),
      ]
    ),
    FunctionDefinition(
      native_function: "S64_xor_U16",
      result: Datatype(name: "S64"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "S64")),
        Variable(name: "num2", datatype: Datatype(name: "U16")),
      ]
    ),
    FunctionDefinition(
      native_function: "S64_xor_U32",
      result: Datatype(name: "S64"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "S64")),
        Variable(name: "num2", datatype: Datatype(name: "U32")),
      ]
    ),
    FunctionDefinition(
      native_function: "S64_xor_U64",
      result: Datatype(name: "S64"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "S64")),
        Variable(name: "num2", datatype: Datatype(name: "U64")),
      ]
    ),
    # Module: U8
    FunctionDefinition(
      native_function: "U8_xor_S8",
      result: Datatype(name: "U8"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "U8")),
        Variable(name: "num2", datatype: Datatype(name: "S8")),
      ]
    ),
    FunctionDefinition(
      native_function: "U8_xor_S16",
      result: Datatype(name: "U16"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "U8")),
        Variable(name: "num2", datatype: Datatype(name: "S16")),
      ]
    ),
    FunctionDefinition(
      native_function: "U8_xor_S32",
      result: Datatype(name: "U32"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "U8")),
        Variable(name: "num2", datatype: Datatype(name: "S32")),
      ]
    ),
    FunctionDefinition(
      native_function: "U8_xor_S64",
      result: Datatype(name: "U64"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "U8")),
        Variable(name: "num2", datatype: Datatype(name: "S64")),
      ]
    ),
    FunctionDefinition(
      native_function: "U8_xor_U8",
      result: Datatype(name: "U8"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "U8")),
        Variable(name: "num2", datatype: Datatype(name: "U8")),
      ]
    ),
    FunctionDefinition(
      native_function: "U8_xor_U16",
      result: Datatype(name: "U16"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "U8")),
        Variable(name: "num2", datatype: Datatype(name: "U16")),
      ]
    ),
    FunctionDefinition(
      native_function: "U8_xor_U32",
      result: Datatype(name: "U32"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "U8")),
        Variable(name: "num2", datatype: Datatype(name: "U32")),
      ]
    ),
    FunctionDefinition(
      native_function: "U8_xor_U64",
      result: Datatype(name: "U64"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "U8")),
        Variable(name: "num2", datatype: Datatype(name: "U64")),
      ]
    ),
    # Module: U16
    FunctionDefinition(
      native_function: "U16_xor_S8",
      result: Datatype(name: "U16"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "U16")),
        Variable(name: "num2", datatype: Datatype(name: "S8")),
      ]
    ),
    FunctionDefinition(
      native_function: "U16_xor_S16",
      result: Datatype(name: "U16"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "U16")),
        Variable(name: "num2", datatype: Datatype(name: "S16")),
      ]
    ),
    FunctionDefinition(
      native_function: "U16_xor_S32",
      result: Datatype(name: "U32"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "U16")),
        Variable(name: "num2", datatype: Datatype(name: "S32")),
      ]
    ),
    FunctionDefinition(
      native_function: "U16_xor_S64",
      result: Datatype(name: "U64"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "U16")),
        Variable(name: "num2", datatype: Datatype(name: "S64")),
      ]
    ),
    FunctionDefinition(
      native_function: "U16_xor_U8",
      result: Datatype(name: "U16"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "U16")),
        Variable(name: "num2", datatype: Datatype(name: "U8")),
      ]
    ),
    FunctionDefinition(
      native_function: "U16_xor_U16",
      result: Datatype(name: "U16"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "U16")),
        Variable(name: "num2", datatype: Datatype(name: "U16")),
      ]
    ),
    FunctionDefinition(
      native_function: "U16_xor_U32",
      result: Datatype(name: "U32"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "U16")),
        Variable(name: "num2", datatype: Datatype(name: "U32")),
      ]
    ),
    FunctionDefinition(
      native_function: "U16_xor_U64",
      result: Datatype(name: "U64"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "U16")),
        Variable(name: "num2", datatype: Datatype(name: "U64")),
      ]
    ),
    # Module: U32
    FunctionDefinition(
      native_function: "U32_xor_S8",
      result: Datatype(name: "U32"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "U32")),
        Variable(name: "num2", datatype: Datatype(name: "S8")),
      ]
    ),
    FunctionDefinition(
      native_function: "U32_xor_S16",
      result: Datatype(name: "U32"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "U32")),
        Variable(name: "num2", datatype: Datatype(name: "S16")),
      ]
    ),
    FunctionDefinition(
      native_function: "U32_xor_S32",
      result: Datatype(name: "U32"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "U32")),
        Variable(name: "num2", datatype: Datatype(name: "S32")),
      ]
    ),
    FunctionDefinition(
      native_function: "U32_xor_S64",
      result: Datatype(name: "U64"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "U32")),
        Variable(name: "num2", datatype: Datatype(name: "S64")),
      ]
    ),
    FunctionDefinition(
      native_function: "U32_xor_U8",
      result: Datatype(name: "U32"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "U32")),
        Variable(name: "num2", datatype: Datatype(name: "U8")),
      ]
    ),
    FunctionDefinition(
      native_function: "U32_xor_U16",
      result: Datatype(name: "U32"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "U32")),
        Variable(name: "num2", datatype: Datatype(name: "U16")),
      ]
    ),
    FunctionDefinition(
      native_function: "U32_xor_U32",
      result: Datatype(name: "U32"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "U32")),
        Variable(name: "num2", datatype: Datatype(name: "U32")),
      ]
    ),
    FunctionDefinition(
      native_function: "U32_xor_U64",
      result: Datatype(name: "U64"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "U32")),
        Variable(name: "num2", datatype: Datatype(name: "U64")),
      ]
    ),
    # Module: U64
    FunctionDefinition(
      native_function: "U64_xor_S8",
      result: Datatype(name: "U64"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "U64")),
        Variable(name: "num2", datatype: Datatype(name: "S8")),
      ]
    ),
    FunctionDefinition(
      native_function: "U64_xor_S16",
      result: Datatype(name: "U64"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "U64")),
        Variable(name: "num2", datatype: Datatype(name: "S16")),
      ]
    ),
    FunctionDefinition(
      native_function: "U64_xor_S32",
      result: Datatype(name: "U64"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "U64")),
        Variable(name: "num2", datatype: Datatype(name: "S32")),
      ]
    ),
    FunctionDefinition(
      native_function: "U64_xor_S64",
      result: Datatype(name: "U64"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "U64")),
        Variable(name: "num2", datatype: Datatype(name: "S64")),
      ]
    ),
    FunctionDefinition(
      native_function: "U64_xor_U8",
      result: Datatype(name: "U64"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "U64")),
        Variable(name: "num2", datatype: Datatype(name: "U8")),
      ]
    ),
    FunctionDefinition(
      native_function: "U64_xor_U16",
      result: Datatype(name: "U64"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "U64")),
        Variable(name: "num2", datatype: Datatype(name: "U16")),
      ]
    ),
    FunctionDefinition(
      native_function: "U64_xor_U32",
      result: Datatype(name: "U64"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "U64")),
        Variable(name: "num2", datatype: Datatype(name: "U32")),
      ]
    ),
    FunctionDefinition(
      native_function: "U64_xor_U64",
      result: Datatype(name: "U64"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "U64")),
        Variable(name: "num2", datatype: Datatype(name: "U64")),
      ]
    ),
])

export bitwise_xor_fn
