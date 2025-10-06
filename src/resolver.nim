import results, tables, strformat

import ast

type
  ResolvedArgumentTypeKind = enum
    RATK_SIMPLE, RATK_NESTED
  ResolvedArgumentType = ref object of RootObj
    argtype: ArgumentType
    module: Module
    case kind: ResolvedArgumentTypeKind
    of RATK_SIMPLE: discard
    of RATK_NESTED: children: seq[ResolvedArgumentType]

proc new_resolved_argument_type(argtype: ArgumentType, module: Module,
    children: seq[ResolvedArgumentType]): ResolvedArgumentType =
  if children.len == 0:
    ResolvedArgumentType(kind: RATK_SIMPLE, argtype: argtype, module: module)
  else:
    ResolvedArgumentType(kind: RATK_NESTED, argtype: argtype, module: module,
        children: children)

type ResolvedArgumentDefinition = ref object of RootObj
  name: Identifier
  resolved_type: ResolvedArgumentType

proc new_resolved_argument_definition(name: Identifier,
    resolved_type: ResolvedArgumentType): ResolvedArgumentDefinition =
  ResolvedArgumentDefinition(name: name, resolved_type: resolved_type)

type ResolvedFunctionCall = ref object of RootObj
  fncall: FunctionCall

type ResolvedInitializer = ref object of RootObj
  init: Initializer

type ResolvedStructGet = ref object of RootObj
  struct_get: StructGet
  resolved_type: ResolvedArgumentType

proc new_resolved_struct_get(struct_get: StructGet,
    resolved_type: ResolvedArgumentType): ResolvedStructGet =
  ResolvedStructGet(struct_get: struct_get, resolved_type: resolved_type)

type
  ResolvedExpressionKind = enum
    REK_FNCALL, REK_INIT, REK_STRUCT_GET, REK_VARIABLE
  ResolvedExpression = ref object of RootObj
    expression: Expression
    case kind: ResolvedExpressionKind
    of REK_FNCALL: fncall: ResolvedFunctioncall
    of REK_INIT: init: ResolvedInitializer
    of REK_STRUCT_GET: struct_get: ResolvedStructGet
    of REK_VARIABLE: variable: ResolvedArgumentDefinition

proc new_resolved_expression(expression: Expression,
    fncall: ResolvedFunctionCall): ResolvedExpression =
  ResolvedExpression(kind: REK_FNCALL, expression: expression, fncall: fncall)

proc new_resolved_expression(expression: Expression,
    init: ResolvedInitializer): ResolvedExpression =
  ResolvedExpression(kind: REK_INIT, expression: expression, init: init)

proc new_resolved_expression(expression: Expression,
    struct_get: ResolvedStructGet): ResolvedExpression =
  ResolvedExpression(kind: REK_STRUCT_GET, expression: expression,
      struct_get: struct_get)

proc new_resolved_expression(expression: Expression,
    variable: ResolvedArgumentDefinition): ResolvedExpression =
  ResolvedExpression(kind: REK_VARIABLE, expression: expression,
      variable: variable)

type ResolvedStatement = ref object of RootObj
  statement: Statement
  resolved_arg: ResolvedArgumentDefinition
  resolved_expr: ResolvedExpression

proc new_resolved_statement(statement: Statement,
    resolved_arg: ResolvedArgumentDefinition,
        resolved_expr: ResolvedExpression): ResolvedStatement =
  ResolvedStatement(statement: statement, resolved_arg: resolved_arg,
      resolved_expr: resolved_expr)

type ResolvedMatch = ref object of RootObj
  match: Match
  resolved_arg: ResolvedArgumentDefinition

type
  ResolvedFunctionStepKind = enum
    RFSK_STATEMENT, RFSK_MATCH
  ResolvedFunctionStep = ref object of RootObj
    step: FunctionStep
    case kind: ResolvedFunctionStepKind
    of RFSK_STATEMENT: statement: ResolvedStatement
    of RFSK_MATCH: match: ResolvedMatch

proc new_resolved_function_step(step: FunctionStep,
    statement: ResolvedStatement): ResolvedFunctionStep =
  ResolvedFunctionStep(kind: RFSK_STATEMENT, step: step, statement: statement)

proc new_resolved_function_step(step: FunctionStep,
    match: ResolvedMatch): ResolvedFunctionStep =
  ResolvedFunctionStep(kind: RFSK_MATCH, step: step, match: match)

type ResolvedFunctionDefinition = ref object of RootObj
  def: FunctionDefinition
  resolved_args: seq[ResolvedArgumentDefinition]
  resolved_return_type: ResolvedArgumentType

proc new_resolved_function_definition(def: FunctionDefinition,
    resolved_args: seq[ResolvedArgumentDefinition],
    resolved_return_type: ResolvedArgumentType): ResolvedFunctionDefinition =
  ResolvedFunctionDefinition(def: def, resolved_args: resolved_args,
      resolved_return_type: resolved_return_type)

type ResolvedFunction = ref object of RootObj
  function: Function
  resolved_def: ResolvedFunctionDefinition
  resolved_steps: seq[ResolvedFunctionStep]

proc new_resolved_function(function: Function, def: ResolvedFunctionDefinition,
    steps: seq[ResolvedFunctionStep]): ResolvedFunction =
  ResolvedFunction(function: function, resolved_def: def, resolved_steps: steps)

type ResolvedGeneric = ref object of RootObj
  generic: Generic
  resolved_defs: seq[ResolvedFunctionDefinition]

type ResolvedStruct = ref object of RootObj
  struct: Struct
  resolved_fields: seq[ResolvedArgumentDefinition]

type ResolvedModule = ref object of RootObj
  module: UserModule
  resolved_generics: seq[ResolvedGeneric]
  resolved_structs: seq[ResolvedStruct]
  resolved_functions: seq[ResolvedFunction]

type ResolvedFile = ref object of RootObj
  file: ast.File
  resolved_modules: seq[ResolvedModule]
  resolved_functions: seq[ResolvedFunction]

proc resolve(file: ast.File, module: UserModule, argtype: ArgumentType): Result[
    ResolvedArgumentType, string] =
  let argmodule = ? file.find_module(argtype.module)
  var children: seq[ResolvedArgumentType]
  for child in argtype.children:
    let resolved_child = ? resolve(file, module, child)
    children.add(resolved_child)
  ok(new_resolved_argument_type(argtype, argmodule, children))

proc resolve(file: ast.File, module: UserModule,
    field: ArgumentDefinition): Result[ResolvedArgumentDefinition, string] =
  let resolved_type = ? resolve(file, module, field.argtype)
  ok(new_resolved_argument_definition(field.name, resolved_type))

proc resolve(file: ast.File, module: UserModule, generic: Generic,
    def: FunctionDefinition): Result[ResolvedFunctionDefinition, string] =
  err("todo: implement module function definition resolution")

proc resolve(file: ast.File, def: FunctionDefinition): Result[
    ResolvedFunctionDefinition, string] =
  err("todo: implement function definition resolution")

proc resolve(file: ast.File, module: UserModule, generic: Generic): Result[
    ResolvedGeneric, string] =
  var resolved_defs: seq[ResolvedFunctionDefinition]
  for def in generic.defs:
    let resolved_def = ? resolve(file, module, generic, def)
    resolved_defs.add(resolved_def)
  ok(ResolvedGeneric(generic: generic, resolved_defs: resolved_defs))

proc resolve(file: ast.File, module: UserModule, struct: Struct): Result[
    ResolvedStruct, string] =
  var resolved_fields: seq[ResolvedArgumentDefinition]
  for field in struct.fields:
    let resolved_field = ? resolve(file, module, field)
    resolved_fields.add(resolved_field)
  ok(ResolvedStruct(struct: struct, resolved_fields: resolved_fields))

proc resolve(file: ast.File, module: UserModule,
    def: FunctionDefinition): Result[ResolvedFunctionDefinition, string] =
  var resolved_args: seq[ResolvedArgumentDefinition]
  for arg in def.args:
    let resolved_arg = ? resolve(file, module, arg)
    resolved_args.add(resolved_arg)
  let resolved_return_type = ? resolve(file, module, def.returns)
  ok(new_resolved_function_definition(def, resolved_args, resolved_return_type))

proc resolve(file: ast.File, module: UserModule, scope: Table[Identifier,
    ResolvedArgumentType], fncall: FunctionCall): Result[ResolvedFunctionCall, string] =
  echo fncall.asl
  err("todo: implement module function call resolution")

proc resolve(file: ast.File, module: UserModule, scope: Table[Identifier,
    ResolvedArgumentType], init: Initializer): Result[ResolvedInitializer, string] =
  err("todo: implement module initializer resolution")

proc resolve(file: ast.File, module: UserModule, scope: Table[Identifier,
    ResolvedArgumentType], struct_get: StructGet): Result[ResolvedStructGet, string] =
  if struct_get.name in scope:
    let arg_module = scope[struct_get.name].module
    let field_type = ? arg_module.find_field(struct_get.field)
    let resolved_type = ? resolve(file, module, field_type)
    ok(new_resolved_struct_get(struct_get, resolved_type))
  else:
    err(fmt"{struct_get.location} struct `{struct_get.name.asl}` is not defined in scope")

proc resolve(file: ast.File, module: UserModule, scope: Table[Identifier,
    ResolvedArgumentType],

variable: Identifier): Result[ResolvedArgumentDefinition, string] =
  err("todo: implement module variable assignment resolution")

proc resolve(file: ast.File, module: UserModule, scope: Table[Identifier,
    ResolvedArgumentType], expression: Expression): Result[ResolvedExpression, string] =
  let maybe_fncall = expression.fncall
  if maybe_fncall.is_ok:
    let resolved_fncall = ? resolve(file, module, scope, maybe_fncall.get)
    return ok(new_resolved_expression(expression, resolved_fncall))

  let maybe_init = expression.init
  if maybe_init.is_ok:
    let resolved_init = ? resolve(file, module, scope, maybe_init.get)
    return ok(new_resolved_expression(expression, resolved_init))

  let maybe_struct_get = expression.struct_get
  if maybe_struct_get.is_ok:
    let resolved_struct_get = ? resolve(file, module, scope,
        maybe_struct_get.get)
    return ok(new_resolved_expression(expression, resolved_struct_get))

  let maybe_variable = expression.variable
  if maybe_variable.is_ok:
    let resolved_variable = ? resolve(file, module, scope, maybe_variable.get)
    return ok(new_resolved_expression(expression, resolved_variable))

  err(fmt"{expression.location} [UNREACHABLE] expected one of the vaild expression like function call/initializer/struct getter/variable assignment")

proc resolve(file: ast.File, module: UserModule, scope: Table[Identifier,
    ResolvedArgumentType], statement: Statement): Result[ResolvedStatement, string] =
  let resolved_expr = ? resolve(file, module, scope, statement.expression)
  var resolved_arg: ResolvedArgumentDefinition
  ok(new_resolved_statement(statement, resolved_arg, resolved_expr))

proc resolve(file: ast.File, module: UserModule, scope: Table[Identifier,
    ResolvedArgumentType], match: Match): Result[ResolvedMatch, string] =
  err("todo: implement module function match resolution")

proc resolve(file: ast.File, module: UserModule, scope: Table[Identifier,
    ResolvedArgumentType], step: FunctionStep): Result[ResolvedFunctionStep, string] =
  let maybe_statement = step.statement
  if maybe_statement.is_ok:
    let resolved_statement = ? resolve(file, module, scope, maybe_statement.get)
    return ok(new_resolved_function_step(step, resolved_statement))

  let maybe_match = step.match
  if maybe_match.is_ok:
    let resolved_match = ? resolve(file, module, scope, maybe_match.get)
    return ok(new_resolved_function_step(step, resolved_match))

  err(fmt"{step.location} [UNREACHABLE] expected the function step to be a statement or match expression")

proc resolve(file: ast.File, function: Function,
    step: FunctionStep): Result[ResolvedFunctionStep, string] =
  err("todo: implement function step resolution")

proc resolve(file: ast.File, module: UserModule, function: Function): Result[
    ResolvedFunction, string] =
  let resolved_def = ? resolve(file, module, function.def)
  var scope: Table[Identifier, ResolvedArgumentType]
  for arg in resolved_def.resolved_args:
    scope[arg.name] = arg.resolved_type

  var resolved_steps: seq[ResolvedFunctionStep]
  for step in function.steps:
    let resolved_step = ? resolve(file, module, scope, step)
    resolved_steps.add(resolved_step)

  ok(new_resolved_function(function, resolved_def, resolved_steps))

proc resolve(file: ast.File, function: Function): Result[ResolvedFunction, string] =
  let resolved_def = ? resolve(file, function.def)

  var resolved_steps: seq[ResolvedFunctionStep]
  for step in function.steps:
    let resolved_step = ? resolve(file, function, step)
    resolved_steps.add(resolved_step)

  ok(new_resolved_function(function, resolved_def, resolved_steps))

proc resolve(file: ast.File, module: UserModule): Result[ResolvedModule, string] =
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

  ok(ResolvedModule(module: module, resolved_generics: resolved_generics,
      resolved_structs: resolved_structs,
      resolved_functions: resolved_functions))

proc resolve*(file: ast.File): Result[ResolvedFile, string] =
  var resolved_modules: seq[ResolvedModule]
  for module in file.user_modules:
    let resolved_module = ? resolve(file, module)
    resolved_modules.add(resolved_module)

  var resolved_functions: seq[ResolvedFunction]
  for function in file.functions:
    let resolved_function = ? resolve(file, function)
    resolved_functions.add(resolved_function)

  ok(ResolvedFile(file: file, resolved_modules: resolved_modules,
      resolved_functions: resolved_functions))
