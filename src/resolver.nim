import results, strformat, sequtils, tables, parseutils, strutils, sets

import resolver/resolved_ast
export resolved_ast

import resolver/deps_analyzer
export deps_analyzer

const DEBUG = false

proc resolve(file: ast.File, module: UserModule, generic: Generic,
    argtype: ArgumentType): Result[ResolvedArgumentType, string] =
  if DEBUG:
    echo fmt"Resolving MODULE GENERIC ARG TYPE: {argtype.location}"
  # NOTE: leaf argument types
  case argtype.kind:
  of ATK_SIMPLE:
    # NOTE: generic argument type
    if argtype.module == generic.name:
      let resolved_generic_type = new_resolved_generic_argument_type(module, generic)
      return ok(new_resolved_argument_type(argtype, resolved_generic_type))
    # NOTE: concrete argument type
    let arg_module = ? file.find_module(argtype.module)
    # NOTE: The module itself where generic is defined can not be used as argument to constraint
    if arg_module.hash == module.hash:
      return err(fmt"{argtype.location} [RE103] module `{argtype.module.asl}` can not be used as an argument in generic constraints")

    if arg_module.generics.len != 0:
      return err(fmt"{argtype.location} [RE104] module `{argtype.module.asl}` expects `{arg_module.generics.len}` generic types but `0` were given")

    let resolved_concrete_type = new_resolved_concrete_argument_type(arg_module)
    ok(new_resolved_argument_type(argtype, resolved_concrete_type))
  # NOTE: nested argument type
  of ATK_NESTED:
    let arg_module = ? file.find_module(argtype.module)
    # NOTE: The module itself where generic is defined can not be used as argument to constraint
    if arg_module.hash == module.hash:
      return err(fmt"{argtype.location} [RE105] module `{argtype.module.asl}` can not be used as an argument in generic constraints")

    if argtype.children.len != arg_module.generics.len:
      return err(fmt"{argtype.location} [RE106] module `{argtype.module.asl}` expects `{arg_module.generics.len}` generic types but `{argtype.children.len}` were given")

    let maybe_user_module = arg_module.user_module
    if maybe_user_module.is_err:
      return err(fmt"{argtype.location} [RE111] module `{argtype.module.asl}` does not expect generics")
    # NOTE: Only user modules can be nested
    var resolved_children: seq[ResolvedArgumentType]
    for child in argtype.children:
      let resolved_child = ? resolve(file, module, generic, child)
      resolved_children.add(resolved_child)

    var concrete_map: Table[Generic, ResolvedArgumentType]
    for (child, generic) in zip(resolved_children, arg_module.generics):
      case child.kind:
      of RATK_CONCRETE:
        let child_module = child.concrete_type.module
        let new_arg_type = ? child_module.argument_type
        let concrete_defs = ? generic.concrete_function_definitions(new_arg_type)
        for def in concrete_defs:
          let maybe_found = child_module.find_function(def)
          # TODO: Resolve return type as well function definition does not account for return type in hash generation
          if maybe_found.is_err:
            return err(fmt"{argtype.location} [RE107] module `{argtype.module.asl}` expects `{child_module.name.asl}` to implement `{def.asl}`")
      of RATK_GENERIC:
        # NOTE: Handle generic parameters as nested type.
        let child_type = child.generic_type
        # NOTE: If the child type's module is same as parent module
        # Then we only allow generic types within.
        if child_type.module.hash != arg_module.hash or
            child_type.generic.hash != generic.hash:
          return err(fmt"{argtype.location} [RE108] module `{argtype.module.asl}` expects generic type `{generic.name.asl}` but found `{child_type.generic.name.asl}`")
      of RATK_NESTED:
        let child_module = child.module
        let child_argtype = ? child_module.argument_type
        let concrete_defs = ? generic.concrete_function_definitions(child_argtype)
        for def in concrete_defs:
          let maybe_found = child_module.find_function(def)
          # TODO: Resolve return type as well, since function definition hash does not account for return type
          if maybe_found.is_err:
            return err(fmt"{argtype.location} [RE110] module `{argtype.module.asl}` expects `{child.module.name.asl}` to implement `{def.asl}`")
      concrete_map[generic] = child

    ok(new_resolved_argument_type(argtype, maybe_user_module.get,
        resolved_children, concrete_map))

proc resolve(file: ast.File, module: UserModule,
    argtype: ArgumentType): Result[ResolvedArgumentType, string] =
  if DEBUG:
    echo fmt"Resolving MODULE ARG TYPE: {argtype.location}"
  # NOTE: leaf argument types
  case argtype.kind:
  of ATK_SIMPLE:
    # NOTE: generic argument type
    let maybe_generic = module.find_generic(argtype.module)
    if maybe_generic.is_ok:
      let generic = maybe_generic.get
      let resolved_generic_type = new_resolved_generic_argument_type(module, generic)
      return ok(new_resolved_argument_type(argtype, resolved_generic_type))

    # NOTE: concrete argument type
    let arg_module = ? file.find_module(argtype.module)
    if arg_module.generics.len != 0:
      return err(fmt"{argtype.location} [RE112] module `{argtype.module.asl}` expects `{arg_module.generics.len}` generic types but `0` were given")
    let resolved_concrete_type = new_resolved_concrete_argument_type(arg_module)
    ok(new_resolved_argument_type(argtype, resolved_concrete_type))
  # NOTE: nested argument type
  of ATK_NESTED:
    let arg_module = ? file.find_module(argtype.module)
    if argtype.children.len != arg_module.generics.len:
      return err(fmt"{argtype.location} [RE113] module `{argtype.module.asl}` expects `{arg_module.generics.len}` generic types but `{argtype.children.len}` were given")

    let maybe_user_module = arg_module.user_module
    # NOTE: Only user modules can be nested
    if maybe_user_module.is_err:
      return err(fmt"{argtype.location} [RE118] module `{argtype.module.asl}` does not expect generics")

    var resolved_children: seq[ResolvedArgumentType]
    for child in argtype.children:
      let resolved_child = ? resolve(file, module, child)
      resolved_children.add(resolved_child)

    var concrete_map: Table[Generic, ResolvedArgumentType]
    for (child, generic) in zip(resolved_children, arg_module.generics):
      case child.kind:
      of RATK_CONCRETE:
        let child_module = child.concrete_type.module
        let child_arg_type = ? child_module.argument_type
        let concrete_defs = ? generic.concrete_function_definitions(child_arg_type)
        for def in concrete_defs:
          let maybe_found = child_module.find_function(def)
          # TODO: Resolve return type as well function definition does not account for return type in hash generation
          if maybe_found.is_err:
            return err(fmt"{argtype.location} [RE114] module `{argtype.module.asl}` expects `{child_module.name.asl}` to implement `{def.asl}`")
      of RATK_GENERIC:
        # NOTE: Handle generic parameters as nested type.
        let child_type = child.generic_type
        # NOTE: If the child type's module is same as parent module
        # Then we only allow generic types within.
        if child_type.module.hash == arg_module.hash:
          if child_type.generic.hash != generic.hash:
            return err(fmt"{argtype.location} [RE115] module `{argtype.module.asl}` expects generic type `{generic.name.asl}` but found `{child_type.generic.name.asl}`")
        else:
          let concrete_defs = ? generic.concrete_function_definitions(
              child_type.generic.argument_type)
          for def in concrete_defs:
            let maybe_found = child_type.generic.find_function(def)
            # TODO: Resolve return type as well function definition does not account for return type in hash generation
            if maybe_found.is_err:
              return err(fmt"{argtype.location} [RE123] module `{argtype.module.asl}` expects `{child.module.name.asl}` to implement `{def.asl}`")
      of RATK_NESTED:
        let child_module = child.module
        let child_argtype = ? child_module.argument_type
        let concrete_defs = ? generic.concrete_function_definitions(child_argtype)
        for def in concrete_defs:
          let maybe_found = child_module.find_function(def)
          # TODO: Resolve return type as well function definition does not account for return type in hash generation
          if maybe_found.is_err:
            return err(fmt"{argtype.location} [RE117] module `{argtype.module.asl}` expects `{child.module.name.asl}` to implement `{def.asl}`")

      concrete_map[generic] = child

    ok(new_resolved_argument_type(argtype, maybe_user_module.get,
        resolved_children, concrete_map))

proc resolve(file: ast.File, argtype: ArgumentType): Result[
    ResolvedArgumentType, string] =
  if DEBUG:
    echo fmt"Resolving ARG TYPE: {argtype.location}"
  # NOTE: leaf argument types
  case argtype.kind:
  of ATK_SIMPLE:
    # NOTE: concrete argument type
    let arg_module = ? file.find_module(argtype.module)
    if arg_module.generics.len != 0:
      return err(fmt"{argtype.location} [RE119] module `{argtype.module.asl}` expects `{arg_module.generics.len}` generic types but `{argtype.children.len}` were given")
    let resolved_concrete_type = new_resolved_concrete_argument_type(arg_module)
    ok(new_resolved_argument_type(argtype, resolved_concrete_type))
  # NOTE: nested argument type
  of ATK_NESTED:
    let arg_module = ? file.find_module(argtype.module)
    if argtype.children.len != arg_module.generics.len:
      return err(fmt"{argtype.location} [RE120] module `{argtype.module.asl}` expects `{arg_module.generics.len}` generic types but `{argtype.children.len}` were given")

    let maybe_user_module = arg_module.user_module
    # NOTE: Only user modules can be nested
    if maybe_user_module.is_err:
      return err(fmt"{argtype.location} [RE124] module `{argtype.module.asl}` does not expect generics")

    var resolved_children: seq[ResolvedArgumentType]
    for child in argtype.children:
      let resolved_child = ? resolve(file, child)
      resolved_children.add(resolved_child)

    var concrete_map: Table[Generic, ResolvedArgumentType]
    for (child, generic) in zip(resolved_children, arg_module.generics):
      case child.kind:
      of RATK_CONCRETE:
        let child_module = child.concrete_type.module
        let new_arg_type = ? child_module.argument_type
        let concrete_defs = ? generic.concrete_function_definitions(new_arg_type)
        for def in concrete_defs:
          let maybe_found = child_module.find_function(def)
          # TODO: Resolve return type as well function definition does not account for return type in hash generation
          if maybe_found.is_err:
            return err(fmt"{argtype.location} [RE121] module `{argtype.module.asl}` expects `{child.module.name.asl}` to implement `{def.asl}`")
      of RATK_GENERIC:
        # NOTE: File level functions will never have generic as input args so this
        # branch must always be unreachable unless there is some issue with the code.
        return err(fmt"{argtype.location} [RE122] [UNREACHABLE] if you see this error that means something is wrong with the code")
      of RATK_NESTED:
        let child_module = child.module
        let child_argtype = ? child_module.argument_type
        let concrete_defs = ? generic.concrete_function_definitions(child_argtype)
        for def in concrete_defs:
          let maybe_found = child_module.find_function(def)
          # TODO: Resolve return type as well function definition does not account for return type in hash generation
          if maybe_found.is_err:
            return err(fmt"{argtype.location} [RE123] module `{argtype.module.asl}` expects `{child.module.name.asl}` to implement `{def.asl}`")

      concrete_map[generic] = child

    ok(new_resolved_argument_type(argtype, maybe_user_module.get,
        resolved_children, concrete_map))

proc resolve(file: ast.File, module: UserModule, generic: Generic,
    def: ArgumentDefinition): Result[ResolvedArgumentDefinition, string] =
  if DEBUG:
    echo fmt"Resolving MODULE ARG DEF: {def.location}"
  let resolved_type = ? resolve(file, module, generic, def.argtype)
  if resolved_type.is_struct:
    ok(new_resolved_argument_definition(def.name, resolved_type, def.location))
  else:
    err(fmt"{def.location} [RE125] module `{def.argtype.module.asl}` is not a struct")

proc resolve(file: ast.File, module: UserModule,
    def: ArgumentDefinition): Result[ResolvedArgumentDefinition, string] =
  if DEBUG:
    echo fmt"Resolving MODULE ARG DEF: {def.location}"
  let resolved_type = ? resolve(file, module, def.argtype)
  if resolved_type.is_struct:
    ok(new_resolved_argument_definition(def.name, resolved_type, def.location))
  else:
    err(fmt"{def.location} [RE126] module `{def.argtype.module.asl}` is not a struct")

proc resolve(file: ast.File, def: ArgumentDefinition): Result[
    ResolvedArgumentDefinition, string] =
  if DEBUG:
    echo fmt"Resolving ARG DEF: {def.location}"
  let resolved_type = ? resolve(file, def.argtype)
  if resolved_type.is_struct:
    ok(new_resolved_argument_definition(def.name, resolved_type, def.location))
  else:
    err(fmt"{def.location} [RE127] module `{def.argtype.module.asl}` is not a struct")

proc resolve(file: ast.File, module: UserModule, generic: Generic,
    def: FunctionDefinition): Result[ResolvedFunctionDefinition, string] =
  if DEBUG:
    echo fmt"Resolving MODULE GENERIC FUNCTION DEF: {def.location}"
  var resolved_args: seq[ResolvedArgumentDefinition]
  for arg in def.args:
    let resolved_arg = ? resolve(file, module, generic, arg)
    resolved_args.add(resolved_arg)

  let resolved_return_type = ? resolve(file, module, generic, def.returns)
  if resolved_return_type.is_struct:
    ok(new_resolved_function_definition(def, resolved_args,
        resolved_return_type))
  else:
    err(fmt"{def.returns.location} [RE128] module `{def.returns.module.asl}` is not a struct")

proc resolve(file: ast.File, module: UserModule,
    def: FunctionDefinition): Result[ResolvedFunctionDefinition, string] =
  if DEBUG:
    echo fmt"Resolving MODULE FUNCTION DEF: {def.location}"
  var resolved_args: seq[ResolvedArgumentDefinition]
  for arg in def.args:
    let resolved_arg = ? resolve(file, module, arg)
    resolved_args.add(resolved_arg)

  let resolved_return_type = ? resolve(file, module, def.returns)
  if resolved_return_type.is_struct:
    ok(new_resolved_function_definition(def, resolved_args,
        resolved_return_type))
  else:
    err(fmt"{def.returns.location} [RE129] module `{def.returns.module.asl}` is not a struct")

proc resolve(file: ast.File, def: FunctionDefinition): Result[
    ResolvedFunctionDefinition, string] =
  if DEBUG:
    echo fmt"Resolving FUNCTION DEF: {def.location}"
  var resolved_args: seq[ResolvedArgumentDefinition]
  for arg in def.args:
    let resolved_arg = ? resolve(file, arg)
    resolved_args.add(resolved_arg)

  let resolved_return_type = ? resolve(file, def.returns)
  if resolved_return_type.is_struct:
    ok(new_resolved_function_definition(def, resolved_args,
        resolved_return_type))
  else:
    err(fmt"{def.returns.location} [RE130] module `{def.returns.module.asl}` is not a struct")

proc resolve(file: ast.File, module: UserModule, generic: Generic): Result[
    ResolvedGeneric, string] =
  if DEBUG:
    echo fmt"Resolving MODULE GENERIC: {generic.location}"
  var resolved_defs: seq[ResolvedFunctionDefinition]
  for def in generic.defs:
    let resolved_def = ? resolve(file, module, generic, def)
    resolved_defs.add(resolved_def)
  ok(new_resolved_generic(generic, resolved_defs))

proc resolve(file: ast.File, module: UserModule, struct: Struct): Result[
    ResolvedStruct, string] =
  if DEBUG:
    echo fmt"Resolving MODULE STRUCT: {struct.location}"
  var resolved_fields: seq[ResolvedArgumentDefinition]
  for field in struct.fields:
    let resolved_field = ? resolve(file, module, field)
    resolved_fields.add(resolved_field)
  new_resolved_struct(struct, resolved_fields)

proc resolve(file: ast.File, module: UserModule, fnref: FunctionRef,
    arity: int): Result[ResolvedFunctionRef, string] =
  if DEBUG:
    echo fmt"Resolving MODULE FUNCTION REF: {fnref.location}"
  case fnref.kind:
  of FRK_LOCAL:
    let defs = ? file.find_functions(fnref.name, arity)
    ok(new_resolved_function_ref(fnref, defs))
  of FRK_MODULE:
    let fnref_module = ? fnref.module
    let argtype = ? resolve(file, module, fnref_module)
    case argtype.kind:
    of RATK_CONCRETE:
      let defs = ? argtype.concrete_type.module.find_functions(fnref.name, arity)
      ok(new_resolved_function_ref(fnref, argtype, defs))
    of RATK_GENERIC:
      let defs = ? argtype.generic_type.generic.find_functions(fnref.name, arity)
      ok(new_resolved_function_ref(fnref, argtype, defs))
    of RATK_NESTED:
      let defs = ? argtype.module.find_functions(fnref.name, arity)
      ok(new_resolved_function_ref(fnref, argtype, defs))

proc resolve(file: ast.File, fnref: FunctionRef, arity: int): Result[
    ResolvedFunctionRef, string] =
  if DEBUG:
    echo fmt"Resolving FUNCTION REF: {fnref.location}"
  case fnref.kind:
  of FRK_LOCAL:
    let defs = ? file.find_functions(fnref.name, arity)
    ok(new_resolved_function_ref(fnref, defs))
  of FRK_MODULE:
    let fnref_module = ? fnref.module
    let argtype = ? resolve(file, fnref_module)
    case argtype.kind:
    of RATK_CONCRETE:
      let defs = ? argtype.concrete_type.module.find_functions(fnref.name, arity)
      ok(new_resolved_function_ref(fnref, argtype, defs))
    of RATK_GENERIC:
      let defs = ? argtype.generic_type.generic.find_functions(fnref.name, arity)
      ok(new_resolved_function_ref(fnref, argtype, defs))
    of RATK_NESTED:
      let defs = ? argtype.module.find_functions(fnref.name, arity)
      ok(new_resolved_function_ref(fnref, argtype, defs))

proc safe_parse*[T](input: string): Result[T, string] =
  when T is SomeSignedInt:
    var temp: BiggestInt
    let code = parse_biggest_int(input, temp)
    if code == 0 or code != input.len:
      return err("Failed to parse signed int from: " & input)
    if temp < T.low.BiggestInt or temp > T.high.BiggestInt:
      return err("Overflow: Value out of range for type " & $T)
    ok(T(temp))
  elif T is SomeUnsignedInt:
    var temp: BiggestUInt
    let code = parse_biggest_uint(input, temp)
    if code == 0 or code != input.len:
      return err("Failed to parse unsigned int from: " & input)
    if temp < T.low.BiggestUInt or temp > T.high.BiggestUInt:
      return err("Overflow: Value out of range for type " & $T)
    ok(T(temp))
  elif T is SomeFloat:
    var temp: BiggestFloat
    let code = parse_biggest_float(input, temp)
    if code == 0 or code != input.len:
      return err("Failed to parse float from: " & input)
    let casted = T(temp)
    if BiggestFloat(casted) != temp:
      return err("Precision loss when converting to " & $T)
    ok(T(temp))
  else:
    err("safe_parse only supports signed/unsigned integers and floating-point types")

proc validate_integer_literal[T](module: NativeModule,
    literal: IntegerLiteral): Result[ResolvedLiteral, string] =
  let maybe_parsed = safe_parse[T](literal.asl)
  if maybe_parsed.is_err:
    err("{literal.location} [RE131] expected integer value between `{T.low}` and `{T.high}` but found `{literal.asl}`")
  else:
    let argtype = ? module.argument_type
    let concrete_type = new_resolved_concrete_argument_type(new_module(module))
    let concrete_module = new_resolved_argument_type(argtype, concrete_type)
    ok(new_resolved_literal(literal, concrete_module))

proc resolve(module: NativeModule, literal: IntegerLiteral): Result[
    ResolvedLiteral, string] =
  case module.name.asl:
  of "S8": validate_integer_literal[int8](module, literal)
  of "S16": validate_integer_literal[int16](module, literal)
  of "S32": validate_integer_literal[int32](module, literal)
  of "S64": validate_integer_literal[int64](module, literal)
  of "U8": validate_integer_literal[uint8](module, literal)
  of "U16": validate_integer_literal[uint16](module, literal)
  of "U32": validate_integer_literal[uint32](module, literal)
  of "U64": validate_integer_literal[uint64](module, literal)
  else: err("{literal.location} [RE132] integer literals are only supported via `S8/S16/S32/S64/U8/U16/U32/U64` native modules")

proc validate_float_literal[T](module: NativeModule,
    literal: FloatLiteral): Result[ResolvedLiteral, string] =
  let maybe_parsed = safe_parse[T](literal.asl)
  if maybe_parsed.is_err:
    if maybe_parsed.error.starts_with("Precision loss"):
      err("{literal.location} [RE133] encountered precision loss in float value `{literal.asl}`")
    else:
      err("{literal.location} [RE134] expected float value but found `{literal.asl}`")
  else:
    let argtype = ? module.argument_type
    let concrete_type = new_resolved_concrete_argument_type(new_module(module))
    let concrete_module = new_resolved_argument_type(argtype, concrete_type)
    ok(new_resolved_literal(literal, concrete_module))

proc resolve(module: NativeModule, literal: FloatLiteral): Result[
    ResolvedLiteral, string] =
  case module.name.asl:
  of "F32": validate_float_literal[float32](module, literal)
  of "F64": validate_float_literal[float64](module, literal)
  else: err("{literal.location} [RE135] float literals are only supported via `F32/F64` native modules")

proc resolve(module: NativeModule, literal: StringLiteral): Result[
    ResolvedLiteral, string] =
  case module.name.asl:
  of "String":
    let argtype = ? module.argument_type
    let concrete_type = new_resolved_concrete_argument_type(new_module(module))
    let concrete_module = new_resolved_argument_type(argtype, concrete_type)
    ok(new_resolved_literal(literal, concrete_module))
  else: err("{literal.location} [RE136] string literals are only supported via `String` native module")

proc resolve(module: NativeModule, literal: Literal): Result[ResolvedLiteral, string] =
  if DEBUG:
    echo fmt"Resolving LITERAL: {literal.location}"
  case literal.kind:
  of LK_INTEGER:
    let integer_literal = ? literal.integer_literal
    resolve(module, integer_literal)
  of LK_FLOAT:
    let float_literal = ? literal.float_literal
    resolve(module, float_literal)
  of LK_STRING:
    let string_literal = ? literal.string_literal
    resolve(module, string_literal)

proc resolve(file: ast.File, module: UserModule, scope: FunctionScope,
    arg: Argument, argdef: ResolvedArgumentDefinition): Result[
    ResolvedArgument, string] =
  if DEBUG:
    echo fmt"Resolving MODULE FUNCTION CALL ARG: {arg.location}"
  case arg.kind:
  of AK_LITERAL:
    case argdef.argtype.kind:
    of RATK_CONCRETE:
      let argmodule = argdef.argtype.concrete_type.module
      case argmodule.kind:
      of MK_NATIVE:
        let native_module = ? argmodule.native_module
        let literal = ? arg.literal
        let resolved_literal = ? resolve(native_module, literal)
        ok(new_resolved_argument(arg, resolved_literal))
      of MK_USER:
        err(fmt"{arg.location} [RE137] expected argument to be a native type but found user type")
    of RATK_NESTED:
      err(fmt"{arg.location} [RE138] expected argument to be a concrete type but found nested type")
    of RATK_GENERIC:
      err(fmt"{arg.location} [RE139] expected argument to be a concrete type but found generic")
  of AK_VARIABLE:
    let argname = ? arg.variable
    let actual_argdef = ? scope.get(argname)
    let actual_type = actual_argdef.argtype
    let expected_type = argdef.argtype
    if actual_type != expected_type:
      err(fmt"{arg.location} [RE140] expected argument `{argname.asl}` to be of type `{expected_type.asl}` but found `{actual_type.asl}`")
    else:
      ok(new_resolved_argument(arg, actual_argdef))

proc resolve(file: ast.File, scope: FunctionScope,
    arg: Argument, argdef: ResolvedArgumentDefinition): Result[
    ResolvedArgument, string] =
  if DEBUG:
    echo fmt"Resolving FUNCTION CALL ARG: {arg.location}"
  case arg.kind:
  of AK_LITERAL:
    case argdef.argtype.kind:
    of RATK_CONCRETE:
      let argmodule = argdef.argtype.concrete_type.module
      case argmodule.kind:
      of MK_NATIVE:
        let native_module = ? argmodule.native_module
        let literal = ? arg.literal
        let resolved_literal = ? resolve(native_module, literal)
        ok(new_resolved_argument(arg, resolved_literal))
      of MK_USER:
        err(fmt"{arg.location} [RE137] expected argument to be a native type but found user type")
    of RATK_NESTED:
      err(fmt"{arg.location} [RE138] expected argument to be a concrete type but found nested type")
    of RATK_GENERIC:
      err(fmt"{arg.location} [RE139] expected argument to be a concrete type but found generic")
  of AK_VARIABLE:
    let argname = ? arg.variable
    let actual_argdef = ? scope.get(argname)
    let actual_type = actual_argdef.argtype
    let expected_type = argdef.argtype
    if actual_type != expected_type:
      err(fmt"{arg.location} [RE140] expected argument `{argname.asl}` to be of type `{expected_type.asl}` but found `{actual_type.asl}`")
    else:
      ok(new_resolved_argument(arg, actual_argdef))

proc resolve(file: ast.File, module: UserModule, scope: FunctionScope,
    def: ResolvedFunctionDefinition, args: seq[Argument]): Result[seq[
    ResolvedArgument], string] =
  var resolved_args: seq[ResolvedArgument]
  for index, (argdef, arg) in zip(def.args, args):
    let resolved_argument = ? resolve(file, module, scope, arg, argdef)
    resolved_args.add(resolved_argument)
  ok(resolved_args)

proc resolve(file: ast.File, scope: FunctionScope,
    def: ResolvedFunctionDefinition, args: seq[Argument]): Result[seq[
    ResolvedArgument], string] =
  var resolved_args: seq[ResolvedArgument]
  for index, (argdef, arg) in zip(def.args, args):
    let resolved_argument = ? resolve(file, scope, arg, argdef)
    resolved_args.add(resolved_argument)
  ok(resolved_args)

proc resolve(file: ast.File, module: UserModule, scope: FunctionScope,
    fncall: FunctionCall): Result[ResolvedFunctionCall, string] =
  if DEBUG:
    echo fmt"Resolving MODULE FUNCTION CALL: {fncall.location}"
  let resolved_fnref = ? resolve(file, module, fncall.fnref, fncall.args.len)
  for def in resolved_fnref.defs:
    case resolved_fnref.kind
    of RFRK_MODULE:
      # NOTE: Will also have to handle the generic calls.
      let maybe_arg_user_module = resolved_fnref.argtype.user_module
      if maybe_arg_user_module.is_ok:
        let resolved_def = ? resolve(file, maybe_arg_user_module.get, def)
        let concrete_def = resolved_def.concrete_function_definition(
            resolved_fnref.argtype)
        let maybe_match = resolve(file, module, scope, concrete_def, fncall.args)
        if maybe_match.is_ok:
          return ok(new_resolved_function_call(fncall, resolved_fnref,
              concrete_def, maybe_match.get))
        # else:
        #   echo maybe_match.error

      let resolved_def = ? resolve(file, def)
      let concrete_def = resolved_def.concrete_function_definition(
            resolved_fnref.argtype)
      let maybe_match = resolve(file, module, scope, concrete_def, fncall.args)
      if maybe_match.is_ok:
        return ok(new_resolved_function_call(fncall, resolved_fnref,
            concrete_def, maybe_match.get))
      # else:
      #   echo maybe_match.error
    of RFRK_LOCAL:
      let resolved_def = ? resolve(file, def)
      let maybe_match = resolve(file, module, scope, resolved_def, fncall.args)
      if maybe_match.is_ok:
        return ok(new_resolved_function_call(fncall, resolved_fnref,
            resolved_def, maybe_match.get))
      # else:
      #   echo maybe_match.error

  case fncall.fnref.kind:
  of FRK_LOCAL:
    err(fmt"{fncall.location} [RE141] function `{fncall.fnref.name.asl}` does not exist")
  of FRK_MODULE:
    let fnref_module = ? fncall.fnref.module
    err(fmt"{fncall.location} [RE142] module `{fnref_module.asl}` does not have any function named `{fncall.fnref.name.asl}`")

proc resolve(file: ast.File, scope: FunctionScope,
    fncall: FunctionCall): Result[ResolvedFunctionCall, string] =
  if DEBUG:
    echo fmt"Resolving FUNCTION CALL: {fncall.location}"
  let resolved_fnref = ? resolve(file, fncall.fnref, fncall.args.len)
  for def in resolved_fnref.defs:
    case resolved_fnref.kind
    of RFRK_MODULE:
      # NOTE: Will also have to handle the generic calls.
      let maybe_arg_user_module = resolved_fnref.argtype.user_module
      if maybe_arg_user_module.is_ok:
        let resolved_def = ? resolve(file, maybe_arg_user_module.get, def)
        let concrete_def = resolved_def.concrete_function_definition(
            resolved_fnref.argtype)
        let maybe_match = resolve(file, scope, concrete_def, fncall.args)
        if maybe_match.is_ok:
          return ok(new_resolved_function_call(fncall, resolved_fnref,
              concrete_def, maybe_match.get))
        # else:
        #   echo maybe_match.error

      let resolved_def = ? resolve(file, def)
      let concrete_def = resolved_def.concrete_function_definition(
            resolved_fnref.argtype)
      let maybe_match = resolve(file, scope, concrete_def, fncall.args)
      if maybe_match.is_ok:
        return ok(new_resolved_function_call(fncall, resolved_fnref,
            concrete_def, maybe_match.get))
      # else:
      #   echo maybe_match.error
    of RFRK_LOCAL:
      let resolved_def = ? resolve(file, def)
      let maybe_match = resolve(file, scope, resolved_def, fncall.args)
      if maybe_match.is_ok:
        return ok(new_resolved_function_call(fncall, resolved_fnref,
            resolved_def, maybe_match.get))
      # else:
      #   echo maybe_match.error

  case fncall.fnref.kind:
  of FRK_LOCAL:
    err(fmt"{fncall.location} [RE141] function `{fncall.fnref.name.asl}` does not exist")
  of FRK_MODULE:
    let fnref_module = ? fncall.fnref.module
    err(fmt"{fncall.location} [RE142] module `{fnref_module.asl}` does not have any function named `{fncall.fnref.name.asl}`")

proc resolve(file: ast.File, module: UserModule, struct_ref: StructRef): Result[
    ResolvedStructRef, string] =
  if DEBUG:
    echo fmt"Resolving MODULE FUNCTION STRUCT REF: {struct_ref.location}"
  let resolved_argtype = ? resolve(file, module, struct_ref.module)
  let resolved_argmodule = ? resolved_argtype.user_module
  let struct =
    case struct_ref.kind:
    of SRK_DEFAULT: ? resolved_argmodule.find_struct()
    of SRK_NAMED: ? resolved_argmodule.find_struct( ? struct_ref.struct)
  let resolved_struct = ? resolve(file, resolved_argmodule, struct)
  let concrete_struct = ? resolved_struct.concrete_struct(
      resolved_argtype.concrete_map)
  ok(new_resolved_struct_ref(struct_ref, resolved_argtype, concrete_struct))

proc resolve(file: ast.File, struct_ref: StructRef): Result[
    ResolvedStructRef, string] =
  if DEBUG:
    echo fmt"Resolving FUNCTION STRUCT REF: {struct_ref.location}"
  let resolved_argtype = ? resolve(file, struct_ref.module)
  let resolved_argmodule = ? resolved_argtype.user_module
  let struct =
    case struct_ref.kind:
    of SRK_DEFAULT: ? resolved_argmodule.find_struct()
    of SRK_NAMED: ? resolved_argmodule.find_struct( ? struct_ref.struct)
  let resolved_struct = ? resolve(file, resolved_argmodule, struct)
  let concrete_struct = ? resolved_struct.concrete_struct(
      resolved_argtype.concrete_map)
  ok(new_resolved_struct_ref(struct_ref, resolved_argtype, concrete_struct))

proc resolve(file: ast.File, module: UserModule, scope: FunctionScope,
    init: StructInit): Result[ResolvedStructInit, string] =
  if DEBUG:
    echo fmt"Resolving MODULE FUNCTION STEP STATEMENT EXPRESSION STRUCT INIT: {init.location}"
  let resolved_struct_ref = ? resolve(file, module, init.struct_ref)
  var resolved_fields = new_seq[ResolvedArgument](init.args.len)
  for kwarg in init.args:
    let field_index = ? resolved_struct_ref.struct.find_field_id(kwarg.name)
    let field_def = resolved_struct_ref.struct.fields[field_index]
    resolved_fields[field_index] = ? resolve(file, module, scope, kwarg.value, field_def)
  ok(new_resolved_struct_init(init, resolved_struct_ref, resolved_fields))

proc resolve(file: ast.File, scope: FunctionScope,
    init: StructInit): Result[ResolvedStructInit, string] =
  if DEBUG:
    echo fmt"Resolving FUNCTION STEP STATEMENT EXPRESSION STRUCT INIT: {init.location}"
  let resolved_struct_ref = ? resolve(file, init.struct_ref)
  var resolved_fields = new_seq[ResolvedArgument](init.args.len)
  for kwarg in init.args:
    let field_index = ? resolved_struct_ref.struct.find_field_id(kwarg.name)
    let field_def = resolved_struct_ref.struct.fields[field_index]
    resolved_fields[field_index] = ? resolve(file, scope, kwarg.value, field_def)
  ok(new_resolved_struct_init(init, resolved_struct_ref, resolved_fields))

proc resolve(file: ast.File, module: UserModule, scope: FunctionScope,
    init: Initializer): Result[ResolvedInitializer, string] =
  if DEBUG:
    echo fmt"Resolving MODULE FUNCTION STEP STATEMENT EXPRESSION INIT: {init.location}"
  case init.kind:
  of IK_LITERAL:
    let literal_init = ? init.literal
    echo literal_init.asl
    err(fmt"{literal_init.location} todo: implement literal init resolution")
  of IK_STRUCT:
    let resolved_struct_init = ? resolve(file, module, scope, ? init.struct)
    ok(new_resolved_initializer(init, resolved_struct_init))

proc resolve(file: ast.File, scope: FunctionScope,
    init: Initializer): Result[ResolvedInitializer, string] =
  if DEBUG:
    echo fmt"Resolving FUNCTION STEP STATEMENT EXPRESSION INIT: {init.location}"
  case init.kind:
  of IK_LITERAL:
    let literal_init = ? init.literal
    let resolved_argtype = ? resolve(file, literal_init.module)
    let literal_module = ? resolved_argtype.native_module
    let resolved_literal = ? resolve(literal_module, literal_init.literal)
    let resolved_literal_init = new_resolved_literal_init(literal_init, resolved_literal)
    ok(new_resolved_initializer(init, resolved_literal_init))
  of IK_STRUCT:
    let struct = ? init.struct
    let resolved_struct_init = ? resolve(file, scope, struct)
    ok(new_resolved_initializer(init, resolved_struct_init))

proc resolve(file: ast.File, module: UserModule, scope: FunctionScope,
    struct_get: StructGet): Result[ResolvedStructGet, string] =
  if DEBUG:
    echo fmt"Resolving MODULE FUNCTION STEP STATEMENT EXPRESSION STRUCT GET: {struct_get.location}"
  let argdef = ? scope.get(struct_get.name)
  let argmodule = ? argdef.argtype.user_module
  let default_struct = ? argmodule.find_struct()
  let resolved_struct = ? resolve(file, argmodule, default_struct)
  let concrete_struct = ? resolved_struct.concrete_struct(
      argdef.argtype.concrete_map)
  let field_id = ? concrete_struct.find_field_id(struct_get.field)
  let resolved_field = concrete_struct.fields[field_id]
  ok(new_resolved_struct_get(struct_get, argdef.argtype, resolved_field))

proc resolve(file: ast.File, scope: FunctionScope,
    struct_get: StructGet): Result[ResolvedStructGet, string] =
  if DEBUG:
    echo fmt"Resolving FUNCTION STEP STATEMENT EXPRESSION STRUCT GET: {struct_get.location}"
  let argdef = ? scope.get(struct_get.name)
  let argmodule = ? argdef.argtype.user_module
  let default_struct = ? argmodule.find_struct()
  let resolved_struct = ? resolve(file, argmodule, default_struct)
  let concrete_struct = ? resolved_struct.concrete_struct(
      argdef.argtype.concrete_map)
  let field_id = ? concrete_struct.find_field_id(struct_get.field)
  let resolved_field = concrete_struct.fields[field_id]
  ok(new_resolved_struct_get(struct_get, argdef.argtype, resolved_field))

proc resolve(file: ast.File, module: UserModule, scope: FunctionScope,
    expression: Expression): Result[ResolvedExpression, string] =
  if DEBUG:
    echo fmt"Resolving MODULE FUNCTION STEP STATEMENT EXPRESSION: {expression.location}"
  case expression.kind:
  of EK_FNCALL:
    let fncall = ? expression.fncall
    let resolved_function_call = ? resolve(file, module, scope, fncall)
    ok(new_resolved_expression(expression, resolved_function_call))
  of EK_INIT:
    let init = ? expression.init
    let resolved_init = ? resolve(file, module, scope, init)
    ok(new_resolved_expression(expression, resolved_init))
  of EK_STRUCT_GET:
    let struct_get = ? expression.struct_get
    let resolved_struct_get = ? resolve(file, module, scope, struct_get)
    ok(new_resolved_expression(expression, resolved_struct_get))
  of EK_VARIABLE:
    let variable = ? expression.variable
    let resolved_arg = ? scope.get(variable)
    ok(new_resolved_expression(expression, resolved_arg))

proc resolve(file: ast.File, scope: FunctionScope,
    expression: Expression): Result[ResolvedExpression, string] =
  if DEBUG:
    echo fmt"Resolving FUNCTION STEP STATEMENT EXPRESSION: {expression.location}"
  case expression.kind:
  of EK_FNCALL:
    let fncall = ? expression.fncall
    let resolved_function_call = ? resolve(file, scope, fncall)
    ok(new_resolved_expression(expression, resolved_function_call))
  of EK_INIT:
    let init = ? expression.init
    let resolved_init = ? resolve(file, scope, init)
    ok(new_resolved_expression(expression, resolved_init))
  of EK_STRUCT_GET:
    let struct_get = ? expression.struct_get
    let resolved_struct_get = ? resolve(file, scope, struct_get)
    ok(new_resolved_expression(expression, resolved_struct_get))
  of EK_VARIABLE:
    let variable = ? expression.variable
    let resolved_arg = ? scope.get(variable)
    ok(new_resolved_expression(expression, resolved_arg))

proc resolve(file: ast.File, module: UserModule, scope: FunctionScope,
    statement: Statement): Result[ResolvedStatement, string] =
  if DEBUG:
    echo fmt"Resolving MODULE FUNCTION STEP STATEMENT: {statement.location}"
  let resolved_expression = ? resolve(file, module, scope, statement.expression)
  let arg = new_resolved_argument_definition(statement.arg,
      resolved_expression.return_type, statement.location)
  ok(new_resolved_statement(statement, arg, resolved_expression))

proc resolve(file: ast.File, scope: FunctionScope,
    statement: Statement): Result[ResolvedStatement, string] =
  if DEBUG:
    echo fmt"Resolving FUNCTION STEP STATEMENT: {statement.location}"
  let resolved_expression = ? resolve(file, scope, statement.expression)
  let arg = new_resolved_argument_definition(statement.arg,
      resolved_expression.return_type, statement.location)
  ok(new_resolved_statement(statement, arg, resolved_expression))

proc resolve(file: ast.File, scope: FunctionScope,
    operand: ResolvedArgumentDefinition, pattern: StructPattern): Result[
    ResolvedStructPattern, string] =
  if DEBUG:
    echo fmt"Resolving FUNCTION STEP MATCH CASE DEF STRUCT PATTERN: {pattern.location}"
  case pattern.kind
  of SPK_DEFAULT:
    let operand_module = ? operand.argtype.user_module
    let struct = ? operand_module.find_struct()
    let resolved_struct = ? resolve(file, operand_module, struct)
    let concrete_struct = ? resolved_struct.concrete_struct(
        operand.argtype.concrete_map)
    var fields: seq[ResolvedArgumentDefinition]
    for (key, value) in pattern.args:
      let field_id = ? concrete_struct.find_field_id(key)
      let resolved_field = concrete_struct.fields[field_id]
      let value_arg_def = new_resolved_argument_definition(value,
          resolved_field.argtype, value.location)
      fields.add(value_arg_def)
    ok(new_resolved_struct_pattern(pattern, fields, resolved_struct))
  of SPK_NAMED:
    let operand_module = ? operand.argtype.user_module
    let struct_name = ? pattern.struct
    let struct = ? operand_module.find_struct(struct_name)
    let resolved_struct = ? resolve(file, operand_module, struct)
    let concrete_struct = ? resolved_struct.concrete_struct(
        operand.argtype.concrete_map)
    var fields: seq[ResolvedArgumentDefinition]
    for (key, value) in pattern.args:
      let field_id = ? concrete_struct.find_field_id(key)
      let resolved_field = concrete_struct.fields[field_id]
      let value_arg_def = new_resolved_argument_definition(value,
          resolved_field.argtype, value.location)
      fields.add(value_arg_def)
    ok(new_resolved_struct_pattern(pattern, fields, resolved_struct))

proc resolve(file: ast.File, module: UserModule, scope: FunctionScope,
    operand: ResolvedArgumentDefinition, def: CaseDefinition): Result[
        ResolvedCaseDefinition, string] =
  if DEBUG:
    echo fmt"Resolving MODULE FUNCTION STEP MATCH CASE DEF: {def.location}"
  case def.pattern.kind:
  of CPK_LITERAL:
    let literal = ? def.pattern.literal
    case literal.kind:
    of LK_INTEGER:
      let integer_literal = ? literal.integer_literal
      case operand.argtype.kind:
      of RATK_CONCRETE:
        let native_module = ? operand.argtype.native_module
        let resolved_literal = ? resolve(native_module, integer_literal)
        let resolved_case_pattern = new_resolved_case_pattern(def.pattern, resolved_literal)
        ok(new_resolved_case_definition(def, resolved_case_pattern))
      else:
        err(fmt"{literal.location} only native modules support literal matching")
    else:
      err(fmt"{literal.location} only integer literals supported in case pattern")
  of CPK_STRUCT:
    let operand_module = ? operand.argtype.user_module
    if operand_module.structs.len < 2:
      return err("{operand.location} Module `{operand_module.name.asl}` is not a union")

    let pattern = ? def.pattern.struct
    let resolved_pattern = ? resolve(file, scope, operand, pattern)
    for field in resolved_pattern.fields:
      discard ? scope.add(field)
    let resolved_case_pattern = new_resolved_case_pattern(def.pattern, resolved_pattern)
    ok(new_resolved_case_definition(def, resolved_case_pattern))

proc resolve(file: ast.File, scope: FunctionScope,
    operand: ResolvedArgumentDefinition, def: CaseDefinition): Result[
    ResolvedCaseDefinition, string] =
  if DEBUG:
    echo fmt"Resolving FUNCTION STEP MATCH CASE DEF: {def.location}"
  case def.pattern.kind:
  of CPK_LITERAL:
    let literal = ? def.pattern.literal
    case literal.kind:
    of LK_INTEGER:
      let integer_literal = ? literal.integer_literal
      case operand.argtype.kind:
      of RATK_CONCRETE:
        let native_module = ? operand.argtype.native_module
        let resolved_literal = ? resolve(native_module, integer_literal)
        let resolved_case_pattern = new_resolved_case_pattern(def.pattern, resolved_literal)
        ok(new_resolved_case_definition(def, resolved_case_pattern))
      else:
        err(fmt"{literal.location} only native modules support literal matching")
    else:
      err(fmt"{literal.location} only integer literals supported in case pattern")
  of CPK_STRUCT:
    let operand_module = ? operand.argtype.user_module
    if operand_module.structs.len < 2:
      return err("{operand.location} Module `{operand_module.name.asl}` is not a union")

    let pattern = ? def.pattern.struct
    let resolved_pattern = ? resolve(file, scope, operand, pattern)
    for field in resolved_pattern.fields:
      discard ? scope.add(field)
    let resolved_case_pattern = new_resolved_case_pattern(def.pattern, resolved_pattern)
    ok(new_resolved_case_definition(def, resolved_case_pattern))

proc resolve(file: ast.File, module: UserModule, scope: FunctionScope,
    operand: ResolvedArgumentDefinition, case_block: Case): Result[ResolvedCase, string] =
  if DEBUG:
    echo fmt"Resolving MODULE FUNCTION STEP MATCH CASE: {case_block.location}"
  let resolved_case_def = ? resolve(file, module, scope, operand,
      case_block.def)
  var case_block_scope = scope.clone()
  var resolved_statements: seq[ResolvedStatement]
  for statement in case_block.statements:
    let resolved_statement = ? resolve(file, module, case_block_scope, statement)
    resolved_statements.add(resolved_statement)
    case_block_scope = ? scope.add(resolved_statement.arg)
  ok(new_resolved_case(case_block, resolved_case_def, resolved_statements))

proc resolve(file: ast.File, scope: FunctionScope,
    operand: ResolvedArgumentDefinition, case_block: Case): Result[ResolvedCase, string] =
  if DEBUG:
    echo fmt"Resolving FUNCTION STEP MATCH CASE: {case_block.location}"
  let resolved_case_def = ? resolve(file, scope, operand,
      case_block.def)
  var case_block_scope = scope.clone()
  var resolved_statements: seq[ResolvedStatement]
  for statement in case_block.statements:
    let resolved_statement = ? resolve(file, case_block_scope, statement)
    resolved_statements.add(resolved_statement)
    case_block_scope = ? scope.add(resolved_statement.arg)
  ok(new_resolved_case(case_block, resolved_case_def, resolved_statements))

proc resolve(file: ast.File, module: UserModule, scope: FunctionScope,
    else_block: Else): Result[ResolvedElse, string] =
  if DEBUG:
    echo fmt"Resolving MODULE FUNCTION STEP MATCH ELSE: {else_block.location}"
  var else_block_scope = scope.clone()
  var resolved_statements: seq[ResolvedStatement]
  for statement in else_block.statements:
    let resolved_statement = ? resolve(file, module, else_block_scope, statement)
    resolved_statements.add(resolved_statement)
    else_block_scope = ? scope.add(resolved_statement.arg)
  ok(new_resolved_else(else_block, resolved_statements))

proc resolve(file: ast.File, scope: FunctionScope,
    else_block: Else): Result[ResolvedElse, string] =
  if DEBUG:
    echo fmt"Resolving FUNCTION STEP MATCH ELSE: {else_block.location}"
  var else_block_scope = scope.clone()
  var resolved_statements: seq[ResolvedStatement]
  for statement in else_block.statements:
    let resolved_statement = ? resolve(file, else_block_scope, statement)
    resolved_statements.add(resolved_statement)
    else_block_scope = ? scope.add(resolved_statement.arg)
  ok(new_resolved_else(else_block, resolved_statements))

proc resolve(file: ast.File, module: UserModule, scope: FunctionScope,
    match: Match): Result[ResolvedMatch, string] =
  if DEBUG:
    echo fmt"Resolving MODULE FUNCTION STEP MATCH: {match.location}"
  let operand_def = ? scope.get(match.def.operand)

  case match.kind:
  of MK_CASE_ONLY:
    var resolved_case_blocks: seq[ResolvedCase]
    for case_block in match.case_blocks:
      let resolved_case_block = ? resolve(file, module, scope, operand_def, case_block)
      resolved_case_blocks.add(resolved_case_block)
    # TODO: Validate uniqueness of case block patterns so that they don't overlap
    for resolved_case_block in resolved_case_blocks:
      if resolved_case_block.return_type != resolved_case_blocks[0].return_type:
        return err(fmt"{resolved_case_block.location} case block return type does not match with else block return type at {resolved_case_blocks[0].location}")
    ok(new_resolved_match(match, resolved_case_blocks))
  of MK_COMPLETE:
    var resolved_case_blocks: seq[ResolvedCase]
    for case_block in match.case_blocks:
      let resolved_case_block = ? resolve(file, module, scope, operand_def, case_block)
      resolved_case_blocks.add(resolved_case_block)
    let else_block = ? match.else_block
    let resolved_else_block = ? resolve(file, module, scope, else_block)
    # TODO: Validate uniqueness of case block patterns so that they don't overlap
    for resolved_case_block in resolved_case_blocks:
      if resolved_case_block.return_type != resolved_else_block.return_type:
        return err(fmt"{resolved_case_block.location} case block return type does not match with else block return type at {resolved_else_block.location}")
    ok(new_resolved_match(match, resolved_case_blocks, resolved_else_block))

proc resolve(file: ast.File, scope: FunctionScope,
    match: Match): Result[ResolvedMatch, string] =
  if DEBUG:
    echo fmt"Resolving FUNCTION STEP MATCH: {match.location}"
  let operand_def = ? scope.get(match.def.operand)

  case match.kind:
  of MK_CASE_ONLY:
    var resolved_case_blocks: seq[ResolvedCase]
    for case_block in match.case_blocks:
      let resolved_case_block = ? resolve(file, scope, operand_def, case_block)
      resolved_case_blocks.add(resolved_case_block)
    # TODO: Validate uniqueness of case block patterns so that they don't overlap
    for resolved_case_block in resolved_case_blocks:
      if resolved_case_block.return_type != resolved_case_blocks[0].return_type:
        return err(fmt"{resolved_case_block.location} case block return type does not match with else block return type at {resolved_case_blocks[0].location}")
    ok(new_resolved_match(match, resolved_case_blocks))
  of MK_COMPLETE:
    var resolved_case_blocks: seq[ResolvedCase]
    for case_block in match.case_blocks:
      let resolved_case_block = ? resolve(file, scope, operand_def, case_block)
      resolved_case_blocks.add(resolved_case_block)
    let else_block = ? match.else_block
    let resolved_else_block = ? resolve(file, scope, else_block)
    # TODO: Validate uniqueness of case block patterns so that they don't overlap
    for resolved_case_block in resolved_case_blocks:
      if resolved_case_block.return_type != resolved_else_block.return_type:
        return err(fmt"{resolved_case_block.location} case block return type does not match with else block return type at {resolved_else_block.location}")
    ok(new_resolved_match(match, resolved_case_blocks, resolved_else_block))

proc resolve(file: ast.File, module: UserModule, scope: FunctionScope,
    step: FunctionStep): Result[ResolvedFunctionStep, string] =
  if DEBUG:
    echo fmt"Resolving MODULE FUNCTION STEP: {step.location}"
  case step.kind:
  of FSK_STATEMENT:
    let statement = ? step.statement
    let resolved_statement = ? resolve(file, module, scope, statement)
    ok(new_resolved_function_step(step, resolved_statement))
  of FSK_MATCH:
    let match = ? step.match
    let resolved_match = ? resolve(file, module, scope, match)
    ok(new_resolved_function_step(step, resolved_match))

proc resolve(file: ast.File, scope: FunctionScope,
    step: FunctionStep): Result[ResolvedFunctionStep, string] =
  if DEBUG:
    echo fmt"Resolving FUNCTION STEP: {step.location}"
  case step.kind:
  of FSK_STATEMENT:
    let statement = ? step.statement
    let resolved_statement = ? resolve(file, scope, statement)
    ok(new_resolved_function_step(step, resolved_statement))
  of FSK_MATCH:
    let match = ? step.match
    let resolved_match = ? resolve(file, scope, match)
    ok(new_resolved_function_step(step, resolved_match))

proc resolve(file: ast.File, module: UserModule, function: Function): Result[
    ResolvedFunction, string] =
  if DEBUG:
    echo fmt"Resolving MODULE FUNCTION: {function.location}"
  let resolved_function_def = ? resolve(file, module, function.def)
  var scope = FunctionScope()
  for arg in resolved_function_def.args:
    scope = ? scope.add(arg)

  var resolved_steps: seq[ResolvedFunctionStep]
  for step in function.steps:
    let resolved_step = ? resolve(file, module, scope, step)
    resolved_steps.add(resolved_step)
    scope = ? scope.add(resolved_step.arg)

  let fn_return_type = resolved_steps[^1].arg.argtype
  if fn_return_type != resolved_function_def.returns:
    let step_location = function.steps[^1].location
    return err(fmt"{step_location} expected function to return `{resolved_function_def.returns.asl}`")

  ok(new_resolved_function(function, resolved_function_def, resolved_steps))

proc resolve(file: ast.File, function: Function): Result[ResolvedFunction, string] =
  if DEBUG:
    echo fmt"Resolving FUNCTION: {function.location}"
  let resolved_function_def = ? resolve(file, function.def)
  var scope = FunctionScope()
  for arg in resolved_function_def.args:
    scope = ? scope.add(arg)
  var resolved_steps: seq[ResolvedFunctionStep]
  for step in function.steps:
    let resolved_step = ? resolve(file, scope, step)
    resolved_steps.add(resolved_step)
    scope = ? scope.add(resolved_step.arg)

  let fn_return_type = resolved_steps[^1].arg.argtype
  if fn_return_type != resolved_function_def.returns:
    let step_location = function.steps[^1].location
    return err(fmt"{step_location} expected function to return `{resolved_function_def.returns.asl}`")

  ok(new_resolved_function(function, resolved_function_def, resolved_steps))

proc resolve(file: ast.File, module: UserModule): Result[
    ResolvedModule, string] =
  if DEBUG:
    echo fmt"Resolving MODULE: {module.location}"
  var resolved_generics: seq[ResolvedGeneric]
  for generic in module.generics:
    let resolved_generic = ? resolve(file, module, generic)
    resolved_generics.add(resolved_generic)

  var resolved_structs: seq[ResolvedStruct]
  for struct in module.structs:
    let resolved_struct = ? resolve(file, module, struct)
    resolved_structs.add(resolved_struct)

  var resolved_functions: seq[ResolvedFunction]
  for function in module.functions:
    let resolved_function = ? resolve(file, module, function)
    resolved_functions.add(resolved_function)

  ok(new_resolved_module(module, resolved_generics, resolved_structs,
      resolved_functions))

proc resolve*(file: ast.File): Result[ResolvedFile, string] =
  var resolved_modules: seq[ResolvedModule]
  for module in file.user_modules:
    let resolved_module = ? resolve(file, module)
    resolved_modules.add(resolved_module)

  var resolved_functions: seq[ResolvedFunction]
  for function in file.functions:
    let resolved_function = ? resolve(file, function)
    resolved_functions.add(resolved_function)

  ok(new_resolved_file(file, resolved_modules, resolved_functions))
