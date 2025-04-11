import "../common"

let bitwise_not_fn =
  Function(
    name: "not",
    defs: @[
    FunctionDefinition(
      native_function: "S8_not",
      result: Datatype(name: "S8"),
      args: @[Variable(name: "num1", datatype: Datatype(name: "S8"))]
    ),
    FunctionDefinition(
      native_function: "S16_not",
      result: Datatype(name: "S16"),
      args: @[Variable(name: "num2", datatype: Datatype(name: "S16"))]
    ),
    FunctionDefinition(
      native_function: "S32_not",
      result: Datatype(name: "S32"),
      args: @[Variable(name: "num2", datatype: Datatype(name: "S32"))]
    ),
    FunctionDefinition(
      native_function: "S64_not",
      result: Datatype(name: "S64"),
      args: @[Variable(name: "num2", datatype: Datatype(name: "S64"))]
    ),
    FunctionDefinition(
      native_function: "U8_not",
      result: Datatype(name: "U8"),
      args: @[Variable(name: "num2", datatype: Datatype(name: "U8"))]
    ),
    FunctionDefinition(
      native_function: "U16_not",
      result: Datatype(name: "U16"),
      args: @[Variable(name: "num2", datatype: Datatype(name: "U16"))]
    ),
    FunctionDefinition(
      native_function: "U32_not",
      result: Datatype(name: "U32"),
      args: @[Variable(name: "num2", datatype: Datatype(name: "U32"))]
    ),
    FunctionDefinition(
      native_function: "U64_not",
      result: Datatype(name: "U64"),
      args: @[Variable(name: "num2", datatype: Datatype(name: "U64"))]
    ),
  ])

export bitwise_not_fn
