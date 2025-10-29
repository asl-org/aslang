import results, strformat, tables, strutils, sets, algorithm, options, sequtils

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
  TypedArgumentTypeKind = enum
    TATK_NATIVE, TATK_USER, TATK_GENERIC, TATK_NESTED
  TypedArgumentType = ref object of RootObj
    location: Location
    case kind: TypedArgumentTypeKind
    of TATK_NATIVE: native: NativeModule
    of TATK_USER: user: UserModule
    of TATK_GENERIC:
      module: UserModule
      generic: Generic
    of TATK_NESTED:
      container: UserModule
      children: seq[TypedArgumentType]

proc new_typed_argument_type(native: NativeModule,
    location: Location): TypedArgumentType =
  TypedArgumentType(kind: TATK_NATIVE, native: native, location: location)

proc new_typed_argument_type(user: UserModule,
    location: Location): TypedArgumentType =
  TypedArgumentType(kind: TATK_USER, user: user, location: location)

proc new_typed_argument_type(module: UserModule,
    generic: Generic, location: Location): TypedArgumentType =
  TypedArgumentType(kind: TATK_GENERIC, module: module, generic: generic,
      location: location)

proc new_typed_argument_type(container: UserModule, children: seq[
    TypedArgumentType], location: Location): TypedArgumentType =
  TypedArgumentType(kind: TATK_NESTED, container: container, children: children,
      location: location)

proc module_deps(argtype: TypedArgumentType): HashSet[UserModule] =
  var module_set: HashSet[UserModule]
  case argtype.kind:
  of TATK_NATIVE: discard
  of TATK_GENERIC: module_set.incl(argtype.module)
  of TATK_USER: module_set.incl(argtype.user)
  of TATK_NESTED:
    module_set.incl(argtype.container)
    for child in argtype.children:
      module_set.incl(child.module_deps)
  module_set

# proc native_module(argtype: TypedArgumentType): Result[NativeModule, string] =
#   case argtype.kind:
#   of TATK_NATIVE: ok(argtype.native)
#   else: err(fmt"{argtype.location} expected a native module")

# proc user_module(argtype: TypedArgumentType): Result[UserModule, string] =
#   case argtype.kind:
#   of TATK_USER: ok(argtype.user)
#   of TATK_GENERIC: ok(argtype.module)
#   of TATK_NESTED: ok(argtype.container)
#   else: err(fmt"{argtype.location} expected a user module")

# proc generic(argtype: TypedArgumentType): Result[Generic, string] =
#   case argtype.kind:
#   of TATK_GENERIC: ok(argtype.generic)
#   else: err(fmt"{argtype.location} expected a generic")

type TypedArgumentDefinition = ref object of RootObj
  name: Identifier
  argtype: TypedArgumentType

proc new_typed_argument_definition(argtype: TypedArgumentType,
    name: Identifier): TypedArgumentDefinition =
  TypedArgumentDefinition(argtype: argtype, name: name)

# proc location(arg: TypedArgumentDefinition): Location =
#   arg.argtype.location

proc module_deps(arg: TypedArgumentDefinition): HashSet[UserModule] =
  arg.argtype.module_deps

type TypedFunctionDefinition = ref object of RootObj
  name: Identifier
  args: seq[TypedArgumentDefinition]
  returns: TypedArgumentType
  location: Location

proc new_typed_function_definition(name: Identifier, args: seq[
    TypedArgumentDefinition], returns: TypedArgumentType,
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
  argtype: TypedArgumentType
  literal: Literal

proc new_typed_literal_init(argtype: TypedArgumentType,
    literal: Literal): TypedLiteralInit =
  TypedLiteralInit(argtype: argtype, literal: literal)

# proc location(init: TypedLiteralInit): Location =
#   init.argtype.location

proc module_deps(init: TypedLiteralInit): HashSet[UserModule] =
  init.argtype.module_deps

type
  TypedStructInitKind = enum
    TSIK_DEFAULT, TSIK_NAMED
  TypedStructInit = ref object of RootObj
    argtype: TypedArgumentType
    args: seq[KeywordArgument]
    case kind: TypedStructInitKind
    of TSIK_DEFAULT: discard
    of TSIK_NAMED: name: Identifier

proc new_typed_struct_init(argtype: TypedArgumentType,
    args: seq[KeywordArgument]): TypedStructInit =
  TypedStructInit(kind: TSIK_DEFAULT, argtype: argtype, args: args)

proc new_typed_struct_init(name: Identifier, argtype: TypedArgumentType,
    args: seq[KeywordArgument]): TypedStructInit =
  TypedStructInit(kind: TSIK_NAMED, name: name, argtype: argtype, args: args)

# proc location(init: TypedStructInit): Location =
#   init.argtype.location

proc module_deps(init: TypedStructInit): HashSet[UserModule] =
  init.argtype.module_deps

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
    of TFCK_MODULE: argtype: TypedArgumentType

proc new_typed_function_call(name: Identifier, args: seq[
    Argument]): TypedFunctionCall =
  TypedFunctionCall(kind: TFCK_LOCAL, name: name, args: args)

proc new_typed_function_call(argtype: TypedArgumentType, name: Identifier,
    args: seq[Argument]): TypedFunctionCall =
  TypedFunctionCall(kind: TFCK_MODULE, argtype: argtype, name: name, args: args)

# proc location(fncall: TypedFunctionCall): Location =
#   case fncall.kind:
#   of TFCK_LOCAL: fncall.name.location
#   of TFCK_MODULE: fncall.argtype.location

proc module_deps(fncall: TypedFunctionCall): HashSet[UserModule] =
  case fncall.kind:
  of TFCK_LOCAL: init_hashset[UserModule]()
  of TFCK_MODULE: fncall.argtype.module_deps

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
  def: CaseDefinition
  statements: seq[TypedStatement]

proc new_typed_case(def: CaseDefinition, statements: seq[
    TypedStatement]): TypedCase =
  TypedCase(def: def, statements: statements)

# proc location(case_block: TypedCase): Location =
#   case_block.def.location

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
    def: MatchDefinition
    case_blocks: seq[TypedCase]
    case kind: TypedMatchKind
    of TMK_CASE_ONLY: discard
    of TMK_COMPLETE: else_block: TypedElse

proc new_typed_match(def: MatchDefinition, case_blocks: seq[
    TypedCase]): TypedMatch =
  TypedMatch(kind: TMK_CASE_ONLY, def: def, case_blocks: case_blocks)

proc new_typed_match(def: MatchDefinition, case_blocks: seq[TypedCase],
    else_block: TypedElse): TypedMatch =
  TypedMatch(kind: TMK_COMPLETE, def: def, case_blocks: case_blocks,
      else_block: else_block)

# proc location(match: TypedMatch): Location =
#   match.def.location

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
  def: UserModuleDefinition
  generics: seq[TypedGeneric]
  structs: seq[TypedStruct]
  functions: seq[TypedFunction]

proc new_typed_module(def: UserModuleDefinition, generics: seq[TypedGeneric],
    structs: seq[TypedStruct], functions: seq[TypedFunction]): TypedModule =
  TypedModule(def: def, generics: generics, structs: structs,
      functions: functions)

# proc location(module: TypedModule): Location =
#   module.def.location

proc module_deps(module: TypedModule): HashSet[UserModule] =
  var module_set: HashSet[UserModule]
  for generic in module.generics:
    module_set.incl(generic.module_deps)
  for struct in module.structs:
    module_set.incl(struct.module_deps)
  for function in module.functions:
    module_set.incl(function.module_deps)
  module_set

type TypedFile = ref object of RootObj
  name: string
  modules: seq[TypedModule]
  functions: seq[TypedFunction]

proc new_typed_file(name: string, modules: seq[TypedModule], functions: seq[
    TypedFunction]): TypedFile =
  TypedFile(name: name, modules: modules, functions: functions)

proc populate_types(file: ast.File, module: UserModule, generic: Generic,
    argtype: ArgumentType): Result[TypedArgumentType, string] =
  case argtype.kind:
  of ATK_SIMPLE:
    let maybe_arg_module = file.find_module(argtype.module)
    if maybe_arg_module.is_ok:
      let arg_module = maybe_arg_module.get
      if arg_module.generics.len != 0:
        return err(fmt"{argtype.location} module `{arg_module.name.asl}` expects {arg_module.generics.len} generic types but found 0")
      case arg_module.kind:
      of MK_NATIVE:
        let native_module = ? arg_module.native_module
        ok(new_typed_argument_type(native_module, argtype.location))
      of MK_USER:
        let user_module = ? arg_module.user_module
        if user_module == module:
          return err(fmt"{argtype.location} module `{module.name.asl}` can not be passed as an argument to generic constraint")
        ok(new_typed_argument_type(user_module, argtype.location))
    else:
      let arg_generic = ? module.find_generic(argtype.module)
      if arg_generic != generic:
        return err(fmt"{argtype.location} expected `{generic.name.asl}` but found `{argtype.module.asl}`")
      ok(new_typed_argument_type(module, arg_generic, argtype.location))
  of ATK_NESTED:
    let arg_module = ? file.find_module(argtype.module)
    let user_module = ? arg_module.user_module
    if user_module.generics.len != argtype.children.len:
      return err(fmt"{argtype.location} module `{user_module.name.asl}` expects {user_module.generics.len} generic types but found {argtype.children.len}")
    if user_module == module:
      return err(fmt"{argtype.location} module `{module.name.asl}` can not be passed as an argument to generic constraint")

    var typed_children: seq[TypedArgumentType]
    for child in argtype.children:
      let typed_child = ? populate_types(file, module, generic, child)
      typed_children.add(typed_child)
    ok(new_typed_argument_type(user_module, typed_children, argtype.location))

proc populate_types(file: ast.File, module: UserModule,
    argtype: ArgumentType): Result[TypedArgumentType, string] =
  case argtype.kind:
  of ATK_SIMPLE:
    let maybe_arg_module = file.find_module(argtype.module)
    if maybe_arg_module.is_ok:
      let arg_module = maybe_arg_module.get
      if arg_module.generics.len != 0:
        return err(fmt"{argtype.location} module `{arg_module.name.asl}` expects {arg_module.generics.len} generic types but found 0")
      case arg_module.kind:
      of MK_NATIVE:
        let native_module = ? arg_module.native_module
        ok(new_typed_argument_type(native_module, argtype.location))
      of MK_USER:
        let user_module = ? arg_module.user_module
        ok(new_typed_argument_type(user_module, argtype.location))
    else:
      let arg_generic = ? module.find_generic(argtype.module)
      ok(new_typed_argument_type(module, arg_generic, argtype.location))
  of ATK_NESTED:
    let arg_module = ? file.find_module(argtype.module)
    let user_module = ? arg_module.user_module
    if user_module.generics.len != argtype.children.len:
      return err(fmt"{argtype.location} module `{user_module.name.asl}` expects {user_module.generics.len} generic types but found {argtype.children.len}")

    var typed_children: seq[TypedArgumentType]
    for child in argtype.children:
      let typed_child = ? populate_types(file, module, child)
      typed_children.add(typed_child)
    ok(new_typed_argument_type(user_module, typed_children, argtype.location))

proc populate_types(file: ast.File, argtype: ArgumentType): Result[
    TypedArgumentType, string] =
  case argtype.kind:
  of ATK_SIMPLE:
    let arg_module = ? file.find_module(argtype.module)
    if arg_module.generics.len != 0:
      return err(fmt"{argtype.location} module `{arg_module.name.asl}` expects {arg_module.generics.len} generic types but found 0")
    case arg_module.kind:
    of MK_NATIVE:
      let native_module = ? arg_module.native_module
      ok(new_typed_argument_type(native_module, argtype.location))
    of MK_USER:
      let user_module = ? arg_module.user_module
      ok(new_typed_argument_type(user_module, argtype.location))
  of ATK_NESTED:
    let arg_module = ? file.find_module(argtype.module)
    let user_module = ? arg_module.user_module
    if user_module.generics.len != argtype.children.len:
      return err(fmt"{argtype.location} module `{user_module.name.asl}` expects {user_module.generics.len} generic types but found {argtype.children.len}")

    var typed_children: seq[TypedArgumentType]
    for child in argtype.children:
      let typed_child = ? populate_types(file, child)
      typed_children.add(typed_child)
    ok(new_typed_argument_type(user_module, typed_children, argtype.location))

proc populate_types(file: ast.File, module: UserModule, generic: Generic,
    arg: ArgumentDefinition): Result[TypedArgumentDefinition, string] =
  let typed_arg = ? populate_types(file, module, generic, arg.argtype)
  ok(new_typed_argument_definition(typed_arg, arg.name))

proc populate_types(file: ast.File, module: UserModule,
    arg: ArgumentDefinition): Result[TypedArgumentDefinition, string] =
  let typed_arg = ? populate_types(file, module, arg.argtype)
  ok(new_typed_argument_definition(typed_arg, arg.name))

proc populate_types(file: ast.File, arg: ArgumentDefinition): Result[
    TypedArgumentDefinition, string] =
  let typed_arg = ? populate_types(file, arg.argtype)
  ok(new_typed_argument_definition(typed_arg, arg.name))

proc populate_types(file: ast.File, module: UserModule, generic: Generic,
    def: FunctionDefinition): Result[TypedFunctionDefinition, string] =
  var typed_args: seq[TypedArgumentDefinition]
  for arg in def.args:
    let typed_arg = ? populate_types(file, module, generic, arg)
    typed_args.add(typed_arg)
  let typed_return = ? populate_types(file, module, generic, def.returns)
  ok(new_typed_function_definition(def.name, typed_args, typed_return, def.location))

proc populate_types(file: ast.File, module: UserModule,
    def: FunctionDefinition): Result[TypedFunctionDefinition, string] =
  var typed_args: seq[TypedArgumentDefinition]
  for arg in def.args:
    let typed_arg = ? populate_types(file, module, arg)
    typed_args.add(typed_arg)
  let typed_return = ? populate_types(file, module, def.returns)
  ok(new_typed_function_definition(def.name, typed_args, typed_return, def.location))

proc populate_types(file: ast.File, def: FunctionDefinition): Result[
    TypedFunctionDefinition, string] =
  var typed_args: seq[TypedArgumentDefinition]
  for arg in def.args:
    let typed_arg = ? populate_types(file, arg)
    typed_args.add(typed_arg)
  let typed_return = ? populate_types(file, def.returns)
  ok(new_typed_function_definition(def.name, typed_args, typed_return, def.location))

proc populate_types(file: ast.File, module: UserModule,
    init: LiteralInit): Result[TypedLiteralInit, string] =
  let argtype = ? populate_types(file, module, init.module)
  ok(new_typed_literal_init(argtype, init.literal))

proc populate_types(file: ast.File, init: LiteralInit): Result[
    TypedLiteralInit, string] =
  let argtype = ? populate_types(file, init.module)
  ok(new_typed_literal_init(argtype, init.literal))

proc populate_types(file: ast.File, module: UserModule,
    init: StructInit): Result[TypedStructInit, string] =
  let argtype = ? populate_types(file, module, init.struct_ref.module)
  case init.struct_ref.kind:
  of SRK_DEFAULT:
    ok(new_typed_struct_init(argtype, init.args))
  of SRK_NAMED:
    let name = ? init.struct_ref.struct
    ok(new_typed_struct_init(name, argtype, init.args))

proc populate_types(file: ast.File, init: StructInit): Result[
    TypedStructInit, string] =
  let argtype = ? populate_types(file, init.struct_ref.module)
  case init.struct_ref.kind:
  of SRK_DEFAULT:
    ok(new_typed_struct_init(argtype, init.args))
  of SRK_NAMED:
    let name = ? init.struct_ref.struct
    ok(new_typed_struct_init(name, argtype, init.args))

proc populate_types(file: ast.File, module: UserModule,
    init: Initializer): Result[TypedInitializer, string] =
  case init.kind:
  of IK_LITERAL:
    let literal_init = ? init.literal
    let typed_literal_init = ? populate_types(file, module, literal_init)
    ok(new_typed_initializer(typed_literal_init))
  of IK_STRUCT:
    let struct_init = ? init.struct
    let typed_struct_init = ? populate_types(file, module, struct_init)
    ok(new_typed_initializer(typed_struct_init))

proc populate_types(file: ast.File, init: Initializer): Result[
    TypedInitializer, string] =
  case init.kind:
  of IK_LITERAL:
    let literal_init = ? init.literal
    let typed_literal_init = ? populate_types(file, literal_init)
    ok(new_typed_initializer(typed_literal_init))
  of IK_STRUCT:
    let struct_init = ? init.struct
    let typed_struct_init = ? populate_types(file, struct_init)
    ok(new_typed_initializer(typed_struct_init))

proc populate_types(file: ast.File, module: UserModule,
    fncall: FunctionCall): Result[TypedFunctionCall, string] =
  case fncall.fnref.kind:
  of FRK_LOCAL:
    ok(new_typed_function_call(fncall.name, fncall.args))
  of FRK_MODULE:
    let argtype = ? populate_types(file, module, ? fncall.fnref.module)
    ok(new_typed_function_call(argtype, fncall.name, fncall.args))

proc populate_types(file: ast.File, fncall: FunctionCall): Result[
    TypedFunctionCall, string] =
  case fncall.fnref.kind:
  of FRK_LOCAL:
    ok(new_typed_function_call(fncall.name, fncall.args))
  of FRK_MODULE:
    let argtype = ? populate_types(file, ? fncall.fnref.module)
    ok(new_typed_function_call(argtype, fncall.name, fncall.args))

proc populate_types(file: ast.File, module: UserModule,
    expression: Expression): Result[TypedExpression, string] =
  case expression.kind:
  of EK_FNCALL:
    let fncall = ? expression.fncall
    let typed_fncall = ? populate_types(file, module, fncall)
    ok(new_typed_expression(typed_fncall))
  of EK_INIT:
    let init = ? expression.init
    let typed_init = ? populate_types(file, module, init)
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

proc populate_types(file: ast.File, expression: Expression): Result[
    TypedExpression, string] =
  case expression.kind:
  of EK_FNCALL:
    let fncall = ? expression.fncall
    let typed_fncall = ? populate_types(file, fncall)
    ok(new_typed_expression(typed_fncall))
  of EK_INIT:
    let init = ? expression.init
    let typed_init = ? populate_types(file, init)
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

proc populate_types(file: ast.File, module: UserModule,
    statement: Statement): Result[TypedStatement, string] =
  let typed_expression = ? populate_types(file, module, statement.expression)
  ok(new_typed_statement(statement.arg, typed_expression))

proc populate_types(file: ast.File, statement: Statement): Result[
    TypedStatement, string] =
  let typed_expression = ? populate_types(file, statement.expression)
  ok(new_typed_statement(statement.arg, typed_expression))

proc populate_types(file: ast.File, module: UserModule,
    case_block: Case): Result[TypedCase, string] =
  var typed_statements: seq[TypedStatement]
  for statement in case_block.statements:
    let typed_statement = ? populate_types(file, module, statement)
    typed_statements.add(typed_statement)
  ok(new_typed_case(case_block.def, typed_statements))

proc populate_types(file: ast.File, case_block: Case): Result[
    TypedCase, string] =
  var typed_statements: seq[TypedStatement]
  for statement in case_block.statements:
    let typed_statement = ? populate_types(file, statement)
    typed_statements.add(typed_statement)
  ok(new_typed_case(case_block.def, typed_statements))

proc populate_types(file: ast.File, module: UserModule,
    else_block: Else): Result[TypedElse, string] =
  var typed_statements: seq[TypedStatement]
  for statement in else_block.statements:
    let typed_statement = ? populate_types(file, module, statement)
    typed_statements.add(typed_statement)
  ok(new_typed_else(typed_statements, else_block.location))

proc populate_types(file: ast.File, else_block: Else): Result[
    TypedElse, string] =
  var typed_statements: seq[TypedStatement]
  for statement in else_block.statements:
    let typed_statement = ? populate_types(file, statement)
    typed_statements.add(typed_statement)
  ok(new_typed_else(typed_statements, else_block.location))

proc populate_types(file: ast.File, module: UserModule, match: Match): Result[
    TypedMatch, string] =
  var typed_cases: seq[TypedCase]
  for case_block in match.case_blocks:
    let typed_case = ? populate_types(file, module, case_block)
    typed_cases.add(typed_case)

  case match.kind:
  of MK_CASE_ONLY:
    ok(new_typed_match(match.def, typed_cases))
  of MK_COMPLETE:
    let else_block = ? match.else_block
    let typed_else = ? populate_types(file, module, else_block)
    ok(new_typed_match(match.def, typed_cases, typed_else))

proc populate_types(file: ast.File, match: Match): Result[
    TypedMatch, string] =
  var typed_cases: seq[TypedCase]
  for case_block in match.case_blocks:
    let typed_case = ? populate_types(file, case_block)
    typed_cases.add(typed_case)

  case match.kind:
  of MK_CASE_ONLY:
    ok(new_typed_match(match.def, typed_cases))
  of MK_COMPLETE:
    let else_block = ? match.else_block
    let typed_else = ? populate_types(file, else_block)
    ok(new_typed_match(match.def, typed_cases, typed_else))

proc populate_types(file: ast.File, module: UserModule,
    step: FunctionStep): Result[TypedFunctionStep, string] =
  case step.kind:
  of FSK_STATEMENT:
    let statement = ? step.statement
    let typed_statement = ? populate_types(file, module, statement)
    ok(new_typed_function_step(typed_statement))
  of FSK_MATCH:
    let match = ? step.match
    let typed_match = ? populate_types(file, module, match)
    ok(new_typed_function_step(typed_match))

proc populate_types(file: ast.File, step: FunctionStep): Result[
    TypedFunctionStep, string] =
  case step.kind:
  of FSK_STATEMENT:
    let statement = ? step.statement
    let typed_statement = ? populate_types(file, statement)
    ok(new_typed_function_step(typed_statement))
  of FSK_MATCH:
    let match = ? step.match
    let typed_match = ? populate_types(file, match)
    ok(new_typed_function_step(typed_match))

proc populate_types(file: ast.File, module: UserModule,
    function: Function): Result[TypedFunction, string] =
  let typed_def = ? populate_types(file, module, function.def)
  var typed_steps: seq[TypedFunctionStep]
  for step in function.steps:
    let typed_step = ? populate_types(file, module, step)
    typed_steps.add(typed_step)
  ok(new_typed_function(typed_def, typed_steps))

proc populate_types(file: ast.File, function: Function): Result[
    TypedFunction, string] =
  let typed_def = ? populate_types(file, function.def)
  var typed_steps: seq[TypedFunctionStep]
  for step in function.steps:
    let typed_step = ? populate_types(file, step)
    typed_steps.add(typed_step)
  ok(new_typed_function(typed_def, typed_steps))

proc populate_types(file: ast.File, module: UserModule,
    generic: Generic): Result[TypedGeneric, string] =
  var typed_defs: seq[TypedFunctionDefinition]
  for def in generic.defs:
    let typed_def = ? populate_types(file, module, generic, def)
    typed_defs.add(typed_def)
  ok(new_typed_generic(generic.name, typed_defs, generic.location))

proc populate_types(file: ast.File, module: UserModule, struct: Struct): Result[
    TypedStruct, string] =
  var module_set: HashSet[UserModule]
  var typed_fields: seq[TypedArgumentDefinition]
  for field in struct.fields:
    let typed_field = ? populate_types(file, module, field)
    typed_fields.add(typed_field)
    module_set.incl(typed_field.module_deps)
  case struct.def.kind:
  of SDK_DEFAULT:
    ok(new_typed_struct(typed_fields, struct.location))
  of SDK_NAMED:
    let struct_name = ? struct.name
    ok(new_typed_struct(struct_name, typed_fields, struct.location))

proc populate_types(file: ast.File, module: UserModule): Result[TypedModule, string] =
  var typed_generics: seq[TypedGeneric]
  for generic in module.generics:
    let typed_generic = ? populate_types(file, module, generic)
    typed_generics.add(typed_generic)

  var typed_structs: seq[TypedStruct]
  for struct in module.structs:
    let typed_struct = ? populate_types(file, module, struct)
    typed_structs.add(typed_struct)

  var typed_functions: seq[TypedFunction]
  for function in module.functions:
    let typed_function = ? populate_types(file, module, function)
    typed_functions.add(typed_function)
  ok(new_typed_module(module.def, typed_generics, typed_structs,
      typed_functions))

proc populate_types*(file: ast.File): Result[TypedFile, string] =
  var module_graph: Table[UserModule, HashSet[UserModule]]
  var module_to_typed_module_map: Table[UserModule, TypedModule]
  for module in file.user_modules:
    let typed_module = ? populate_types(file, module)
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
    let typed_function = ? populate_types(file, function)
    typed_functions.add(typed_function)

  ok(new_typed_file(file.path, typed_modules, typed_functions))
