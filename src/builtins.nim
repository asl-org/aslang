import common

const print_fn = Function(
    name: "print",
    defs: @[
      FunctionDefinition(native_function: "print_s8", result: Datatype(
          name: "S32"), args: @[Variable(name: "value", datatype: Datatype(
              name: "S8"))]),
      FunctionDefinition(native_function: "print_s16", result: Datatype(
          name: "S32"), args: @[Variable(
          name: "value", datatype: Datatype(name: "S16"))]),
      FunctionDefinition(native_function: "print_s32", result: Datatype(
          name: "S32"), args: @[Variable(
          name: "value", datatype: Datatype(name: "S32"))]),
      FunctionDefinition(native_function: "print_s64", result: Datatype(
          name: "S32"), args: @[Variable(
          name: "value", datatype: Datatype(name: "S64"))]),
      FunctionDefinition(native_function: "print_u8", result: Datatype(
          name: "S32"), args: @[Variable(
          name: "value", datatype: Datatype(name: "U8"))]),
      FunctionDefinition(native_function: "print_u16", result: Datatype(
          name: "S32"), args: @[Variable(
          name: "value", datatype: Datatype(name: "U16"))]),
      FunctionDefinition(native_function: "print_u32", result: Datatype(
          name: "S32"), args: @[Variable(
          name: "value", datatype: Datatype(name: "U32"))]),
      FunctionDefinition(native_function: "print_u64", result: Datatype(
          name: "S32"), args: @[Variable(
          name: "value", datatype: Datatype(name: "U64"))]),
      FunctionDefinition(native_function: "print_f32", result: Datatype(
          name: "S32"), args: @[Variable(
          name: "value", datatype: Datatype(name: "F32"))]),
      FunctionDefinition(native_function: "print_f64", result: Datatype(
          name: "S32"), args: @[Variable(
          name: "value", datatype: Datatype(name: "F64"))]),
  ])

proc builtin_functions*(): seq[Function] = @[
  print_fn
]
