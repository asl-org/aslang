import "../common"

let division_fn =
  Function(
    name: "unsafe_division",
    defs: @[
    # Module: S8
    FunctionDefinition(
      native_function: "S8_unsafe_division_S8",
      result: Datatype(name: "S8"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "S8")),
        Variable(name: "num2", datatype: Datatype(name: "S8")),
      ]
    ),
    FunctionDefinition(
      native_function: "S8_unsafe_division_S16",
      result: Datatype(name: "S8"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "S8")),
        Variable(name: "num2", datatype: Datatype(name: "S16")),
      ]
    ),
    FunctionDefinition(
      native_function: "S8_unsafe_division_S32",
      result: Datatype(name: "S8"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "S8")),
        Variable(name: "num2", datatype: Datatype(name: "S32")),
      ]
    ),
    FunctionDefinition(
      native_function: "S8_unsafe_division_S64",
      result: Datatype(name: "S8"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "S8")),
        Variable(name: "num2", datatype: Datatype(name: "S64")),
      ]
    ),
    FunctionDefinition(
      native_function: "S8_unsafe_division_U8",
      result: Datatype(name: "S8"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "S8")),
        Variable(name: "num2", datatype: Datatype(name: "U8")),
      ]
    ),
    FunctionDefinition(
      native_function: "S8_unsafe_division_U16",
      result: Datatype(name: "S8"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "S8")),
        Variable(name: "num2", datatype: Datatype(name: "U16")),
      ]
    ),
    FunctionDefinition(
      native_function: "S8_unsafe_division_U32",
      result: Datatype(name: "S8"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "S8")),
        Variable(name: "num2", datatype: Datatype(name: "U32")),
      ]
    ),
    FunctionDefinition(
      native_function: "S8_unsafe_division_U64",
      result: Datatype(name: "S8"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "S8")),
        Variable(name: "num2", datatype: Datatype(name: "U64")),
      ]
    ),
    FunctionDefinition(
      native_function: "S8_unsafe_division_F32",
      result: Datatype(name: "F32"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "S8")),
        Variable(name: "num2", datatype: Datatype(name: "F32")),
      ]
    ),
    FunctionDefinition(
      native_function: "S8_unsafe_division_F64",
      result: Datatype(name: "F64"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "S8")),
        Variable(name: "num2", datatype: Datatype(name: "F64")),
      ]
    ),
    # Module: S16
    FunctionDefinition(
      native_function: "S16_unsafe_division_S8",
      result: Datatype(name: "S16"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "S16")),
        Variable(name: "num2", datatype: Datatype(name: "S8")),
      ]
    ),
    FunctionDefinition(
      native_function: "S16_unsafe_division_S16",
      result: Datatype(name: "S16"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "S16")),
        Variable(name: "num2", datatype: Datatype(name: "S16")),
      ]
    ),
    FunctionDefinition(
      native_function: "S16_unsafe_division_S32",
      result: Datatype(name: "S16"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "S16")),
        Variable(name: "num2", datatype: Datatype(name: "S32")),
      ]
    ),
    FunctionDefinition(
      native_function: "S16_unsafe_division_S64",
      result: Datatype(name: "S16"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "S16")),
        Variable(name: "num2", datatype: Datatype(name: "S64")),
      ]
    ),
    FunctionDefinition(
      native_function: "S16_unsafe_division_U8",
      result: Datatype(name: "S16"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "S16")),
        Variable(name: "num2", datatype: Datatype(name: "U8")),
      ]
    ),
    FunctionDefinition(
      native_function: "S16_unsafe_division_U16",
      result: Datatype(name: "S16"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "S16")),
        Variable(name: "num2", datatype: Datatype(name: "U16")),
      ]
    ),
    FunctionDefinition(
      native_function: "S16_unsafe_division_U32",
      result: Datatype(name: "S16"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "S16")),
        Variable(name: "num2", datatype: Datatype(name: "U32")),
      ]
    ),
    FunctionDefinition(
      native_function: "S16_unsafe_division_U64",
      result: Datatype(name: "S16"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "S16")),
        Variable(name: "num2", datatype: Datatype(name: "U64")),
      ]
    ),
    FunctionDefinition(
      native_function: "S16_unsafe_division_F32",
      result: Datatype(name: "F32"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "S16")),
        Variable(name: "num2", datatype: Datatype(name: "F32")),
      ]
    ),
    FunctionDefinition(
      native_function: "S16_unsafe_division_F64",
      result: Datatype(name: "F64"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "S16")),
        Variable(name: "num2", datatype: Datatype(name: "F64")),
      ]
    ),
    # Module: S32
    FunctionDefinition(
      native_function: "S32_unsafe_division_S8",
      result: Datatype(name: "S32"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "S32")),
        Variable(name: "num2", datatype: Datatype(name: "S8")),
      ]
    ),
    FunctionDefinition(
      native_function: "S32_unsafe_division_S16",
      result: Datatype(name: "S32"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "S32")),
        Variable(name: "num2", datatype: Datatype(name: "S16")),
      ]
    ),
    FunctionDefinition(
      native_function: "S32_unsafe_division_S32",
      result: Datatype(name: "S32"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "S32")),
        Variable(name: "num2", datatype: Datatype(name: "S32")),
      ]
    ),
    FunctionDefinition(
      native_function: "S32_unsafe_division_S64",
      result: Datatype(name: "S32"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "S32")),
        Variable(name: "num2", datatype: Datatype(name: "S64")),
      ]
    ),
    FunctionDefinition(
      native_function: "S32_unsafe_division_U8",
      result: Datatype(name: "S32"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "S32")),
        Variable(name: "num2", datatype: Datatype(name: "U8")),
      ]
    ),
    FunctionDefinition(
      native_function: "S32_unsafe_division_U16",
      result: Datatype(name: "S32"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "S32")),
        Variable(name: "num2", datatype: Datatype(name: "U16")),
      ]
    ),
    FunctionDefinition(
      native_function: "S32_unsafe_division_U32",
      result: Datatype(name: "S32"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "S32")),
        Variable(name: "num2", datatype: Datatype(name: "U32")),
      ]
    ),
    FunctionDefinition(
      native_function: "S32_unsafe_division_U64",
      result: Datatype(name: "S32"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "S32")),
        Variable(name: "num2", datatype: Datatype(name: "U64")),
      ]
    ),
    FunctionDefinition(
      native_function: "S32_unsafe_division_F32",
      result: Datatype(name: "F32"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "S32")),
        Variable(name: "num2", datatype: Datatype(name: "F32")),
      ]
    ),
    FunctionDefinition(
      native_function: "S32_unsafe_division_F64",
      result: Datatype(name: "F64"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "S32")),
        Variable(name: "num2", datatype: Datatype(name: "F64")),
      ]
    ),
    # Module: S64
    FunctionDefinition(
      native_function: "S64_unsafe_division_S8",
      result: Datatype(name: "S64"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "S64")),
        Variable(name: "num2", datatype: Datatype(name: "S8")),
      ]
    ),
    FunctionDefinition(
      native_function: "S64_unsafe_division_S16",
      result: Datatype(name: "S64"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "S64")),
        Variable(name: "num2", datatype: Datatype(name: "S16")),
      ]
    ),
    FunctionDefinition(
      native_function: "S64_unsafe_division_S32",
      result: Datatype(name: "S64"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "S64")),
        Variable(name: "num2", datatype: Datatype(name: "S32")),
      ]
    ),
    FunctionDefinition(
      native_function: "S64_unsafe_division_S64",
      result: Datatype(name: "S64"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "S64")),
        Variable(name: "num2", datatype: Datatype(name: "S64")),
      ]
    ),
    FunctionDefinition(
      native_function: "S64_unsafe_division_U8",
      result: Datatype(name: "S64"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "S64")),
        Variable(name: "num2", datatype: Datatype(name: "U8")),
      ]
    ),
    FunctionDefinition(
      native_function: "S64_unsafe_division_U16",
      result: Datatype(name: "S64"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "S64")),
        Variable(name: "num2", datatype: Datatype(name: "U16")),
      ]
    ),
    FunctionDefinition(
      native_function: "S64_unsafe_division_U32",
      result: Datatype(name: "S64"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "S64")),
        Variable(name: "num2", datatype: Datatype(name: "U32")),
      ]
    ),
    FunctionDefinition(
      native_function: "S64_unsafe_division_U64",
      result: Datatype(name: "S64"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "S64")),
        Variable(name: "num2", datatype: Datatype(name: "U64")),
      ]
    ),
    FunctionDefinition(
      native_function: "S64_unsafe_division_F32",
      result: Datatype(name: "F64"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "S64")),
        Variable(name: "num2", datatype: Datatype(name: "F32")),
      ]
    ),
    FunctionDefinition(
      native_function: "S64_unsafe_division_F64",
      result: Datatype(name: "F64"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "S64")),
        Variable(name: "num2", datatype: Datatype(name: "F64")),
      ]
    ),
    # Module: U8
    FunctionDefinition(
      native_function: "U8_unsafe_division_S8",
      result: Datatype(name: "S8"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "U8")),
        Variable(name: "num2", datatype: Datatype(name: "S8")),
      ]
    ),
    FunctionDefinition(
      native_function: "U8_unsafe_division_S16",
      result: Datatype(name: "S8"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "U8")),
        Variable(name: "num2", datatype: Datatype(name: "S16")),
      ]
    ),
    FunctionDefinition(
      native_function: "U8_unsafe_division_S32",
      result: Datatype(name: "S8"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "U8")),
        Variable(name: "num2", datatype: Datatype(name: "S32")),
      ]
    ),
    FunctionDefinition(
      native_function: "U8_unsafe_division_S64",
      result: Datatype(name: "S8"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "U8")),
        Variable(name: "num2", datatype: Datatype(name: "S64")),
      ]
    ),
    FunctionDefinition(
      native_function: "U8_unsafe_division_U8",
      result: Datatype(name: "U8"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "U8")),
        Variable(name: "num2", datatype: Datatype(name: "U8")),
      ]
    ),
    FunctionDefinition(
      native_function: "U8_unsafe_division_U16",
      result: Datatype(name: "U8"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "U8")),
        Variable(name: "num2", datatype: Datatype(name: "U16")),
      ]
    ),
    FunctionDefinition(
      native_function: "U8_unsafe_division_U32",
      result: Datatype(name: "U8"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "U8")),
        Variable(name: "num2", datatype: Datatype(name: "U32")),
      ]
    ),
    FunctionDefinition(
      native_function: "U8_unsafe_division_U64",
      result: Datatype(name: "U8"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "U8")),
        Variable(name: "num2", datatype: Datatype(name: "U64")),
      ]
    ),
    FunctionDefinition(
      native_function: "U8_unsafe_division_F32",
      result: Datatype(name: "F32"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "U8")),
        Variable(name: "num2", datatype: Datatype(name: "F32")),
      ]
    ),
    FunctionDefinition(
      native_function: "U8_unsafe_division_F64",
      result: Datatype(name: "F64"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "U8")),
        Variable(name: "num2", datatype: Datatype(name: "F64")),
      ]
    ),
    # Module: U16
    FunctionDefinition(
      native_function: "U16_unsafe_division_S8",
      result: Datatype(name: "S16"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "U16")),
        Variable(name: "num2", datatype: Datatype(name: "S8")),
      ]
    ),
    FunctionDefinition(
      native_function: "U16_unsafe_division_S16",
      result: Datatype(name: "S16"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "U16")),
        Variable(name: "num2", datatype: Datatype(name: "S16")),
      ]
    ),
    FunctionDefinition(
      native_function: "U16_unsafe_division_S32",
      result: Datatype(name: "S16"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "U16")),
        Variable(name: "num2", datatype: Datatype(name: "S32")),
      ]
    ),
    FunctionDefinition(
      native_function: "U16_unsafe_division_S64",
      result: Datatype(name: "S16"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "U16")),
        Variable(name: "num2", datatype: Datatype(name: "S64")),
      ]
    ),
    FunctionDefinition(
      native_function: "U16_unsafe_division_U8",
      result: Datatype(name: "U16"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "U16")),
        Variable(name: "num2", datatype: Datatype(name: "U8")),
      ]
    ),
    FunctionDefinition(
      native_function: "U16_unsafe_division_U16",
      result: Datatype(name: "U16"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "U16")),
        Variable(name: "num2", datatype: Datatype(name: "U16")),
      ]
    ),
    FunctionDefinition(
      native_function: "U16_unsafe_division_U32",
      result: Datatype(name: "U16"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "U16")),
        Variable(name: "num2", datatype: Datatype(name: "U32")),
      ]
    ),
    FunctionDefinition(
      native_function: "U16_unsafe_division_U64",
      result: Datatype(name: "U16"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "U16")),
        Variable(name: "num2", datatype: Datatype(name: "U64")),
      ]
    ),
    FunctionDefinition(
      native_function: "U16_unsafe_division_F32",
      result: Datatype(name: "F32"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "U16")),
        Variable(name: "num2", datatype: Datatype(name: "F32")),
      ]
    ),
    FunctionDefinition(
      native_function: "U16_unsafe_division_F64",
      result: Datatype(name: "F64"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "U16")),
        Variable(name: "num2", datatype: Datatype(name: "F64")),
      ]
    ),
    # Module: U32
    FunctionDefinition(
      native_function: "U32_unsafe_division_S8",
      result: Datatype(name: "S32"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "U32")),
        Variable(name: "num2", datatype: Datatype(name: "S8")),
      ]
    ),
    FunctionDefinition(
      native_function: "U32_unsafe_division_S16",
      result: Datatype(name: "S32"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "U32")),
        Variable(name: "num2", datatype: Datatype(name: "S16")),
      ]
    ),
    FunctionDefinition(
      native_function: "U32_unsafe_division_S32",
      result: Datatype(name: "S32"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "U32")),
        Variable(name: "num2", datatype: Datatype(name: "S32")),
      ]
    ),
    FunctionDefinition(
      native_function: "U32_unsafe_division_S64",
      result: Datatype(name: "S32"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "U32")),
        Variable(name: "num2", datatype: Datatype(name: "S64")),
      ]
    ),
    FunctionDefinition(
      native_function: "U32_unsafe_division_U8",
      result: Datatype(name: "U32"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "U32")),
        Variable(name: "num2", datatype: Datatype(name: "U8")),
      ]
    ),
    FunctionDefinition(
      native_function: "U32_unsafe_division_U16",
      result: Datatype(name: "U32"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "U32")),
        Variable(name: "num2", datatype: Datatype(name: "U16")),
      ]
    ),
    FunctionDefinition(
      native_function: "U32_unsafe_division_U32",
      result: Datatype(name: "U32"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "U32")),
        Variable(name: "num2", datatype: Datatype(name: "U32")),
      ]
    ),
    FunctionDefinition(
      native_function: "U32_unsafe_division_U64",
      result: Datatype(name: "U32"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "U32")),
        Variable(name: "num2", datatype: Datatype(name: "U64")),
      ]
    ),
    FunctionDefinition(
      native_function: "U32_unsafe_division_F32",
      result: Datatype(name: "F32"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "U32")),
        Variable(name: "num2", datatype: Datatype(name: "F32")),
      ]
    ),
    FunctionDefinition(
      native_function: "U32_unsafe_division_F64",
      result: Datatype(name: "F64"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "U32")),
        Variable(name: "num2", datatype: Datatype(name: "F64")),
      ]
    ),
    # Module: U64
    FunctionDefinition(
      native_function: "U64_unsafe_division_S8",
      result: Datatype(name: "S64"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "U64")),
        Variable(name: "num2", datatype: Datatype(name: "S8")),
      ]
    ),
    FunctionDefinition(
      native_function: "U64_unsafe_division_S16",
      result: Datatype(name: "S64"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "U64")),
        Variable(name: "num2", datatype: Datatype(name: "S16")),
      ]
    ),
    FunctionDefinition(
      native_function: "U64_unsafe_division_S32",
      result: Datatype(name: "S64"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "U64")),
        Variable(name: "num2", datatype: Datatype(name: "S32")),
      ]
    ),
    FunctionDefinition(
      native_function: "U64_unsafe_division_S64",
      result: Datatype(name: "S64"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "U64")),
        Variable(name: "num2", datatype: Datatype(name: "S64")),
      ]
    ),
    FunctionDefinition(
      native_function: "U64_unsafe_division_U8",
      result: Datatype(name: "U64"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "U64")),
        Variable(name: "num2", datatype: Datatype(name: "U8")),
      ]
    ),
    FunctionDefinition(
      native_function: "U64_unsafe_division_U16",
      result: Datatype(name: "U64"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "U64")),
        Variable(name: "num2", datatype: Datatype(name: "U16")),
      ]
    ),
    FunctionDefinition(
      native_function: "U64_unsafe_division_U32",
      result: Datatype(name: "U64"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "U64")),
        Variable(name: "num2", datatype: Datatype(name: "U32")),
      ]
    ),
    FunctionDefinition(
      native_function: "U64_unsafe_division_U64",
      result: Datatype(name: "U64"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "U64")),
        Variable(name: "num2", datatype: Datatype(name: "U64")),
      ]
    ),
    FunctionDefinition(
      native_function: "U64_unsafe_division_F32",
      result: Datatype(name: "F64"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "U64")),
        Variable(name: "num2", datatype: Datatype(name: "F32")),
      ]
    ),
    FunctionDefinition(
      native_function: "U64_unsafe_division_F64",
      result: Datatype(name: "F64"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "U64")),
        Variable(name: "num2", datatype: Datatype(name: "F64")),
      ]
    ),
    # Module: F32
    FunctionDefinition(
      native_function: "F32_unsafe_division_S8",
      result: Datatype(name: "F64"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "F32")),
        Variable(name: "num2", datatype: Datatype(name: "S8")),
      ]
    ),
    FunctionDefinition(
      native_function: "F32_unsafe_division_S16",
      result: Datatype(name: "F64"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "F32")),
        Variable(name: "num2", datatype: Datatype(name: "S16")),
      ]
    ),
    FunctionDefinition(
      native_function: "F32_unsafe_division_S32",
      result: Datatype(name: "F64"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "F32")),
        Variable(name: "num2", datatype: Datatype(name: "S32")),
      ]
    ),
    FunctionDefinition(
      native_function: "F32_unsafe_division_S64",
      result: Datatype(name: "F64"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "F32")),
        Variable(name: "num2", datatype: Datatype(name: "S64")),
      ]
    ),
    FunctionDefinition(
      native_function: "F32_unsafe_division_U8",
      result: Datatype(name: "F64"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "F32")),
        Variable(name: "num2", datatype: Datatype(name: "U8")),
      ]
    ),
    FunctionDefinition(
      native_function: "F32_unsafe_division_U16",
      result: Datatype(name: "F64"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "F32")),
        Variable(name: "num2", datatype: Datatype(name: "U16")),
      ]
    ),
    FunctionDefinition(
      native_function: "F32_unsafe_division_U32",
      result: Datatype(name: "F64"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "F32")),
        Variable(name: "num2", datatype: Datatype(name: "U32")),
      ]
    ),
    FunctionDefinition(
      native_function: "F32_unsafe_division_U64",
      result: Datatype(name: "F64"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "F32")),
        Variable(name: "num2", datatype: Datatype(name: "U64")),
      ]
    ),
    FunctionDefinition(
      native_function: "F32_unsafe_division_F32",
      result: Datatype(name: "F64"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "F32")),
        Variable(name: "num2", datatype: Datatype(name: "F32")),
      ]
    ),
    FunctionDefinition(
      native_function: "F32_unsafe_division_F64",
      result: Datatype(name: "F64"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "F32")),
        Variable(name: "num2", datatype: Datatype(name: "F64")),
      ]
    ),
    # Module: F64
    FunctionDefinition(
      native_function: "F64_unsafe_division_S8",
      result: Datatype(name: "F64"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "F64")),
        Variable(name: "num2", datatype: Datatype(name: "S8")),
      ]
    ),
    FunctionDefinition(
      native_function: "F64_unsafe_division_S16",
      result: Datatype(name: "F64"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "F64")),
        Variable(name: "num2", datatype: Datatype(name: "S16")),
      ]
    ),
    FunctionDefinition(
      native_function: "F64_unsafe_division_S32",
      result: Datatype(name: "F64"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "F64")),
        Variable(name: "num2", datatype: Datatype(name: "S32")),
      ]
    ),
    FunctionDefinition(
      native_function: "F64_unsafe_division_S64",
      result: Datatype(name: "F64"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "F64")),
        Variable(name: "num2", datatype: Datatype(name: "S64")),
      ]
    ),
    FunctionDefinition(
      native_function: "F64_unsafe_division_U8",
      result: Datatype(name: "F64"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "F64")),
        Variable(name: "num2", datatype: Datatype(name: "U8")),
      ]
    ),
    FunctionDefinition(
      native_function: "F64_unsafe_division_U16",
      result: Datatype(name: "F64"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "F64")),
        Variable(name: "num2", datatype: Datatype(name: "U16")),
      ]
    ),
    FunctionDefinition(
      native_function: "F64_unsafe_division_U32",
      result: Datatype(name: "F64"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "F64")),
        Variable(name: "num2", datatype: Datatype(name: "U32")),
      ]
    ),
    FunctionDefinition(
      native_function: "F64_unsafe_division_U64",
      result: Datatype(name: "F64"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "F64")),
        Variable(name: "num2", datatype: Datatype(name: "U64")),
      ]
    ),
    FunctionDefinition(
      native_function: "F64_unsafe_division_F32",
      result: Datatype(name: "F64"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "F64")),
        Variable(name: "num2", datatype: Datatype(name: "F32")),
      ]
    ),
    FunctionDefinition(
      native_function: "F64_unsafe_division_F64",
      result: Datatype(name: "F64"),
      args: @[
        Variable(name: "num1", datatype: Datatype(name: "F64")),
        Variable(name: "num2", datatype: Datatype(name: "F64")),
      ]
    ),
])

export division_fn
