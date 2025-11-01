import results, strformat, tables, strutils, sets, algorithm, options, sequtils, options

import deps_analyzer/parser
export parser

# NOTE: Cycle detection algo
proc detect_cycle[T](graph: Table[T, HashSet[T]], node: T,
    visited: var OrderedSet[T], ancestors: var OrderedSet[T]): Result[
    OrderedSet[T], OrderedSet[T]] =
  if node in ancestors: return err(ancestors)
  if node in visited: return ok(visited)
  visited.incl(node)
  ancestors.incl(node)
  for child in graph[node]:
    # NOTE: Graph may have self cycles since a module can
    # depend on itself for recursive dependencies. Other
    # than that no circular dependencies are allowed.
    if child == node: continue
    visited = ? detect_cycle(graph, child, visited, ancestors)
  ancestors.excl(node)
  ok(visited)

# NOTE: weird api
# "ok" returns topologicaly sorted nodes basically module resolution order
# "error" returns the cycle in order of nodes as they come up.
proc detect_cycle[T](graph: Table[T, HashSet[T]]): Result[seq[T], seq[T]] =
  var visited: OrderedSet[T]
  for node in graph.keys:
    if node notin visited:
      var ancestors: OrderedSet[T]
      let maybe_dag = detect_cycle(graph, node, visited, ancestors)
      if maybe_dag.is_err: return err(maybe_dag.error.to_seq)
      visited = maybe_dag.get
  ok(visited.to_seq.reversed)

type
  TypedModuleRefKind = enum
    TMRK_NATIVE, TMRK_USER, TMRK_GENERIC
  TypedModuleRef = ref object of RootObj
    location: Location
    case kind: TypedModuleRefKind
    of TMRK_NATIVE:
      native_module: NativeModule
    of TMRK_USER:
      user_module: UserModule
      children: seq[TypedModuleRef]
    of TMRK_GENERIC:
      module: UserModule
      generic: Generic

proc new_typed_module_ref(native_module: NativeModule,
    location: Location): TypedModuleRef =
  TypedModuleRef(kind: TMRK_NATIVE, native_module: native_module,
      location: location)

proc new_typed_module_ref(user_module: UserModule,
    location: Location): TypedModuleRef =
  TypedModuleRef(kind: TMRK_USER, user_module: user_module, location: location)

proc new_typed_module_ref(user_module: UserModule, children: seq[
    TypedModuleRef], location: Location): TypedModuleRef =
  TypedModuleRef(kind: TMRK_USER, user_module: user_module, children: children,
      location: location)

proc new_typed_module_ref(module: UserModule,
    generic: Generic, location: Location): TypedModuleRef =
  TypedModuleRef(kind: TMRK_GENERIC, module: module, generic: generic,
      location: location)

proc module_deps(module_ref: TypedModuleRef): HashSet[UserModule] =
  var module_set: HashSet[UserModule]
  case module_ref.kind:
  of TMRK_NATIVE: discard
  of TMRK_GENERIC: module_set.incl(module_ref.module)
  of TMRK_USER:
    module_set.incl(module_ref.user_module)
    for child in module_ref.children:
      module_set.incl(child.module_deps)
  module_set

# proc native_module(module_ref: TypedModuleRef): Result[NativeModule, string] =
#   case module_ref.kind:
#   of TMRK_NATIVE: ok(module_ref.native)
#   else: err(fmt"{module_ref.location} expected a native module")

# proc user_module(module_ref: TypedModuleRef): Result[UserModule, string] =
#   case module_ref.kind:
#   of TMRK_USER: ok(module_ref.user)
#   of TMRK_GENERIC: ok(module_ref.module)
#   of TMRK_NESTED: ok(module_ref.container)
#   else: err(fmt"{module_ref.location} expected a user module")

# proc generic(module_ref: TypedModuleRef): Result[Generic, string] =
#   case module_ref.kind:
#   of TMRK_GENERIC: ok(module_ref.generic)
#   else: err(fmt"{module_ref.location} expected a generic")

type TypedArgumentDefinition = ref object of RootObj
  name: Identifier
  module_ref: TypedModuleRef

proc new_typed_argument_definition(module_ref: TypedModuleRef,
    name: Identifier): TypedArgumentDefinition =
  TypedArgumentDefinition(module_ref: module_ref, name: name)

# proc location(arg: TypedArgumentDefinition): Location =
#   arg.module_ref.location

proc module_deps(arg: TypedArgumentDefinition): HashSet[UserModule] =
  arg.module_ref.module_deps

type TypedFunctionDefinition = ref object of RootObj
  name: Identifier
  args: seq[TypedArgumentDefinition]
  returns: TypedModuleRef
  location: Location

proc new_typed_function_definition(name: Identifier, args: seq[
    TypedArgumentDefinition], returns: TypedModuleRef,
    location: Location): TypedFunctionDefinition =
  TypedFunctionDefinition(name: name, args: args, returns: returns,
      location: location)

proc module_deps(def: TypedFunctionDefinition): HashSet[UserModule] =
  var module_set: HashSet[UserModule]
  for arg in def.args:
    module_set.incl(arg.module_deps)
  module_set.incl(def.returns.module_deps)
  module_set

type TypedGeneric = ref object of RootObj
  name: Identifier
  defs: seq[TypedFunctionDefinition]
  location: Location

proc new_typed_generic(name: Identifier, defs: seq[TypedFunctionDefinition],
    location: Location): TypedGeneric =
  TypedGeneric(name: name, defs: defs, location: location)

proc module_deps(generic: TypedGeneric): HashSet[UserModule] =
  var module_set: HashSet[UserModule]
  for def in generic.defs:
    module_set.incl(def.module_deps)
  module_set

type
  TypedStructKind = enum
    TSK_DEFAULT, TSK_NAMED
  TypedStruct = ref object of RootObj
    fields: seq[TypedArgumentDefinition]
    location: Location
    case kind: TypedStructKind
    of TSK_DEFAULT: discard
    of TSK_NAMED: name: Identifier

proc new_typed_struct(fields: seq[TypedArgumentDefinition],
    location: Location): TypedStruct =
  TypedStruct(kind: TSK_DEFAULT, fields: fields, location: location)

proc new_typed_struct(name: Identifier, fields: seq[TypedArgumentDefinition],
    location: Location): TypedStruct =
  TypedStruct(kind: TSK_NAMED, name: name, fields: fields, location: location)

proc module_deps(struct: TypedStruct): HashSet[UserModule] =
  var module_set: HashSet[UserModule]
  for field in struct.fields:
    module_set.incl(field.module_deps)
  module_set

type TypedLiteralInit = ref object of RootObj
  module_ref: TypedModuleRef
  literal: Literal

proc new_typed_literal_init(module_ref: TypedModuleRef,
    literal: Literal): TypedLiteralInit =
  TypedLiteralInit(module_ref: module_ref, literal: literal)

# proc location(init: TypedLiteralInit): Location =
#   init.module_ref.location

proc module_deps(init: TypedLiteralInit): HashSet[UserModule] =
  init.module_ref.module_deps

type
  TypedStructInitKind = enum
    TSIK_DEFAULT, TSIK_NAMED
  TypedStructInit = ref object of RootObj
    module_ref: TypedModuleRef
    args: seq[KeywordArgument]
    case kind: TypedStructInitKind
    of TSIK_DEFAULT: discard
    of TSIK_NAMED: name: Identifier

proc new_typed_struct_init(module_ref: TypedModuleRef,
    args: seq[KeywordArgument]): TypedStructInit =
  TypedStructInit(kind: TSIK_DEFAULT, module_ref: module_ref, args: args)

proc new_typed_struct_init(name: Identifier, module_ref: TypedModuleRef,
    args: seq[KeywordArgument]): TypedStructInit =
  TypedStructInit(kind: TSIK_NAMED, name: name, module_ref: module_ref, args: args)

# proc location(init: TypedStructInit): Location =
#   init.module_ref.location

proc module_deps(init: TypedStructInit): HashSet[UserModule] =
  init.module_ref.module_deps

type
  TypedInitializerKind = enum
    TIK_LITERAL, TIK_STRUCT
  TypedInitializer = ref object of RootObj
    case kind: TypedInitializerKind
    of TIK_LITERAL: literal: TypedLiteralInit
    of TIK_STRUCT: struct: TypedStructInit

proc new_typed_initializer(literal: TypedLiteralInit): TypedInitializer =
  TypedInitializer(kind: TIK_LITERAL, literal: literal)

proc new_typed_initializer(struct: TypedStructInit): TypedInitializer =
  TypedInitializer(kind: TIK_STRUCT, struct: struct)

# proc location(init: TypedInitializer): Location =
#   case init.kind:
#   of TIK_LITERAL: init.literal.location
#   of TIK_STRUCT: init.struct.location

proc module_deps(init: TypedInitializer): HashSet[UserModule] =
  case init.kind:
  of TIK_LITERAL: init.literal.module_deps
  of TIK_STRUCT: init.struct.module_deps

type
  TypedFunctionCallKind = enum
    TFCK_MODULE, TFCK_LOCAL
  TypedFunctionCall = ref object of RootObj
    name: Identifier
    args: seq[Argument]
    case kind: TypedFunctionCallKind
    of TFCK_LOCAL: discard
    of TFCK_MODULE: module_ref: TypedModuleRef

proc new_typed_function_call(name: Identifier, args: seq[
    Argument]): TypedFunctionCall =
  TypedFunctionCall(kind: TFCK_LOCAL, name: name, args: args)

proc new_typed_function_call(module_ref: TypedModuleRef, name: Identifier,
    args: seq[Argument]): TypedFunctionCall =
  TypedFunctionCall(kind: TFCK_MODULE, module_ref: module_ref, name: name, args: args)

# proc location(fncall: TypedFunctionCall): Location =
#   case fncall.kind:
#   of TFCK_LOCAL: fncall.name.location
#   of TFCK_MODULE: fncall.module_ref.location

proc module_deps(fncall: TypedFunctionCall): HashSet[UserModule] =
  case fncall.kind:
  of TFCK_LOCAL: init_hashset[UserModule]()
  of TFCK_MODULE: fncall.module_ref.module_deps

type TypedStructGet = ref object of RootObj
  variable: Identifier
  field: Identifier

proc new_typed_struct_get(variable: Identifier,
    field: Identifier): TypedStructGet =
  TypedStructGet(variable: variable, field: field)

# proc location(struct_get: TypedStructGet): Location =
#   struct_get.variable.location

proc module_deps(struct_get: TypedStructGet): HashSet[UserModule] =
  init_hashset[UserModule]()

type TypedVariable = ref object of RootObj
  name: Identifier

proc new_typed_variable(name: Identifier): TypedVariable =
  TypedVariable(name: name)

proc location(variable: TypedVariable): Location = variable.location
proc module_deps(variable: TypedVariable): HashSet[UserModule] = init_hashset[
    UserModule]()

type
  TypedExpressionKind = enum
    TEK_FNCALL, TEK_INIT, TEK_STRUCT_GET, TEK_VARIABLE
  TypedExpression = ref object of RootObj
    case kind: TypedExpressionKind
    of TEK_FNCALL: fncall: TypedFunctionCall
    of TEK_INIT: init: TypedInitializer
    of TEK_STRUCT_GET: struct_get: TypedStructGet
    of TEK_VARIABLE: variable: TypedVariable

proc new_typed_expression(fncall: TypedFunctionCall): TypedExpression =
  TypedExpression(kind: TEK_FNCALL, fncall: fncall)

proc new_typed_expression(init: TypedInitializer): TypedExpression =
  TypedExpression(kind: TEK_INIT, init: init)

proc new_typed_expression(struct_get: TypedStructGet): TypedExpression =
  TypedExpression(kind: TEK_STRUCT_GET, struct_get: struct_get)

proc new_typed_expression(variable: TypedVariable): TypedExpression =
  TypedExpression(kind: TEK_VARIABLE, variable: variable)

# proc location(expression: TypedExpression): Location =
#   case expression.kind:
#   of TEK_FNCALL: expression.fncall.location
#   of TEK_INIT: expression.init.location
#   of TEK_STRUCT_GET: expression.struct_get.location
#   of TEK_VARIABLE: expression.variable.location

proc module_deps(expression: TypedExpression): HashSet[UserModule] =
  case expression.kind:
  of TEK_FNCALL: expression.fncall.module_deps
  of TEK_INIT: expression.init.module_deps
  of TEK_STRUCT_GET: expression.struct_get.module_deps
  of TEK_VARIABLE: expression.variable.module_deps

type TypedStatement = ref object of RootObj
  arg: Identifier
  expression: TypedExpression

proc new_typed_statement(arg: Identifier,
    expression: TypedExpression): TypedStatement =
  TypedStatement(arg: arg, expression: expression)

# proc location(statement: TypedStatement): Location =
#   statement.arg.location

proc module_deps(statement: TypedStatement): HashSet[UserModule] =
  statement.expression.module_deps

type TypedCase = ref object of RootObj
  pattern: CasePattern
  location: Location
  statements: seq[TypedStatement]

proc new_typed_case(pattern: CasePattern, statements: seq[TypedStatement],
    location: Location): TypedCase =
  TypedCase(pattern: pattern, statements: statements, location: location)

# proc location(case_block: TypedCase): Location =
#   case_block.location

proc module_deps(case_block: TypedCase): HashSet[UserModule] =
  var module_set: HashSet[UserModule]
  for statement in case_block.statements:
    module_set.incl(statement.module_deps)
  module_set

type TypedElse = ref object of RootObj
  location: Location
  statements: seq[TypedStatement]

proc new_typed_else(statements: seq[TypedStatement],
    location: Location): TypedElse =
  TypedElse(statements: statements, location: location)

# proc location(else_block: TypedElse): Location = else_block.location

proc module_deps(else_block: TypedElse): HashSet[UserModule] =
  var module_set: HashSet[UserModule]
  for statement in else_block.statements:
    module_set.incl(statement.module_deps)
  module_set


type
  TypedMatchKind = enum
    TMK_CASE_ONLY, TMK_COMPLETE
  TypedMatch = ref object of RootObj
    operand: Identifier
    arg: Identifier
    case_blocks: seq[TypedCase]
    case kind: TypedMatchKind
    of TMK_CASE_ONLY: discard
    of TMK_COMPLETE: else_block: TypedElse

proc new_typed_match(operand: Identifier, arg: Identifier, case_blocks: seq[
    TypedCase]): TypedMatch =
  TypedMatch(kind: TMK_CASE_ONLY, operand: operand, arg: arg,
      case_blocks: case_blocks)

proc new_typed_match(operand: Identifier, arg: Identifier, case_blocks: seq[
    TypedCase], else_block: TypedElse): TypedMatch =
  TypedMatch(kind: TMK_COMPLETE, operand: operand, arg: arg,
      case_blocks: case_blocks, else_block: else_block)

# proc location(match: TypedMatch): Location =
#   match.arg.location

proc module_deps(match: TypedMatch): HashSet[UserModule] =
  var module_set: HashSet[UserModule]
  for case_block in match.case_blocks:
    module_set.incl(case_block.module_deps)
  case match.kind:
  of TMK_CASE_ONLY: discard
  of TMK_COMPLETE: module_set.incl(match.else_block.module_deps)
  module_set

type
  TypedFunctionStepKind = enum
    TFSK_STATEMENT, TFSK_MATCH
  TypedFunctionStep = ref object of RootObj
    case kind: TypedFunctionStepKind
    of TFSK_STATEMENT: statement: TypedStatement
    of TFSK_MATCH: match: TypedMatch

proc new_typed_function_step(statement: TypedStatement): TypedFunctionStep =
  TypedFunctionStep(kind: TFSK_STATEMENT, statement: statement)

proc new_typed_function_step(match: TypedMatch): TypedFunctionStep =
  TypedFunctionStep(kind: TFSK_MATCH, match: match)

# proc location(step: TypedFunctionStep): Location =
#   case step.kind:
#   of TFSK_STATEMENT: step.statement.location
#   of TFSK_MATCH: step.match.location

proc module_deps(step: TypedFunctionStep): HashSet[UserModule] =
  case step.kind:
  of TFSK_STATEMENT: step.statement.module_deps
  of TFSK_MATCH: step.match.module_deps

type TypedFunction = ref object of RootObj
  def: TypedFunctionDefinition
  steps: seq[TypedFunctionStep]

proc new_typed_function(def: TypedFunctionDefinition, steps: seq[
    TypedFunctionStep]): TypedFunction =
  TypedFunction(def: def, steps: steps)

# proc location(function: TypedFunction): Location =
#   function.def.location

proc module_deps(function: TypedFunction): HashSet[UserModule] =
  var module_set: HashSet[UserModule]
  module_set.incl(function.def.module_deps)
  for step in function.steps:
    module_set.incl(step.module_deps)
  module_set

type TypedModule = ref object of RootObj
  name: Identifier
  location: Location
  generics: seq[TypedGeneric]
  structs: seq[TypedStruct]
  functions: seq[TypedFunction]

proc new_typed_module(name: Identifier, generics: seq[TypedGeneric],
    structs: seq[TypedStruct], functions: seq[TypedFunction],
    location: Location): TypedModule =
  TypedModule(name: name, location: location, generics: generics,
      structs: structs, functions: functions)

# proc location(module: TypedModule): Location =
#   module.location

proc module_deps(module: TypedModule): HashSet[UserModule] =
  var module_set: HashSet[UserModule]
  for generic in module.generics:
    module_set.incl(generic.module_deps)
  for struct in module.structs:
    module_set.incl(struct.module_deps)
  for function in module.functions:
    module_set.incl(function.module_deps)
  module_set

type TypedFile* = ref object of RootObj
  name: string
  modules: seq[TypedModule]
  functions: seq[TypedFunction]

proc new_typed_file(name: string, modules: seq[TypedModule], functions: seq[
    TypedFunction]): TypedFile =
  TypedFile(name: name, modules: modules, functions: functions)

proc assign_type(file: ast.File, optional_module: Option[UserModule],
    module_name: Identifier): Result[TypedModuleRef, string] =
  # NOTE: For handling generics that are only defined in a module
  if optional_module.is_some:
    let module = optional_module.get
    let maybe_arg_generic = module.find_generic(module_name)
    if maybe_arg_generic.is_ok:
      return ok(new_typed_module_ref(module, maybe_arg_generic.get,
          module_name.location))

  let arg_module = ? file.find_module(module_name)
  case arg_module.kind:
  of MK_NATIVE:
    let native_module = ? arg_module.native_module
    ok(new_typed_module_ref(native_module, module_name.location))
  of MK_USER:
    let user_module = ? arg_module.user_module
    ok(new_typed_module_ref(user_module, module_name.location))

proc assign_type(file: ast.File, optional_module: Option[UserModule],
    module_ref: ModuleRef): Result[TypedModuleRef, string] =
  case module_ref.kind:
  of MRK_SIMPLE: assign_type(file, optional_module, module_ref.module)
  of MRK_NESTED:
    let arg_module = ? file.find_module(module_ref.module)
    let user_module = ? arg_module.user_module
    var typed_children: seq[TypedModuleRef]
    for child in module_ref.children:
      let typed_child = ? assign_type(file, optional_module, child)
      typed_children.add(typed_child)
    ok(new_typed_module_ref(user_module, typed_children, module_ref.location))

proc assign_type(file: ast.File, module: UserModule,
    module_ref: ModuleRef): Result[TypedModuleRef, string] =
  assign_type(file, some(module), module_ref)

proc assign_type(file: ast.File, module_ref: ModuleRef): Result[TypedModuleRef, string] =
  assign_type(file, none(UserModule), module_ref)

proc assign_type(file: ast.File, module: UserModule, generic: Generic,
    arg: ArgumentDefinition): Result[TypedArgumentDefinition, string] =
  let typed_arg = ? assign_type(file, module, arg.module_ref)
  ok(new_typed_argument_definition(typed_arg, arg.name))

proc assign_type(file: ast.File, module: UserModule,
    arg: ArgumentDefinition): Result[TypedArgumentDefinition, string] =
  let typed_arg = ? assign_type(file, module, arg.module_ref)
  ok(new_typed_argument_definition(typed_arg, arg.name))

proc assign_type(file: ast.File, arg: ArgumentDefinition): Result[
    TypedArgumentDefinition, string] =
  let typed_arg = ? assign_type(file, arg.module_ref)
  ok(new_typed_argument_definition(typed_arg, arg.name))

proc assign_type(file: ast.File, module: UserModule, generic: Generic,
    def: FunctionDefinition): Result[TypedFunctionDefinition, string] =
  var typed_args: seq[TypedArgumentDefinition]
  for arg in def.args:
    let typed_arg = ? assign_type(file, module, generic, arg)
    typed_args.add(typed_arg)
  let typed_return = ? assign_type(file, module, def.returns)
  ok(new_typed_function_definition(def.name, typed_args, typed_return, def.location))

proc assign_type(file: ast.File, module: UserModule,
    def: FunctionDefinition): Result[TypedFunctionDefinition, string] =
  var typed_args: seq[TypedArgumentDefinition]
  for arg in def.args:
    let typed_arg = ? assign_type(file, module, arg)
    typed_args.add(typed_arg)
  let typed_return = ? assign_type(file, module, def.returns)
  ok(new_typed_function_definition(def.name, typed_args, typed_return, def.location))

proc assign_type(file: ast.File, def: FunctionDefinition): Result[
    TypedFunctionDefinition, string] =
  var typed_args: seq[TypedArgumentDefinition]
  for arg in def.args:
    let typed_arg = ? assign_type(file, arg)
    typed_args.add(typed_arg)
  let typed_return = ? assign_type(file, def.returns)
  ok(new_typed_function_definition(def.name, typed_args, typed_return, def.location))

proc assign_type(file: ast.File, module: UserModule,
    init: LiteralInit): Result[TypedLiteralInit, string] =
  let module_ref = ? assign_type(file, module, init.module)
  ok(new_typed_literal_init(module_ref, init.literal))

proc assign_type(file: ast.File, init: LiteralInit): Result[
    TypedLiteralInit, string] =
  let module_ref = ? assign_type(file, init.module)
  ok(new_typed_literal_init(module_ref, init.literal))

proc assign_type(file: ast.File, module: UserModule,
    init: StructInit): Result[TypedStructInit, string] =
  let module_ref = ? assign_type(file, module, init.struct_ref.module)
  case init.struct_ref.kind:
  of SRK_DEFAULT:
    ok(new_typed_struct_init(module_ref, init.args))
  of SRK_NAMED:
    let name = ? init.struct_ref.struct
    ok(new_typed_struct_init(name, module_ref, init.args))

proc assign_type(file: ast.File, init: StructInit): Result[
    TypedStructInit, string] =
  let module_ref = ? assign_type(file, init.struct_ref.module)
  case init.struct_ref.kind:
  of SRK_DEFAULT:
    ok(new_typed_struct_init(module_ref, init.args))
  of SRK_NAMED:
    let name = ? init.struct_ref.struct
    ok(new_typed_struct_init(name, module_ref, init.args))

proc assign_type(file: ast.File, module: UserModule,
    init: Initializer): Result[TypedInitializer, string] =
  case init.kind:
  of IK_LITERAL:
    let literal_init = ? init.literal
    let typed_literal_init = ? assign_type(file, module, literal_init)
    ok(new_typed_initializer(typed_literal_init))
  of IK_STRUCT:
    let struct_init = ? init.struct
    let typed_struct_init = ? assign_type(file, module, struct_init)
    ok(new_typed_initializer(typed_struct_init))

proc assign_type(file: ast.File, init: Initializer): Result[
    TypedInitializer, string] =
  case init.kind:
  of IK_LITERAL:
    let literal_init = ? init.literal
    let typed_literal_init = ? assign_type(file, literal_init)
    ok(new_typed_initializer(typed_literal_init))
  of IK_STRUCT:
    let struct_init = ? init.struct
    let typed_struct_init = ? assign_type(file, struct_init)
    ok(new_typed_initializer(typed_struct_init))

proc assign_type(file: ast.File, module: UserModule,
    fncall: FunctionCall): Result[TypedFunctionCall, string] =
  case fncall.fnref.kind:
  of FRK_LOCAL:
    ok(new_typed_function_call(fncall.name, fncall.args))
  of FRK_MODULE:
    let module_ref = ? assign_type(file, module, ? fncall.fnref.module)
    ok(new_typed_function_call(module_ref, fncall.name, fncall.args))

proc assign_type(file: ast.File, fncall: FunctionCall): Result[
    TypedFunctionCall, string] =
  case fncall.fnref.kind:
  of FRK_LOCAL:
    ok(new_typed_function_call(fncall.name, fncall.args))
  of FRK_MODULE:
    let module_ref = ? assign_type(file, ? fncall.fnref.module)
    ok(new_typed_function_call(module_ref, fncall.name, fncall.args))

proc assign_type(file: ast.File, module: UserModule,
    expression: Expression): Result[TypedExpression, string] =
  case expression.kind:
  of EK_FNCALL:
    let fncall = ? expression.fncall
    let typed_fncall = ? assign_type(file, module, fncall)
    ok(new_typed_expression(typed_fncall))
  of EK_INIT:
    let init = ? expression.init
    let typed_init = ? assign_type(file, module, init)
    ok(new_typed_expression(typed_init))
  of EK_STRUCT_GET:
    let struct_get = ? expression.struct_get
    let typed_struct_get = new_typed_struct_get(struct_get.name,
        struct_get.field)
    ok(new_typed_expression(typed_struct_get))
  of EK_VARIABLE:
    let variable = ? expression.variable
    let typed_variable = new_typed_variable(variable)
    ok(new_typed_expression(typed_variable))

proc assign_type(file: ast.File, expression: Expression): Result[
    TypedExpression, string] =
  case expression.kind:
  of EK_FNCALL:
    let fncall = ? expression.fncall
    let typed_fncall = ? assign_type(file, fncall)
    ok(new_typed_expression(typed_fncall))
  of EK_INIT:
    let init = ? expression.init
    let typed_init = ? assign_type(file, init)
    ok(new_typed_expression(typed_init))
  of EK_STRUCT_GET:
    let struct_get = ? expression.struct_get
    let typed_struct_get = new_typed_struct_get(struct_get.name,
        struct_get.field)
    ok(new_typed_expression(typed_struct_get))
  of EK_VARIABLE:
    let variable = ? expression.variable
    let typed_variable = new_typed_variable(variable)
    ok(new_typed_expression(typed_variable))

proc assign_type(file: ast.File, module: UserModule,
    statement: Statement): Result[TypedStatement, string] =
  let typed_expression = ? assign_type(file, module, statement.expression)
  ok(new_typed_statement(statement.arg, typed_expression))

proc assign_type(file: ast.File, statement: Statement): Result[
    TypedStatement, string] =
  let typed_expression = ? assign_type(file, statement.expression)
  ok(new_typed_statement(statement.arg, typed_expression))

proc assign_type(file: ast.File, module: UserModule,
    case_block: Case): Result[TypedCase, string] =
  var typed_statements: seq[TypedStatement]
  for statement in case_block.statements:
    let typed_statement = ? assign_type(file, module, statement)
    typed_statements.add(typed_statement)
  ok(new_typed_case(case_block.def.pattern, typed_statements,
      case_block.def.location))

proc assign_type(file: ast.File, case_block: Case): Result[
    TypedCase, string] =
  var typed_statements: seq[TypedStatement]
  for statement in case_block.statements:
    let typed_statement = ? assign_type(file, statement)
    typed_statements.add(typed_statement)
  ok(new_typed_case(case_block.def.pattern, typed_statements,
      case_block.def.location))

proc assign_type(file: ast.File, module: UserModule,
    else_block: Else): Result[TypedElse, string] =
  var typed_statements: seq[TypedStatement]
  for statement in else_block.statements:
    let typed_statement = ? assign_type(file, module, statement)
    typed_statements.add(typed_statement)
  ok(new_typed_else(typed_statements, else_block.location))

proc assign_type(file: ast.File, else_block: Else): Result[
    TypedElse, string] =
  var typed_statements: seq[TypedStatement]
  for statement in else_block.statements:
    let typed_statement = ? assign_type(file, statement)
    typed_statements.add(typed_statement)
  ok(new_typed_else(typed_statements, else_block.location))

proc assign_type(file: ast.File, module: UserModule, match: Match): Result[
    TypedMatch, string] =
  var typed_cases: seq[TypedCase]
  for case_block in match.case_blocks:
    let typed_case = ? assign_type(file, module, case_block)
    typed_cases.add(typed_case)

  case match.kind:
  of MK_CASE_ONLY:
    ok(new_typed_match(match.def.operand, match.def.arg, typed_cases))
  of MK_COMPLETE:
    let else_block = ? match.else_block
    let typed_else = ? assign_type(file, module, else_block)
    ok(new_typed_match(match.def.operand, match.def.arg, typed_cases, typed_else))

proc assign_type(file: ast.File, match: Match): Result[
    TypedMatch, string] =
  var typed_cases: seq[TypedCase]
  for case_block in match.case_blocks:
    let typed_case = ? assign_type(file, case_block)
    typed_cases.add(typed_case)

  case match.kind:
  of MK_CASE_ONLY:
    ok(new_typed_match(match.def.operand, match.def.arg, typed_cases))
  of MK_COMPLETE:
    let else_block = ? match.else_block
    let typed_else = ? assign_type(file, else_block)
    ok(new_typed_match(match.def.operand, match.def.arg, typed_cases, typed_else))

proc assign_type(file: ast.File, module: UserModule,
    step: FunctionStep): Result[TypedFunctionStep, string] =
  case step.kind:
  of FSK_STATEMENT:
    let statement = ? step.statement
    let typed_statement = ? assign_type(file, module, statement)
    ok(new_typed_function_step(typed_statement))
  of FSK_MATCH:
    let match = ? step.match
    let typed_match = ? assign_type(file, module, match)
    ok(new_typed_function_step(typed_match))

proc assign_type(file: ast.File, step: FunctionStep): Result[
    TypedFunctionStep, string] =
  case step.kind:
  of FSK_STATEMENT:
    let statement = ? step.statement
    let typed_statement = ? assign_type(file, statement)
    ok(new_typed_function_step(typed_statement))
  of FSK_MATCH:
    let match = ? step.match
    let typed_match = ? assign_type(file, match)
    ok(new_typed_function_step(typed_match))

proc assign_type(file: ast.File, module: UserModule,
    function: Function): Result[TypedFunction, string] =
  let typed_def = ? assign_type(file, module, function.def)
  var typed_steps: seq[TypedFunctionStep]
  for step in function.steps:
    let typed_step = ? assign_type(file, module, step)
    typed_steps.add(typed_step)
  ok(new_typed_function(typed_def, typed_steps))

proc assign_type(file: ast.File, function: Function): Result[
    TypedFunction, string] =
  let typed_def = ? assign_type(file, function.def)
  var typed_steps: seq[TypedFunctionStep]
  for step in function.steps:
    let typed_step = ? assign_type(file, step)
    typed_steps.add(typed_step)
  ok(new_typed_function(typed_def, typed_steps))

proc assign_type(file: ast.File, module: UserModule,
    generic: Generic): Result[TypedGeneric, string] =
  var typed_defs: seq[TypedFunctionDefinition]
  for def in generic.defs:
    let typed_def = ? assign_type(file, module, generic, def)
    typed_defs.add(typed_def)
  ok(new_typed_generic(generic.name, typed_defs, generic.location))

proc assign_type(file: ast.File, module: UserModule, struct: Struct): Result[
    TypedStruct, string] =
  var module_set: HashSet[UserModule]
  var typed_fields: seq[TypedArgumentDefinition]
  for field in struct.fields:
    let typed_field = ? assign_type(file, module, field)
    typed_fields.add(typed_field)
    module_set.incl(typed_field.module_deps)
  case struct.def.kind:
  of SDK_DEFAULT:
    ok(new_typed_struct(typed_fields, struct.location))
  of SDK_NAMED:
    let struct_name = ? struct.name
    ok(new_typed_struct(struct_name, typed_fields, struct.location))

proc assign_type(file: ast.File, module: UserModule): Result[TypedModule, string] =
  var typed_generics: seq[TypedGeneric]
  for generic in module.generics:
    let typed_generic = ? assign_type(file, module, generic)
    typed_generics.add(typed_generic)

  var typed_structs: seq[TypedStruct]
  for struct in module.structs:
    let typed_struct = ? assign_type(file, module, struct)
    typed_structs.add(typed_struct)

  var typed_functions: seq[TypedFunction]
  for function in module.functions:
    let typed_function = ? assign_type(file, module, function)
    typed_functions.add(typed_function)
  ok(new_typed_module(module.name, typed_generics, typed_structs,
      typed_functions, module.location))

proc assign_type*(file: ast.File): Result[TypedFile, string] =
  var module_graph: Table[UserModule, HashSet[UserModule]]
  var module_to_typed_module_map: Table[UserModule, TypedModule]
  for module in file.user_modules:
    let typed_module = ? assign_type(file, module)
    module_graph[module] = typed_module.module_deps
    module_to_typed_module_map[module] = typed_module

  # NOTE: Cycle detection and Topologically sort based on module dependencies.
  let maybe_module_order = detect_cycle(module_graph)
  if maybe_module_order.is_err:
    let cycle = maybe_module_order.get
    var message = @["CYCLIC DEPENDENCIES ENCOUNTERED"]
    for module in cycle:
      message.add(fmt"{module.location} {module.name.asl}")
    return err(message.join("\n"))

  let module_resolution_order = maybe_module_order.get
  var typed_modules: seq[TypedModule]
  for module in module_resolution_order:
    typed_modules.add(module_to_typed_module_map[module])

  var typed_functions: seq[TypedFunction]
  for function in file.functions:
    let typed_function = ? assign_type(file, function)
    typed_functions.add(typed_function)

  ok(new_typed_file(file.path, typed_modules, typed_functions))
