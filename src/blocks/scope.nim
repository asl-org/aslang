import results, options, strformat, typetraits
import strutils, sequtils
import sets, tables, algorithm

import native
import module
import function
import matcher

import "../rules/parse_result"

proc make_native_module(spec: (string, seq[(string, string, string, seq[(
    string, string)])])): Result[Module, string] =
  let (name, fns) = spec
  let native_module = name.new_identifier().new_module_def(Location()).new_native_module()

  for (native_fn_name, returns, fn_name, args) in fns:
    var arg_defs: seq[ArgumentDefinition]
    for (module, name) in args:
      let arg_def = new_arg_def(new_identifier(module), new_identifier(name))
      arg_defs.add(arg_def)

    let fn_def = new_fn_def(new_identifier(fn_name), new_identifier(
        returns), arg_defs)

    ? native_module.add_fn(new_native_function(fn_def, native_fn_name))

  return ok(native_module)

type Scope* = ref object of RootObj
  modules: seq[Module]
  native_modules: seq[Module]

proc modules*(scope: Scope): seq[Module] = scope.modules
proc spaces*(scope: Scope): int = scope.spaces

proc `$`*(scope: Scope): string =
  $(scope.modules[0])

proc find_app(scope: Scope): Result[Module, string] =
  var apps: seq[Module]
  for module in scope.modules:
    if module.def.kind == MDK_APP:
      apps.add(module)

  if apps.len == 0:
    return err(fmt"Failed to find `app` module")

  if apps.len > 1:
    var message = @[fmt"The ASL Program must contain only one app module but found {apps.len} definitions"]
    for app in apps:
      message.add($(app.def.location))
    return err(message.join("\n"))

  return ok(apps[0])

proc find_user_module(scope: Scope, module_name: Identifier): Result[Module, string] =
  for module in scope.modules:
    if $(module.def.name) == $(module_name):
      return ok(module)

  return err(fmt"{module_name} is not defined in scope.")

proc find_native_module(scope: Scope, module_name: Identifier): Result[Module, string] =
  for module in scope.native_modules:
    if $(module.def.name) == $(module_name):
      return ok(module)

  return err(fmt"{module_name} is not defined in scope.")

proc find_module(scope: Scope, module_name: Identifier): Result[Module, string] =
  let maybe_native_module = scope.find_native_module(module_name)
  if maybe_native_module.is_ok: return maybe_native_module

  let maybe_user_module = scope.find_user_module(module_name)
  if maybe_user_module.is_ok: return maybe_user_module

  return err(fmt"{module_name.location} {module_name} is not defined in scope")

proc add_native_module*(scope: Scope, new_module: Module): Result[void, string] =
  let maybe_native_module = scope.find_native_module(new_module.def.name)
  if maybe_native_module.is_ok:
    return err(fmt"{new_module.def.location} {new_module.def.name} is already defined in the scope")

  scope.native_modules.add(new_module)
  ok()

proc add_user_module*(scope: Scope, new_module: Module): Result[void, string] =
  let maybe_user_module = scope.find_user_module(new_module.def.name)
  if maybe_user_module.is_ok:
    return err(fmt"{new_module.def.location} Module {new_module.def.name} is already defined in the scope")

  scope.modules.add(new_module)
  ok()

proc new_scope*(): Result[Scope, string] =
  var scope = Scope()
  for spec in native_module_spec:
    let native_mod = ? spec.make_native_module()
    ? scope.add_native_module(native_mod)
  ok(scope)

# TODO: perform final validation
proc close*(scope: Scope): Result[void, string] =
  discard ? scope.find_app()
  ok()

type FunctionScope* = ref object of RootObj
  mapping: Table[string, ArgumentDefinition] = initTable[string,
      ArgumentDefinition]()
  temp_variables: int = 0

proc temp_variable(fn_scope: FunctionScope): Identifier =
  let id = new_identifier(fmt"_asl_temp_var_{fn_scope.temp_variables}")
  fn_scope.temp_variables += 1
  return id

proc add_arg(fn_scope: FunctionScope, arg_def: ArgumentDefinition): Result[
    void, string] =
  let arg_name = $(arg_def.name)
  if arg_name in fn_scope.mapping:
    return err(fmt"{arg_name} already exists in the scope")

  fn_scope.mapping[arg_name] = arg_def
  return ok()

proc get_arg(fn_scope: FunctionScope, arg_name: Identifier): Result[
    ArgumentDefinition, string] =
  let arg_name_str = $(arg_name)
  if not (arg_name_str in fn_scope.mapping):
    return err(fmt"{arg_name.location} {arg_name} is not present in the scope")
  ok(fn_scope.mapping[arg_name_str])

proc clone(fn_scope: FunctionScope): Result[FunctionScope, string] =
  var new_fn_scope = FunctionScope(temp_variables: fn_scope.temp_variables)
  for arg_def in fn_scope.mapping.values:
    ? new_fn_scope.add_arg(arg_def.clone)
  return ok(new_fn_scope)

type ResolutionQueue = ref object of RootObj
  data: seq[(Module, Function)]
  index: HashSet[string]

proc new_resolution_queue(): ResolutionQueue =
  ResolutionQueue(data: @[], index: initHashSet[string]())

proc add(queue: ResolutionQueue, module: Module, function: Function): void =
  let mod_name = $(module.def.name)
  let fn_name = $(function.def.name)
  let hash = fmt"{mod_name}_{fn_name}"
  if hash in queue.index: return
  queue.data.add((module, function))
  queue.index.incl(hash)

proc len(q: ResolutionQueue): int = q.data.len
proc get(q: ResolutionQueue): (Module, Function) =
  let info = q.data[0]
  q.data.delete(0)
  return info

proc resolve_struct_literal(
  scope: Scope,
  fn_scope: FunctionScope,
  module: Module,
  literal: Literal,
  queue: ResolutionQueue
): Result[string, string] =
  case literal.kind:
  of LTK_STRUCT:
    # TODO: make sure initialization also adds a destruction call.
    var struct_init_fncall_args: seq[string]
    let expected_fields = ? module.resolve_struct_literal(literal.struct)
    for (field, kwarg) in zip(expected_fields, literal.struct.kwargs):
      case kwarg.value.kind:
      of KWAV_ATOM:
        let literal_module = ? scope.find_module(field.module)
        let nn_code = ? literal_module.resolve_native_numeric(kwarg.value.atom)
        struct_init_fncall_args.add(nn_code)
      of KWAV_IDENTIFIER:
        let arg = ? fn_scope.get_arg(kwarg.value.identifier)
        if $(arg.module) != $(field.module):
          return err(fmt"{kwarg.value.identifier.location} expected {field.module} but found {arg.module}")
        struct_init_fncall_args.add(fmt"{kwarg.value.identifier}")

    let init_fn = "init".new_identifier.new_fn_def(module.def.name,
        module.struct.get.field_defs).new_native_function(fmt"{module.def.name}_init")
    queue.add(module, init_fn)

    let struct_init_fncall_args_str = struct_init_fncall_args.join(", ")
    ok(fmt"{module.def.name}_init({struct_init_fncall_args_str})")
  of LTK_NATIVE_NUMERIC:
    err(fmt"User defined modules can not use native numerics for initialization")

proc resolve_union_literal(
  scope: Scope,
  fn_scope: FunctionScope,
  module: Module,
  union_name: Identifier,
  literal: Literal,
  queue: ResolutionQueue
): Result[string, string] =
  case literal.kind:
  of LTK_STRUCT:
    # TODO: make sure initialization also adds a destruction call.
    var struct_init_fncall_args: seq[string]
    let expected_fields = ? module.resolve_union_literal(union_name,
        literal.struct)
    for (field, kwarg) in zip(expected_fields, literal.struct.kwargs):
      case kwarg.value.kind:
      of KWAV_ATOM:
        let literal_module = ? scope.find_module(field.module)
        let nn_code = ? literal_module.resolve_native_numeric(kwarg.value.atom)
        struct_init_fncall_args.add(nn_code)
      of KWAV_IDENTIFIER:
        let arg = ? fn_scope.get_arg(kwarg.value.identifier)
        if $(arg.module) != $(field.module):
          return err(fmt"{kwarg.value.identifier.location} expected {field.module} but found {arg.module}")
        struct_init_fncall_args.add(fmt"{kwarg.value.identifier}")

    let union_fields = ( ? module.union.get.get_union_def(union_name)).fields
    let init_fn = (fmt"init_{union_name}").new_identifier.new_fn_def(
        module.def.name, union_fields).new_native_function(fmt"{module.def.name}_init")
    queue.add(module, init_fn)

    let struct_init_fncall_args_str = struct_init_fncall_args.join(", ")
    ok(fmt"{module.def.name}_init_{union_name}({struct_init_fncall_args_str})")
  of LTK_NATIVE_NUMERIC:
    err(fmt"User defined modules can not use native numerics for initialization")


proc resolve_literal(
  scope: Scope,
  fn_scope: FunctionScope,
  module: Module,
  literal: Literal,
  queue: ResolutionQueue,
): Result[string, string] =
  case module.kind:
  of MK_NATIVE:
    case literal.kind:
    of LTK_STRUCT: err(fmt"ASL native modules do not support structs")
    of LTK_NATIVE_NUMERIC: module.resolve_native_numeric(literal.integer)
  of MK_USER:
    case module.def.kind:
    of MDK_STRUCT: scope.resolve_struct_literal(fn_scope, module, literal, queue)
    else:
      # TODO: check for init function with matching keyword arg list
      err(fmt"Should be unreachable since union are not supported yet")

proc resolve_struct_getter(
  scope: Scope,
  fn_scope: FunctionScope,
  arg_def: ArgumentDefinition,
  struct_getter: StructGetter,
): Result[string, string] =
  let arg_in_scope = ? fn_scope.get_arg(struct_getter.target)
  let arg_module = ? scope.find_module(arg_in_scope.module)
  case arg_module.kind:
  of MK_NATIVE: err(fmt"Native modules can not be structs")
  of MK_USER:
    case arg_module.def.kind:
    of MDK_STRUCT:
      var found = false
      for field_def in arg_module.struct.get.field_defs:
        if $(field_def.name) != $(struct_getter.field): continue
        if $(field_def.module) != $(arg_def.module): continue
        found = true
        break

      if found: ok("{struct_getter.target}->{struct_getter.field}")
      else: err(fmt"{struct_getter} did not match the function signature")
    else: err(fmt"{arg_module.def} is not a struct")

proc resolve_fncall_arg(
  scope: Scope,
  fn_scope: FunctionScope,
  arg_def: ArgumentDefinition,
  arg: Argument,
  queue: ResolutionQueue,
): Result[void, string] =
  case arg.kind:
  of AK_IDENTIFIER:
    let arg_in_scope = ? fn_scope.get_arg(arg.name)
    if $(arg_in_scope.module) != $(arg_def.module):
      return err(fmt"Expected {arg.name} to be of type {arg_def.module} but found {arg_in_scope.module}")
  of AK_LITERAL:
    let expected_module = ? scope.find_module(arg_def.module)
    # TODO: resolving a struct literal here will be passed to fncall
    # by value which may cause un-necessary copies. Handle that.
    let maybe_resolved = scope.resolve_literal(fn_scope, expected_module,
        arg.literal, queue)
    if maybe_resolved.is_err:
      return err(fmt"Expected {arg.literal} to be of type {arg_def.module}")
  of AK_STRUCT_GETTER:
    let maybe_resolved = scope.resolve_struct_getter(fn_scope, arg_def,
        arg.struct_getter)
    if maybe_resolved.is_err:
      return err(fmt"Expected {arg.struct_getter} to be of type {arg_def.module}")
  ok()

proc resolve_fncall(
  scope: Scope,
  module: Module,
  fn_scope: FunctionScope,
  fncall: FunctionCall,
  queue: ResolutionQueue,
): Result[(Function, string), string] =
  for fn in module.fns:
    if $(fn.def.name) != $(fncall.fn_name): continue
    if fn.def.arg_def_list.len != fncall.arglist.len: continue

    var matched = true
    for (arg_def, arg) in zip(fn.def.arg_def_list, fncall.arglist):
      let maybe_resolved = scope.resolve_fncall_arg(fn_scope, arg_def, arg, queue)
      if maybe_resolved.is_err:
        matched = false
        break

    if matched:
      let args_str = fncall.arglist.map_it($(it)).join(", ")
      let fn_name =
        case fn.kind:
        of FK_NATIVE: fn.native_fn_name
        of FK_USER: fmt"{module.def.name}_{fn.def.name}"

      let c_code = fmt"{fn_name}({args_str})"
      return ok((fn, c_code))
  return err(fmt"{fncall.location} Failed to find matching function for {fncall}")

proc resolve_expression(
  scope: Scope,
  fn_scope: FunctionScope,
  expression: Expression,
  queue: ResolutionQueue
): Result[(Identifier, string), string] =
  case expression.kind:
  of EK_INIT:
    let init = expression.init
    if init.module_ref.refs.len == 1:
      let init_struct_module = ? scope.find_module(init.module_ref.refs[0])
      let literal_str = ? scope.resolve_literal(fn_scope, init_struct_module,
          init.literal, queue)

      return ok((init_struct_module.def.name, literal_str))
    elif init.module_ref.refs.len == 2:
      let init_union_module = ? scope.find_module(init.module_ref.refs[0])
      let literal_str = ? scope.resolve_union_literal(fn_scope,
          init_union_module, init.module_ref.refs[1], init.literal, queue)
      return ok((init_union_module.def.name, literal_str))
    else:
      return err(fmt"Should be unreachable since import based refs are not supported yet")
  of EK_FNCALL:
    let fncall = expression.fncall
    let fncall_module = ? scope.find_module(fncall.module_name)
    let (fncall_fn, fncall_code) = ? scope.resolve_fncall(fncall_module,
        fn_scope, fncall, queue)
    queue.add(fncall_module, fncall_fn)

    return ok((fncall_fn.def.returns, fncall_code))
  of EK_IDENTIFIER:
    let arg_in_scope = ? fn_scope.get_arg(expression.identifier)
    return ok((arg_in_scope.module, $(arg_in_scope.name)))

proc resolve_return_type(scope: Scope, module_name: Identifier): Result[string, string] =
  let module = ? scope.find_module(module_name)
  case module.kind:
  of MK_NATIVE: ok(fmt"{module_name}")
  of MK_USER:
    case module.def.kind:
    of MDK_STRUCT, MDK_UNION: ok(fmt"{module_name}*")
    else: ok(fmt"{module_name}")

proc resolve_statement(
  scope: Scope,
  fn_scope: FunctionScope,
  statement: Statement,
  queue: ResolutionQueue
): Result[(ArgumentDefinition, string), string] =
  case statement.kind:
  of SK_ASSIGNMENT:
    let (return_type, expr_code) = ? scope.resolve_expression(fn_scope,
        statement.assign.expression, queue)
    let return_arg_def = new_arg_def(return_type, statement.assign.dest)
    let return_type_code = ? scope.resolve_return_type(return_type)
    var statement_code = fmt"{return_type_code} {statement.assign.dest} = {expr_code};"
    ok((return_arg_def, statement_code))
  of SK_EXPR:
    let (return_type, expr_code) = ? scope.resolve_expression(fn_scope,
        statement.expression, queue)
    let return_arg_def = new_arg_def(return_type, fn_scope.temp_variable)
    let return_type_code = ? scope.resolve_return_type(return_type)
    var statement_code = fmt"{return_type_code} {return_arg_def.name} = {expr_code};"
    ok((return_arg_def, statement_code))

proc resolve_case_block(
  scope: Scope,
  fn_scope: FunctionScope,
  module: Module,
  case_block: Case,
  match_arg: ArgumentDefinition,
  target_arg: Identifier,
  queue: ResolutionQueue
): Result[(ArgumentDefinition, string), string] =
  var case_scope = ? fn_scope.clone()
  # TODO: case macros do yet support pattern matching via
  # structs they only support native numeric. Ensure that
  # it does not occurs unintentionally.
  var case_value: string
  var case_block_code: seq[string]
  case case_block.value.kind:
  of CPK_ATOM:
    case_value = ? module.resolve_native_numeric(case_block.value.atom)
    case_block_code.add(fmt"case {case_value}: " & "{")
  else:
    let module_ref = case_block.value.module_ref
    let arg_def_list = case_block.value.arg_def_list
    if module_ref.refs.len != 2:
      return err(fmt"Struct pattern matching is not yet implemented")
    let union_module = ? scope.find_module(module_ref.refs[0])
    case union_module.kind:
    of MK_NATIVE: return err(fmt"{union_module.def.name} is a native module, expected pattern to be a number")
    of MK_USER: discard

    case union_module.def.kind:
    of MDK_UNION: discard
    else: return err(fmt"expected module {union_module.def.name} to be a union, but found {union_module.def.kind}")

    let union_def_index = ? union_module.union.get.get_union_def_index(
        module_ref.refs[1])

    case_block_code.add(fmt"case {union_def_index}: " & "{")
    for arg_def in arg_def_list:
      let union_def_field = ? union_module.union.get.get_union_def_field(
          module_ref.refs[1], arg_def.name)
      let new_arg = new_arg_def(union_def_field.module, arg_def.module)
      ? case_scope.add_arg(new_arg)
      # echo fmt"{new_arg} = {match_arg.name}->data.{module_ref.refs[1]}.{arg_def.name};"
      case_block_code.add(fmt"{new_arg} = {match_arg.name}->data.{module_ref.refs[1]}.{arg_def.name};")

  for index, statement in case_block.statements:
    let (return_arg_def, statement_code) = ? scope.resolve_statement(case_scope,
        statement, queue)
    ? case_scope.add_arg(return_arg_def)
    case_block_code.add(statement_code)

    if index == case_block.statements.len - 1:
      case_block_code.add(fmt"{target_arg} = {return_arg_def.name};")
      case_block_code.add("break;")
      case_block_code.add("}")
      let case_block_code_str = case_block_code.join("\n")
      return ok((return_arg_def, case_block_code_str))
  return err(fmt"Case block must have at least one statement")

proc resolve_else_block(
  scope: Scope,
  fn_scope: FunctionScope,
  else_block: Else,
  target_arg: Identifier,
  queue: ResolutionQueue
): Result[(ArgumentDefinition, string), string] =
  var else_scope = ? fn_scope.clone()
  var else_block_code = @["default: {"]
  for index, statement in else_block.statements:
    let (return_arg_def, statement_code) = ? scope.resolve_statement(else_scope,
        statement, queue)
    ? else_scope.add_arg(return_arg_def)
    else_block_code.add(statement_code)

    if index == else_block.statements.len - 1:
      else_block_code.add(fmt"{target_arg} = {return_arg_def.name};")
      else_block_code.add("break;")
      else_block_code.add("}")
      let else_block_code_str = else_block_code.join("\n")
      return ok((return_arg_def, else_block_code_str))
  return err(fmt"Else block must have at least one statement")

proc resolve_match_block(
  scope: Scope,
  fn_scope: FunctionScope,
  match_block: Match,
  queue: ResolutionQueue
): Result[(ArgumentDefinition, string), string] =
  let match_arg = ? fn_scope.get_arg(match_block.value)
  let match_arg_module = ? scope.find_module(match_arg.module)
  var match_block_code: seq[string]

  case match_arg_module.def.kind:
  of MDK_UNION:
    match_block_code.add(fmt"switch({match_arg.name}->id) " & "{")
  else:
    match_block_code.add(fmt"switch({match_arg.name}) " & "{")

  let match_block_result_var = fn_scope.temp_variable()
  var block_return_module: seq[Identifier]

  if match_block.cases.len == 0:
    return err(fmt"A match block must have at least one case block")

  for case_block in match_block.cases:
    let (return_arg_def, case_code) = ? scope.resolve_case_block(fn_scope,
        match_arg_module, case_block, match_arg, match_block_result_var, queue)
    block_return_module.add(return_arg_def.module)
    match_block_code.add(case_code)

  if match_block.else_blocks.len > 1:
    return err(fmt"A match block can have at max one else block that too at last")

  for else_block in match_block.else_blocks:
    let (return_arg_def, else_code) = ? scope.resolve_else_block(fn_scope,
        else_block, match_block_result_var, queue)
    block_return_module.add(return_arg_def.module)
    match_block_code.add(else_code)

  for index, return_module in block_return_module:
    if $(block_return_module[0]) != $(return_module):
      return err(fmt"All blocks must return value of same module")

  let return_arg_def = new_arg_def(block_return_module[0], match_block_result_var)
  match_block_code.add("}")
  # IMPORTANT
  # insert the `match_block_result_var` since we don't know up until now about the
  # data type that will be returned from the switch case statement
  let return_type_code = ? scope.resolve_return_type(block_return_module[0])
  match_block_code.insert(fmt"{return_type_code} {match_block_result_var};", 0)
  return ok((return_arg_def, match_block_code.join("\n")))

proc resolve_step(scope: Scope, fn_scope: FunctionScope, step: FunctionStep,
    queue: ResolutionQueue): Result[(ArgumentDefinition, string), string] =
  case step.kind:
  of FSK_STATEMENT:
    scope.resolve_statement(fn_scope, step.statement, queue)
  of FSK_MATCHER:
    scope.resolve_match_block(fn_scope, step.matcher, queue)

proc resolve_union_definition*(scope: Scope, module: Module): Result[string, string] =
  case module.kind:
  of MK_USER: discard
  else: return err(fmt"{module} must be a user module")

  case module.def.kind:
  of MDK_UNION: discard
  else: return err(fmt"{module} must be a union")

  var union_kind_def_code: seq[string]
  for union_def in module.union.get.union_defs:
    var fields_code: seq[string]
    for field in union_def.fields:
      let field_module = ? scope.find_module(field.module)
      let field_def_code =
        case field_module.kind:
        of MK_USER: fmt"{field.module}* {field.name};"
        of MK_NATIVE: fmt"{field.module} {field.name};"
      fields_code.add(field_def_code)

    union_kind_def_code.add(@[
      "struct {",
      fields_code.join("\n"),
      "}" & $(union_def.name) & ";",
    ].join("\n"))


  let union_def_code = @[
    "typedef struct {",
    "U64 id;",
    "union {",
    union_kind_def_code.join("\n"),
    "} data;",
    "}" & fmt"{module.def.name};",
  ].join("\n")
  ok(union_def_code)

proc resolve_union_init*(scope: Scope, module: Module): Result[(string, string), string] =
  case module.kind:
  of MK_USER: discard
  else: return err(fmt"{module} must be a user module")

  case module.def.kind:
  of MDK_UNION: discard
  else: return err(fmt"{module} must be a union")
  # Hacky stuff here, need to fix this but prioritizing simplicity for now.
  # TODO: make sure the allocated memory is free when the function returns
  let init_temp_ptr_arg = "_asl_temp_ptr"
  let init_temp_value_arg = "_asl_temp_value"
  let init_fn_name = "init"
  var union_init_def_code: seq[string]
  var union_init_impl_code: seq[string]

  for (index, union_def) in module.union.get.union_defs.pairs:
    let union_name = union_def.name
    let module_name = module.def.name
    let fn_name = fmt"{module_name}_{init_fn_name}_{union_name}";

    var arg_def_list: seq[string]
    for arg_def in union_def.fields:
      let arg_def_module = ? scope.find_module(arg_def.module)
      let arg_def_code =
        case arg_def_module.kind:
        of MK_USER: fmt"{arg_def.module}* {arg_def.name}"
        of MK_NATIVE: fmt"{arg_def.module} {arg_def.name}"
      arg_def_list.add(arg_def_code)

    let arg_def_list_code = arg_def_list.join(", ")
    let init_def_code = fmt"{module_name}* {fn_name}({arg_def_list_code});"
    union_init_def_code.add(init_def_code)

    let arg_copy_list = union_def.fields.map_it(
        fmt"{init_temp_value_arg}->data.{union_name}.{it.name} = {it.name};").join("\n")
    let init_impl_code = @[
      fmt"{module_name}* {fn_name}({arg_def_list_code})" & "{",
      fmt"Pointer {init_temp_ptr_arg} = System_allocate(sizeof({module_name}));",
      fmt"{module_name}* {init_temp_value_arg} = ({module_name}*){init_temp_ptr_arg};",
      fmt"{init_temp_value_arg}->id = {index};",
      arg_copy_list,
      fmt"return {init_temp_value_arg};",
      "}"
    ].join("\n")
    union_init_impl_code.add(init_impl_code)

  return ok((union_init_def_code.join("\n"), union_init_impl_code.join("\n")))

proc resolve_app(scope: Scope, app_module: Module,
    start_fn: Function): Result[string, string] =
  var queue = new_resolution_queue()
  queue.add(app_module, start_fn)
  var resolved_structs: HashSet[string]
  var resolved_unions: HashSet[string]
  var resolved_structs_init: HashSet[string]
  var resolved_unions_init: HashSet[string]

  var app_impl_code: seq[string]
  var app_fn_def_code: seq[string]
  var app_struct_def_code: seq[string]
  # perform function dependent bfs
  while queue.len > 0:
    let (module, fn) = queue.get()

    # skip native module resolution
    case module.kind:
    of MK_NATIVE: continue
    of MK_USER: discard

    case module.def.kind:
    of MDK_STRUCT:
      if not resolved_structs.contains($(module.def.name)):
        let maybe_struct_def_code = module.resolve_struct_definition()
        if maybe_struct_def_code.is_ok:
          app_struct_def_code.add(maybe_struct_def_code.get)
          resolved_structs.incl($(module.def.name))

      if not resolved_structs_init.contains($(module.def.name)):
        let maybe_native_init = module.resolve_struct_init()
        if maybe_native_init.is_ok:
          let (init_def_code, init_impl_code) = maybe_native_init.get
          app_fn_def_code.add(init_def_code)
          app_impl_code.add(init_impl_code)
          resolved_structs_init.incl($(module.def.name))
    of MDK_UNION:
      if not resolved_unions.contains($(module.def.name)):
        let maybe_union_def_code = scope.resolve_union_definition(module)
        if maybe_union_def_code.is_ok:
          app_struct_def_code.add(maybe_union_def_code.get)
          resolved_unions.incl($(module.def.name))

      if not resolved_unions_init.contains($(module.def.name)):
        let maybe_native_init = scope.resolve_union_init(module)
        if maybe_native_init.is_ok:
          let (init_def_code, init_impl_code) = maybe_native_init.get
          app_fn_def_code.add(init_def_code)
          app_impl_code.add(init_impl_code)
          resolved_unions_init.incl($(module.def.name))
    else: discard

    # resolve auto generated init functions for struct
    # since they are marked as native at the time of resolution
    case fn.kind:
    of FK_USER: discard
    of FK_NATIVE: continue

    # only user functions will reach here
    var fn_scope = FunctionScope()
    var return_code = ? scope.resolve_return_type(fn.def.returns)

    var arg_def_code: seq[string]
    for arg in fn.def.arg_def_list:
      let arg_type_code = ? scope.resolve_return_type(arg.module)
      ? fn_scope.add_arg(arg)
      arg_def_code.add(fmt"{arg_type_code} {arg.name}")

    let args_def_code_str = arg_def_code.join(", ")
    app_fn_def_code.add(fmt"{return_code} {module.def.name}_{fn.def.name}({args_def_code_str});")
    var fn_code = @[fmt"{return_code} {module.def.name}_{fn.def.name}({args_def_code_str})" & "{"]

    for index, step in fn.steps:
      let (return_arg_def, step_code) = ? scope.resolve_step(fn_scope, step, queue)
      ? fn_scope.add_arg(return_arg_def)
      fn_code.add(step_code)

      # add return statement after resolving last function step.
      if index == fn.steps.len - 1:
        if $(return_arg_def.module) != $(fn.def.returns):
          return err(fmt"Expected {step.statement} to return {fn.def.returns} but found {return_arg_def.module}")
        else:
          fn_code.add(fmt"return {return_arg_def.name};")

    fn_code.add("}")
    app_impl_code.add(fn_code.join("\n"))

  let app_code = @[
      app_struct_def_code.join("\n"),
      app_fn_def_code.join("\n"),
      app_impl_code.reversed.join("\n")
    ].join("\n")
  ok(app_code)

proc resolve(scope: Scope): Result[(Module, string), string] =
  let app = ? scope.find_app()
  let start = ? app.find_start()
  let app_code = ? scope.resolve_app(app, start)
  ok((app, app_code))

proc generate_app*(scope: Scope): Result[string, string] =
  let (app, app_code) = ? scope.resolve()
  let code = @[
    """#include "runtime/asl.h"""",
    app_code,
    "int main(int argc, char** argv) {",
    fmt"return {app.def.name}_start((U8)argc);",
    "}"
  ]

  ok(code.join("\n"))
