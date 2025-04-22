import results

import module, function_def, variable

proc s64_module(): Result[Module, string] =
  # unsafe_print
  let unsafe_print_variables = @[new_variable("num", "S64")]
  let unsafe_print_signature = new_signature("S64", unsafe_print_variables)
  var unsafe_print_fn = new_function_def("unsafe_print")
  unsafe_print_fn = ? unsafe_print_fn.add_signature(unsafe_print_signature)

  # unsafe_from
  let unsafe_from_variables = @[new_variable("num", "F64")]
  let unsafe_from_signature = new_signature("S64", unsafe_from_variables)
  var unsafe_from_fn = new_function_def("unsafe_from")
  unsafe_from_fn = ? unsafe_from_fn.add_signature(unsafe_from_signature)

  # not
  let not_variables = @[new_variable("num", "S64")]
  let not_signature = new_signature("S64", not_variables)
  var not_fn = new_function_def("not")
  not_fn = ? not_fn.add_signature(not_signature)

  # or
  let or_variables = @[new_variable("num1", "S64"), new_variable("num2", "S64")]
  let or_signature = new_signature("S64", or_variables)
  var or_fn = new_function_def("or")
  or_fn = ? or_fn.add_signature(or_signature)

  # and
  let and_variables = @[new_variable("num1", "S64"), new_variable("num2", "S64")]
  let and_signature = new_signature("S64", and_variables)
  var and_fn = new_function_def("and")
  and_fn = ? and_fn.add_signature(and_signature)

  # xor
  let xor_variables = @[new_variable("num1", "S64"), new_variable("num2", "S64")]
  let xor_signature = new_signature("S64", xor_variables)
  var xor_fn = new_function_def("xor")
  xor_fn = ? xor_fn.add_signature(xor_signature)

  # lshift
  let lshift_variables = @[new_variable("num1", "S64"), new_variable("num2", "S64")]
  let lshift_signature = new_signature("S64", lshift_variables)
  var lshift_fn = new_function_def("lshift")
  lshift_fn = ? lshift_fn.add_signature(lshift_signature)

  # rshift
  let rshift_variables = @[new_variable("num1", "S64"), new_variable("num2", "S64")]
  let rshift_signature = new_signature("S64", rshift_variables)
  var rshift_fn = new_function_def("rshift")
  rshift_fn = ? rshift_fn.add_signature(rshift_signature)

  # unsafe_add
  let unsafe_add_variables = @[new_variable("num1", "S64"), new_variable("num2", "S64")]
  let unsafe_add_signature = new_signature("S64", unsafe_add_variables)
  var unsafe_add_fn = new_function_def("unsafe_add")
  unsafe_add_fn = ? unsafe_add_fn.add_signature(unsafe_add_signature)

  var module = new_native_module("S64")
  module = ? module.add_function(unsafe_print_fn)
  module = ? module.add_function(unsafe_from_fn)
  module = ? module.add_function(not_fn)
  module = ? module.add_function(or_fn)
  module = ? module.add_function(and_fn)
  module = ? module.add_function(xor_fn)
  module = ? module.add_function(lshift_fn)
  module = ? module.add_function(rshift_fn)
  module = ? module.add_function(unsafe_add_fn)

  return ok(module)

proc f64_module(): Result[Module, string] =
  # unsafe_print
  let unsafe_print_variables = @[new_variable("num", "F64")]
  let unsafe_print_signature = new_signature("S64", unsafe_print_variables)
  var unsafe_print_fn = new_function_def("unsafe_print")
  unsafe_print_fn = ? unsafe_print_fn.add_signature(unsafe_print_signature)

  # unsafe_from
  let unsafe_from_variables = @[new_variable("num", "S64")]
  let unsafe_from_signature = new_signature("F64", unsafe_from_variables)
  var unsafe_from_fn = new_function_def("unsafe_from")
  unsafe_from_fn = ? unsafe_from_fn.add_signature(unsafe_from_signature)

  # unsafe_add
  let unsafe_add_variables = @[new_variable("num1", "F64"), new_variable("num2", "F64")]
  let unsafe_add_signature = new_signature("F64", unsafe_add_variables)
  var unsafe_add_fn = new_function_def("unsafe_add")
  unsafe_add_fn = ? unsafe_add_fn.add_signature(unsafe_add_signature)

  var module = new_native_module("F64")
  module = ? module.add_function(unsafe_print_fn)
  module = ? module.add_function(unsafe_from_fn)
  module = ? module.add_function(unsafe_add_fn)


  return ok(module)

proc modules*(): Result[seq[Module], string] =
  ok(@[ ? s64_module(), ? f64_module()])
