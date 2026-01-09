import results, strformat, tables, strutils, sets, algorithm, options, sequtils,
    hashes, parseutils

import deps_analyzer/parser
export parser

# NOTE: Cycle detection algo
proc detect_cycle[T](graph: Table[T, HashSet[T]], node: T,
    visited: var OrderedSet[T], ancestors: var OrderedSet[T], stack: var seq[
    T]): Result[seq[T], OrderedSet[T]] =
  if node in ancestors: return err(ancestors)
  if node in visited: return ok(stack)
  visited.incl(node)
  ancestors.incl(node)
  stack.add(node)
  for child in graph[node]:
    # NOTE: Graph may have self cycles since a module can
    # depend on itself for recursive dependencies. Other
    # than that no circular dependencies are allowed.
    if child == node: continue
    stack = ? detect_cycle(graph, child, visited, ancestors, stack)
  ancestors.excl(node)
  ok(stack)

# NOTE: weird api
# "ok" returns topologicaly sorted nodes basically module resolution order
# "error" returns the cycle in order of nodes as they come up.
proc detect_cycle[T](graph: Table[T, HashSet[T]]): Result[seq[T], seq[T]] =
  var visited: OrderedSet[T]
  var ordered_nodes: seq[T]
  for node in graph.keys:
    if node notin visited:
      var ancestors: OrderedSet[T]
      var stack: seq[T]
      let maybe_dag = detect_cycle(graph, node, visited, ancestors, stack)
      if maybe_dag.is_err: return err(maybe_dag.error.to_seq)
      ordered_nodes.add(maybe_dag.get.reversed)
  ok(ordered_nodes)

# Numeric literal parser utility
proc safe_parse[T](input: string): Result[void, string] =
  when T is SomeSignedInt:
    var temp: BiggestInt
    let code = parse_biggest_int(input, temp)
    if code == 0 or code != input.len:
      return err("Failed to parse signed int from: " & input)
    if temp < T.low.BiggestInt or temp > T.high.BiggestInt:
      return err("Overflow: Value out of range for type " & $T)
    ok() # ok(T(temp))
  elif T is SomeUnsignedInt:
    var temp: BiggestUInt
    let code = parse_biggest_uint(input, temp)
    if code == 0 or code != input.len:
      return err("Failed to parse unsigned int from: " & input)
    if temp < T.low.BiggestUInt or temp > T.high.BiggestUInt:
      return err("Overflow: Value out of range for type " & $T)
    ok() # ok(T(temp))
  elif T is SomeFloat:
    var temp: BiggestFloat
    let code = parse_biggest_float(input, temp)
    if code == 0 or code != input.len:
      return err("Failed to parse float from: " & input)
    let casted = T(temp)
    if BiggestFloat(casted) != temp:
      return err("Precision loss when converting to " & $T)
    ok() # ok(T(temp))
  else:
    err("safe_parse only supports signed/unsigned integers and floating-point types")

type
  TypedModuleRefKind* = enum
    TMRK_NATIVE, TMRK_USER, TMRK_GENERIC
  TypedModuleRef* = ref object of RootObj
    location: Location
    case kind: TypedModuleRefKind
    of TMRK_NATIVE:
      native_module: NativeModule
      native_children: seq[TypedModuleRef]
    of TMRK_USER:
      user_module: UserModule
      children: seq[TypedModuleRef]
    of TMRK_GENERIC:
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

proc new_typed_module_ref(native_module: NativeModule, children: seq[
    TypedModuleRef], location: Location): TypedModuleRef =
  TypedModuleRef(kind: TMRK_NATIVE, native_module: native_module,
      native_children: children, location: location)

proc new_typed_module_ref(generic: Generic,
    location: Location): TypedModuleRef =
  TypedModuleRef(kind: TMRK_GENERIC, generic: generic,
      location: location)

proc concretize(module_ref: TypedModuleRef, generic: Generic,
    concrete_module_ref: TypedModuleRef): TypedModuleRef =
  case module_ref.kind:
  of TMRK_NATIVE: module_ref
  of TMRK_GENERIC:
    if module_ref.generic == generic: concrete_module_ref
    else: module_ref
  of TMRK_USER:
    var concrete_children: seq[TypedModuleRef]
    for child in module_ref.children:
      let concrete_child = child.concretize(generic, concrete_module_ref)
      concrete_children.add(concrete_child)
    new_typed_module_ref(module_ref.user_module, concrete_children,
        module_ref.location)

proc module_deps(module_ref: TypedModuleRef): HashSet[UserModule] =
  var module_set: HashSet[UserModule]
  case module_ref.kind:
  of TMRK_NATIVE: discard
  of TMRK_GENERIC: discard
  of TMRK_USER:
    module_set.incl(module_ref.user_module)
    for child in module_ref.children:
      module_set.incl(child.module_deps)
  module_set

proc hash(module_ref: TypedModuleRef): Hash =
  case module_ref.kind:
  of TMRK_NATIVE:
    module_ref.native_module.hash
  of TMRK_GENERIC:
    module_ref.generic.hash
  of TMRK_USER:
    var acc = module_ref.user_module.hash
    for child in module_ref.children:
      acc = acc !& child.hash
    acc

proc self*(module_ref: TypedModuleRef): TypedModuleRef =
  case module_ref.kind:
  of TMRK_NATIVE: module_ref
  of TMRK_GENERIC: module_ref
  of TMRK_USER:
    var child_module_refs: seq[TypedModuleRef]
    for generic in module_ref.user_module.generics:
      let child_module_ref = new_typed_module_ref(generic, module_ref.location)
      child_module_refs.add(child_module_ref)
    new_typed_module_ref(module_ref.user_module, child_module_refs,
        module_ref.location)

proc asl*(module_ref: TypedModuleRef): string =
  case module_ref.kind:
  of TMRK_NATIVE: module_ref.native_module.name.asl
  of TMRK_GENERIC: module_ref.generic.name.asl
  of TMRK_USER:
    let module_name = module_ref.user_module.name.asl
    var children: seq[string]
    for child in module_ref.children:
      children.add(child.asl)
    let children_str = children.join(", ")
    if children.len == 0: module_name
    else: fmt"{module_name}[{children_str}]"

proc location*(module_ref: TypedModuleRef): Location = module_ref.location
proc kind*(module_ref: TypedModuleRef): TypedModuleRefKind = module_ref.kind
proc native_module*(module_ref: TypedModuleRef): Result[NativeModule, string] =
  case module_ref.kind:
  of TMRK_NATIVE: ok(module_ref.native_module)
  else: err(fmt"{module_ref.location} expected a native module")

proc user_module*(module_ref: TypedModuleRef): Result[UserModule, string] =
  case module_ref.kind:
  of TMRK_USER: ok(module_ref.user_module)
  of TMRK_GENERIC: err(fmt"{module_ref.location} expected a user module")
  else: err(fmt"{module_ref.location} expected a user module")

proc children*(module_ref: TypedModuleRef): Result[seq[TypedModuleRef], string] =
  case module_ref.kind:
  of TMRK_USER: ok(module_ref.children)
  of TMRK_NATIVE: ok(module_ref.native_children)
  else: err(fmt"{module_ref.location} expected a nested module ref")

proc generic*(module_ref: TypedModuleRef): Result[Generic, string] =
  case module_ref.kind:
  of TMRK_GENERIC: ok(module_ref.generic)
  else: err(fmt"{module_ref.location} expected a generic")

# NOTE: This is a utility function to internally add some function definitions
# like `byte_size`, `read`, `write`
proc make_typed_module_ref(file: parser.File, module_name: string): Result[
    TypedModuleRef, string] =
  let module_id = ? new_identifier(module_name)
  let module = ? file.find_module(module_id)
  case module.kind:
  of MK_NATIVE:
    let native_module = ? module.native_module
    ok(new_typed_module_ref(native_module, Location()))
  of MK_USER:
    let user_module = ? module.user_module
    let user_module_ref = new_typed_module_ref(user_module, Location())
    ok(user_module_ref.self)

type TypedArgumentDefinition* = ref object of RootObj
  name: Identifier
  module_ref: TypedModuleRef

proc new_typed_argument_definition(module_ref: TypedModuleRef,
    name: Identifier): TypedArgumentDefinition =
  TypedArgumentDefinition(module_ref: module_ref, name: name)

proc concretize(def: TypedArgumentDefinition, generic: Generic,
    module_ref: TypedModuleRef): TypedArgumentDefinition =
  let concrete_module_ref = concretize(def.module_ref, generic, module_ref)
  new_typed_argument_definition(concrete_module_ref, def.name)

proc module_deps(arg: TypedArgumentDefinition): HashSet[UserModule] =
  arg.module_ref.module_deps

proc hash(def: TypedArgumentDefinition): Hash =
  def.module_ref.hash

proc location*(arg: TypedArgumentDefinition): Location = arg.module_ref.location
proc name*(arg: TypedArgumentDefinition): Identifier = arg.name
proc module_ref*(arg: TypedArgumentDefinition): TypedModuleRef = arg.module_ref
proc asl*(arg: TypedArgumentDefinition): string = fmt"{arg.module_ref.asl} {arg.name.asl}"

# NOTE: This is a utility function to internally add some function definitions
# like `byte_size`, `read`, `write`
proc make_typed_arg_def(file: parser.File, module_name: string,
    arg_name: string): Result[TypedArgumentDefinition, string] =
  let arg_module_ref = ? make_typed_module_ref(file, module_name)
  let arg_name_id = ? new_identifier(arg_name)
  ok(new_typed_argument_definition(arg_module_ref, arg_name_id))

type TypedFunctionDefinition* = ref object of RootObj
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

proc hash*(def: TypedFunctionDefinition): Hash =
  var acc = def.name.hash
  for arg in def.args:
    acc = acc !& arg.hash
  acc !& def.returns.hash

proc `==`*(self: TypedFunctionDefinition,
    other: TypedFunctionDefinition): bool =
  self.hash == other.hash

proc asl*(def: TypedFunctionDefinition): string =
  var args: seq[string]
  for arg in def.args: args.add(arg.asl)

  let args_str = args.join(", ")
  let returns_str = def.returns.asl
  fmt"fn {def.name.asl}({args_str}): {returns_str}"

proc location*(def: TypedFunctionDefinition): Location = def.location
proc name*(def: TypedFunctionDefinition): Identifier = def.name
proc returns*(def: TypedFunctionDefinition): TypedModuleRef = def.returns
proc args*(def: TypedFunctionDefinition): seq[
    TypedArgumentDefinition] = def.args

proc concretize(def: TypedFunctionDefinition, generic: Generic,
    module_ref: TypedModuleRef): TypedFunctionDefinition =
  var concrete_args: seq[TypedArgumentDefinition]
  for arg in def.args:
    let concrete_arg = arg.concretize(generic, module_ref)
    concrete_args.add(concrete_arg)
  let concrete_returns = def.returns.concretize(generic, module_ref)
  new_typed_function_definition(def.name, concrete_args, concrete_returns, def.location)

# NOTE: This is a utility function to internally add some function definitions
# like `byte_size`, `read`, `write`
proc make_typed_function_def(file: parser.File, name: string, args: seq[(string,
    string)], returns: string): Result[TypedFunctionDefinition, string] =
  let name_id = ? new_identifier(name)
  let returns_module_ref = ? make_typed_module_ref(file, returns)
  var typed_arg_defs: seq[TypedArgumentDefinition]
  for (arg_module, arg_name) in args:
    typed_arg_defs.add( ? make_typed_arg_def(file, arg_module, arg_name))
  ok(new_typed_function_definition(name_id, typed_arg_defs, returns_module_ref,
      Location()))

type
  TypedStructKind* = enum
    TSK_DEFAULT, TSK_NAMED
  TypedStruct* = ref object of RootObj
    id: uint64
    fields: seq[TypedArgumentDefinition]
    location: Location
    case kind: TypedStructKind
    of TSK_DEFAULT: discard
    of TSK_NAMED: name: Identifier

proc new_typed_struct(id: uint64, fields: seq[TypedArgumentDefinition],
    location: Location): TypedStruct =
  TypedStruct(kind: TSK_DEFAULT, id: id, fields: fields, location: location)

proc new_typed_struct(id: uint64, name: Identifier, fields: seq[
    TypedArgumentDefinition], location: Location): TypedStruct =
  TypedStruct(kind: TSK_NAMED, id: id, name: name, fields: fields,
      location: location)

proc module_deps(struct: TypedStruct): HashSet[UserModule] =
  var module_set: HashSet[UserModule]
  for field in struct.fields:
    module_set.incl(field.module_deps)
  module_set

proc id*(struct: TypedStruct): uint64 = struct.id
proc hash*(struct: TypedStruct): Hash = struct.location.hash
proc `==`*(self: TypedStruct, other: TypedStruct): bool = self.hash == other.hash

proc kind*(struct: TypedStruct): TypedStructKind = struct.kind
proc location*(struct: TypedStruct): Location = struct.location
proc fields*(struct: TypedStruct): seq[TypedArgumentDefinition] = struct.fields
proc name*(struct: TypedStruct): Result[Identifier, string] =
  case struct.kind:
  of TSK_DEFAULT: err("{struct.location} expected a named struct")
  of TSK_NAMED: ok(struct.name)

type TypedLiteralInit* = ref object of RootObj
  module_ref: TypedModuleRef
  literal: Literal

proc new_typed_literal_init(module_ref: TypedModuleRef,
    literal: Literal): TypedLiteralInit =
  TypedLiteralInit(module_ref: module_ref, literal: literal)

proc location*(init: TypedLiteralInit): Location = init.module_ref.location
proc module_ref*(init: TypedLiteralInit): TypedModuleRef = init.module_ref
proc literal*(init: TypedLiteralInit): Literal = init.literal

proc module_deps(init: TypedLiteralInit): HashSet[UserModule] =
  init.module_ref.module_deps

type
  TypedStructRefKind* = enum
    TSRK_DEFAULT, TSRK_NAMED
  TypedStructRef* = ref object of RootObj
    module_ref: TypedModuleRef
    case kind: TypedStructRefKind
    of TSRK_DEFAULT: discard
    of TSRK_NAMED: name: Identifier

proc new_typed_struct_ref(module_ref: TypedModuleRef): TypedStructRef =
  TypedStructRef(kind: TSRK_DEFAULT, module_ref: module_ref)

proc new_typed_struct_ref(module_ref: TypedModuleRef,
    name: Identifier): TypedStructRef =
  TypedStructRef(kind: TSRK_NAMED, module_ref: module_ref, name: name)

proc module_deps(struct_ref: TypedStructRef): HashSet[UserModule] =
  struct_ref.module_ref.module_deps

proc location*(struct_ref: TypedStructRef): Location = struct_ref.module_ref.location
proc kind*(struct_ref: TypedStructRef): TypedStructRefKind = struct_ref.kind
proc module_ref*(struct_ref: TypedStructRef): TypedModuleRef = struct_ref.module_ref
proc name*(struct_ref: TypedStructRef): Result[Identifier, string] =
  case struct_ref.kind:
  of TSRK_NAMED: ok(struct_ref.name)
  of TSRK_DEFAULT: err(fmt"{struct_ref.location} expected a named struct")

type TypedStructInit* = ref object of RootObj
  struct_ref: TypedStructRef
  args: seq[KeywordArgument]

proc new_typed_struct_init(struct_ref: TypedStructRef, args: seq[
    KeywordArgument]): TypedStructInit =
  TypedStructInit(struct_ref: struct_ref, args: args)

proc module_deps(init: TypedStructInit): HashSet[UserModule] =
  init.struct_ref.module_deps

proc location*(init: TypedStructInit): Location = init.struct_ref.location
proc struct_ref*(init: TypedStructInit): TypedStructRef = init.struct_ref
proc fields*(init: TypedStructInit): seq[KeywordArgument] = init.args

type
  TypedInitializerKind* = enum
    TIK_LITERAL, TIK_STRUCT
  TypedInitializer* = ref object of RootObj
    case kind: TypedInitializerKind
    of TIK_LITERAL: literal: TypedLiteralInit
    of TIK_STRUCT: struct: TypedStructInit

proc new_typed_initializer(literal: TypedLiteralInit): TypedInitializer =
  TypedInitializer(kind: TIK_LITERAL, literal: literal)

proc new_typed_initializer(struct: TypedStructInit): TypedInitializer =
  TypedInitializer(kind: TIK_STRUCT, struct: struct)

proc location*(init: TypedInitializer): Location =
  case init.kind:
  of TIK_LITERAL: init.literal.location
  of TIK_STRUCT: init.struct.location

proc kind*(init: TypedInitializer): TypedInitializerKind = init.kind
proc struct*(init: TypedInitializer): Result[TypedStructInit, string] =
  case init.kind:
  of TIK_STRUCT: ok(init.struct)
  else: err(fmt"{init.location} expected a struct initializer")
proc literal*(init: TypedInitializer): Result[TypedLiteralInit, string] =
  case init.kind:
  of TIK_LITERAL: ok(init.literal)
  else: err(fmt"{init.location} expected a literal initializer")

proc module_deps(init: TypedInitializer): HashSet[UserModule] =
  case init.kind:
  of TIK_LITERAL: init.literal.module_deps
  of TIK_STRUCT: init.struct.module_deps

type
  TypedFunctionRefKind* = enum
    TFRK_LOCAL, TFRK_MODULE
  TypedFunctionRef* = ref object of RootObj
    name: Identifier
    arity: uint
    case kind: TypedFunctionRefKind
    of TFRK_LOCAL: discard
    of TFRK_MODULE: module_ref: TypedModuleRef

proc new_typed_function_ref(name: Identifier, arity: uint): TypedFunctionRef =
  TypedFunctionRef(kind: TFRK_LOCAL, name: name, arity: arity)

proc new_typed_function_ref(module_ref: TypedModuleRef, name: Identifier,
    arity: uint): TypedFunctionRef =
  TypedFunctionRef(kind: TFRK_MODULE, module_ref: module_ref, name: name, arity: arity)

proc module_deps(fnref: TypedFunctionRef): HashSet[UserModule] =
  case fnref.kind:
  of TFRK_LOCAL: init_hashset[UserModule]()
  of TFRK_MODULE: fnref.module_ref.module_deps

proc location*(fnref: TypedFunctionRef): Location =
  case fnref.kind:
  of TFRK_LOCAL: fnref.name.location
  of TFRK_MODULE: fnref.module_ref.location

proc kind*(fnref: TypedFunctionRef): TypedFunctionRefKind = fnref.kind
proc name*(fnref: TypedFunctionRef): Identifier = fnref.name
proc arity*(fnref: TypedFunctionRef): uint = fnref.arity
proc module_ref*(fnref: TypedFunctionRef): Result[TypedModuleRef, string] =
  case fnref.kind:
  of TFRK_LOCAL: err(fmt"{fnref.location} expected a module function call")
  of TFRK_MODULE: ok(fnref.module_ref)

type
  TypedFunctionCall* = ref object of RootObj
    fnref: TypedFunctionRef
    args: seq[Argument]

proc new_typed_function_call(fnref: TypedFunctionRef, args: seq[
    Argument]): TypedFunctionCall =
  TypedFunctionCall(fnref: fnref, args: args)

proc module_deps(fncall: TypedFunctionCall): HashSet[
    UserModule] = fncall.fnref.module_deps
proc location*(fncall: TypedFunctionCall): Location = fncall.fnref.location
proc fnref*(fncall: TypedFunctionCall): TypedFunctionRef = fncall.fnref
proc args*(fncall: TypedFunctionCall): seq[Argument] = fncall.args

type TypedStructGet* = ref object of RootObj
  variable: Identifier
  field: Identifier

proc new_typed_struct_get(variable: Identifier,
    field: Identifier): TypedStructGet =
  TypedStructGet(variable: variable, field: field)

proc module_deps(struct_get: TypedStructGet): HashSet[UserModule] =
  init_hashset[UserModule]()

proc location*(struct_get: TypedStructGet): Location = struct_get.variable.location
proc variable*(struct_get: TypedStructGet): Identifier = struct_get.variable
proc field*(struct_get: TypedStructGet): Identifier = struct_get.field

type TypedVariable* = ref object of RootObj
  name: Identifier

proc new_typed_variable(name: Identifier): TypedVariable =
  TypedVariable(name: name)

proc location*(variable: TypedVariable): Location = variable.name.location
proc name*(variable: TypedVariable): Identifier = variable.name
proc module_deps(variable: TypedVariable): HashSet[UserModule] = init_hashset[
    UserModule]()

type
  TypedExpressionKind* = enum
    TEK_MATCH, TEK_FNCALL, TEK_INIT, TEK_STRUCT_GET, TEK_VARIABLE
  TypedExpression* = ref object of RootObj
    case kind: TypedExpressionKind
    of TEK_MATCH: match: TypedMatch
    of TEK_FNCALL: fncall: TypedFunctionCall
    of TEK_INIT: init: TypedInitializer
    of TEK_STRUCT_GET: struct_get: TypedStructGet
    of TEK_VARIABLE: variable: TypedVariable
  TypedStatement* = ref object of RootObj
    arg: Identifier
    expression: TypedExpression
  TypedCase* = ref object of RootObj
    pattern: CasePattern
    location: Location
    statements: seq[TypedStatement]
  TypedElse* = ref object of RootObj
    location: Location
    statements: seq[TypedStatement]
  TypedMatchKind* = enum
    TMK_CASE_ONLY, TMK_COMPLETE
  TypedMatch* = ref object of RootObj
    location: Location
    operand: Identifier
    case_blocks: seq[TypedCase]
    case kind: TypedMatchKind
    of TMK_CASE_ONLY: discard
    of TMK_COMPLETE: else_block: TypedElse

proc new_typed_expression(match: TypedMatch): TypedExpression =
  TypedExpression(kind: TEK_MATCH, match: match)

proc new_typed_expression(fncall: TypedFunctionCall): TypedExpression =
  TypedExpression(kind: TEK_FNCALL, fncall: fncall)

proc new_typed_expression(init: TypedInitializer): TypedExpression =
  TypedExpression(kind: TEK_INIT, init: init)

proc new_typed_expression(struct_get: TypedStructGet): TypedExpression =
  TypedExpression(kind: TEK_STRUCT_GET, struct_get: struct_get)

proc new_typed_expression(variable: TypedVariable): TypedExpression =
  TypedExpression(kind: TEK_VARIABLE, variable: variable)

proc module_deps(match: TypedMatch): HashSet[UserModule]

proc module_deps(expression: TypedExpression): HashSet[UserModule] =
  case expression.kind:
  of TEK_MATCH: expression.match.module_deps
  of TEK_FNCALL: expression.fncall.module_deps
  of TEK_INIT: expression.init.module_deps
  of TEK_STRUCT_GET: expression.struct_get.module_deps
  of TEK_VARIABLE: expression.variable.module_deps

proc location*(match: TypedMatch): Location

proc location*(expression: TypedExpression): Location =
  case expression.kind:
  of TEK_MATCH: expression.match.location
  of TEK_FNCALL: expression.fncall.location
  of TEK_INIT: expression.init.location
  of TEK_STRUCT_GET: expression.struct_get.location
  of TEK_VARIABLE: expression.variable.location

proc kind*(expression: TypedExpression): TypedExpressionKind = expression.kind

proc match*(expression: TypedExpression): Result[TypedMatch, string] =
  case expression.kind:
  of TEK_MATCH: ok(expression.match)
  else: err(fmt"{expression.location} expected a match expression")

proc fncall*(expression: TypedExpression): Result[TypedFunctionCall, string] =
  case expression.kind:
  of TEK_FNCALL: ok(expression.fncall)
  else: err(fmt"{expression.location} expected a function call")

proc init*(expression: TypedExpression): Result[TypedInitializer, string] =
  case expression.kind:
  of TEK_INIT: ok(expression.init)
  else: err(fmt"{expression.location} expected an initilaizer")

proc struct_get*(expression: TypedExpression): Result[TypedStructGet, string] =
  case expression.kind:
  of TEK_STRUCT_GET: ok(expression.struct_get)
  else: err(fmt"{expression.location} expected a struct field accessor")

proc variable*(expression: TypedExpression): Result[TypedVariable, string] =
  case expression.kind:
  of TEK_VARIABLE: ok(expression.variable)
  else: err(fmt"{expression.location} expected a variable")

# Statement
proc new_typed_statement(arg: Identifier,
    expression: TypedExpression): TypedStatement =
  TypedStatement(arg: arg, expression: expression)

proc module_deps(statement: TypedStatement): HashSet[UserModule] =
  statement.expression.module_deps

proc arg*(statement: TypedStatement): Identifier = statement.arg
proc expression*(statement: TypedStatement): TypedExpression = statement.expression
proc location*(statement: TypedStatement): Location = statement.arg.location

# Case
proc new_typed_case(pattern: CasePattern, statements: seq[TypedStatement],
    location: Location): TypedCase =
  TypedCase(pattern: pattern, statements: statements, location: location)

proc location*(case_block: TypedCase): Location = case_block.location
proc pattern*(case_block: TypedCase): CasePattern = case_block.pattern
proc statements*(case_block: TypedCase): seq[
    TypedStatement] = case_block.statements

proc module_deps(case_block: TypedCase): HashSet[UserModule] =
  var module_set: HashSet[UserModule]
  for statement in case_block.statements:
    module_set.incl(statement.module_deps)
  module_set

# Else
proc new_typed_else(statements: seq[TypedStatement],
    location: Location): TypedElse =
  TypedElse(statements: statements, location: location)

proc location*(else_block: TypedElse): Location = else_block.location
proc statements*(else_block: TypedElse): seq[
    TypedStatement] = else_block.statements

proc module_deps(else_block: TypedElse): HashSet[UserModule] =
  var module_set: HashSet[UserModule]
  for statement in else_block.statements:
    module_set.incl(statement.module_deps)
  module_set

# Match
proc new_typed_match(operand: Identifier, arg: Identifier, case_blocks: seq[
    TypedCase], location: Location): TypedMatch =
  TypedMatch(kind: TMK_CASE_ONLY, operand: operand, case_blocks: case_blocks,
      location: location)

proc new_typed_match(operand: Identifier, arg: Identifier, case_blocks: seq[
    TypedCase], else_block: TypedElse, location: Location): TypedMatch =
  TypedMatch(kind: TMK_COMPLETE, operand: operand, case_blocks: case_blocks,
      else_block: else_block, location: location)

proc kind*(match: TypedMatch): TypedMatchKind = match.kind
proc location*(match: TypedMatch): Location = match.location
proc operand*(match: TypedMatch): Identifier = match.operand
proc case_blocks*(match: TypedMatch): seq[TypedCase] = match.case_blocks
proc else_block*(match: TypedMatch): Result[TypedElse, string] =
  case match.kind:
  of TMK_CASE_ONLY: err(fmt"{match.location} expected an else block")
  of TMK_COMPLETE: ok(match.else_block)

proc module_deps(match: TypedMatch): HashSet[UserModule] =
  var module_set: HashSet[UserModule]
  for case_block in match.case_blocks:
    module_set.incl(case_block.module_deps)
  case match.kind:
  of TMK_CASE_ONLY: discard
  of TMK_COMPLETE: module_set.incl(match.else_block.module_deps)
  module_set

type TypedFunction* = ref object of RootObj
  def: TypedFunctionDefinition
  steps: seq[TypedStatement]

proc new_typed_function(def: TypedFunctionDefinition, steps: seq[
    TypedStatement]): TypedFunction =
  TypedFunction(def: def, steps: steps)

proc module_deps(function: TypedFunction): HashSet[UserModule] =
  var module_set: HashSet[UserModule]
  module_set.incl(function.def.module_deps)
  for step in function.steps:
    module_set.incl(step.module_deps)
  module_set

proc def*(function: TypedFunction): TypedFunctionDefinition = function.def
proc steps*(function: TypedFunction): seq[TypedStatement] = function.steps

proc assign_type(file: parser.File, optional_module: Option[UserModule],
    module_name: Identifier): Result[TypedModuleRef, string] =
  # NOTE: For handling generics that are only defined in a module
  if optional_module.is_some:
    let module = optional_module.get
    let maybe_arg_generic = module.find_generic(module_name)
    if maybe_arg_generic.is_ok:
      return ok(new_typed_module_ref(maybe_arg_generic.get,
          module_name.location))

  let arg_module = ? file.find_module(module_name)
  case arg_module.kind:
  of MK_NATIVE:
    let native_module = ? arg_module.native_module
    ok(new_typed_module_ref(native_module, module_name.location))
  of MK_USER:
    let user_module = ? arg_module.user_module
    ok(new_typed_module_ref(user_module, module_name.location))

proc assign_type(file: parser.File, optional_module: Option[NativeModule],
    module_name: Identifier): Result[TypedModuleRef, string] =
  # NOTE: For handling generics that are only defined in a module
  if optional_module.is_some:
    let module = optional_module.get
    let maybe_arg_generic = module.find_generic(module_name)
    if maybe_arg_generic.is_ok:
      return ok(new_typed_module_ref(maybe_arg_generic.get,
          module_name.location))

  let arg_module = ? file.find_module(module_name)
  case arg_module.kind:
  of MK_NATIVE:
    let native_module = ? arg_module.native_module
    ok(new_typed_module_ref(native_module, module_name.location))
  of MK_USER:
    let user_module = ? arg_module.user_module
    ok(new_typed_module_ref(user_module, module_name.location))

proc assign_type(file: parser.File, optional_module: Option[UserModule],
    module_ref: ModuleRef): Result[TypedModuleRef, string] =
  case module_ref.kind:
  of MRK_SIMPLE: assign_type(file, optional_module, module_ref.module)
  of MRK_NESTED:
    let arg_module = ? file.find_module(module_ref.module)
    case arg_module.kind:
    of MK_NATIVE:
      let native_module = ? arg_module.native_module
      var typed_children: seq[TypedModuleRef]
      for child in module_ref.children:
        let typed_child = ? assign_type(file, optional_module, child)
        typed_children.add(typed_child)
      ok(new_typed_module_ref(native_module, typed_children,
          module_ref.location))
    of MK_USER:
      let user_module = ? arg_module.user_module
      var typed_children: seq[TypedModuleRef]
      for child in module_ref.children:
        let typed_child = ? assign_type(file, optional_module, child)
        typed_children.add(typed_child)
      ok(new_typed_module_ref(user_module, typed_children, module_ref.location))

proc assign_type(file: parser.File, optional_module: Option[NativeModule],
    module_ref: ModuleRef): Result[TypedModuleRef, string] =
  case module_ref.kind:
  of MRK_SIMPLE: assign_type(file, optional_module, module_ref.module)
  of MRK_NESTED:
    let arg_module = ? file.find_module(module_ref.module)
    case arg_module.kind:
    of MK_NATIVE:
      let native_module = ? arg_module.native_module
      var typed_children: seq[TypedModuleRef]
      for child in module_ref.children:
        let typed_child = ? assign_type(file, optional_module, child)
        typed_children.add(typed_child)
      ok(new_typed_module_ref(native_module, typed_children,
          module_ref.location))
    of MK_USER:
      let user_module = ? arg_module.user_module
      var typed_children: seq[TypedModuleRef]
      for child in module_ref.children:
        let typed_child = ? assign_type(file, optional_module, child)
        typed_children.add(typed_child)
      ok(new_typed_module_ref(user_module, typed_children, module_ref.location))

proc assign_type(file: parser.File, module: UserModule,
    module_ref: ModuleRef): Result[TypedModuleRef, string] =
  assign_type(file, some(module), module_ref)

proc assign_type(file: parser.File, module: NativeModule,
    module_ref: ModuleRef): Result[TypedModuleRef, string] =
  assign_type(file, some(module), module_ref)

proc assign_type(file: parser.File, module_ref: ModuleRef): Result[
    TypedModuleRef, string] =
  assign_type(file, none(UserModule), module_ref)

proc assign_type(file: parser.File, module: UserModule, generic: Generic,
    arg: ArgumentDefinition): Result[TypedArgumentDefinition, string] =
  let typed_arg = ? assign_type(file, module, arg.module_ref)
  ok(new_typed_argument_definition(typed_arg, arg.name))

proc assign_type(file: parser.File, module: NativeModule, generic: Generic,
    arg: ArgumentDefinition): Result[TypedArgumentDefinition, string] =
  let typed_arg = ? assign_type(file, module, arg.module_ref)
  ok(new_typed_argument_definition(typed_arg, arg.name))

proc assign_type(file: parser.File, module: UserModule,
    arg: ArgumentDefinition): Result[TypedArgumentDefinition, string] =
  let typed_arg = ? assign_type(file, module, arg.module_ref)
  ok(new_typed_argument_definition(typed_arg, arg.name))

proc assign_type(file: parser.File, module: NativeModule,
    arg: ArgumentDefinition): Result[TypedArgumentDefinition, string] =
  let typed_arg = ? assign_type(file, module, arg.module_ref)
  ok(new_typed_argument_definition(typed_arg, arg.name))

proc assign_type(file: parser.File, arg: ArgumentDefinition): Result[
    TypedArgumentDefinition, string] =
  let typed_arg = ? assign_type(file, arg.module_ref)
  ok(new_typed_argument_definition(typed_arg, arg.name))

proc assign_type(file: parser.File, module: UserModule, generic: Generic,
    def: FunctionDefinition): Result[TypedFunctionDefinition, string] =
  var typed_args: seq[TypedArgumentDefinition]
  for arg in def.args:
    let typed_arg = ? assign_type(file, module, generic, arg)
    typed_args.add(typed_arg)
  let typed_return = ? assign_type(file, module, def.returns)
  ok(new_typed_function_definition(def.name, typed_args, typed_return, def.location))

proc assign_type(file: parser.File, module: NativeModule, generic: Generic,
    def: FunctionDefinition): Result[TypedFunctionDefinition, string] =
  var typed_args: seq[TypedArgumentDefinition]
  for arg in def.args:
    let typed_arg = ? assign_type(file, module, generic, arg)
    typed_args.add(typed_arg)
  let typed_return = ? assign_type(file, module, def.returns)
  ok(new_typed_function_definition(def.name, typed_args, typed_return, def.location))

proc assign_type(file: parser.File, module: UserModule,
    def: FunctionDefinition): Result[TypedFunctionDefinition, string] =
  var typed_args: seq[TypedArgumentDefinition]
  for arg in def.args:
    let typed_arg = ? assign_type(file, module, arg)
    typed_args.add(typed_arg)
  let typed_return = ? assign_type(file, module, def.returns)
  ok(new_typed_function_definition(def.name, typed_args, typed_return, def.location))

proc assign_type(file: parser.File, module: NativeModule,
    def: FunctionDefinition): Result[TypedFunctionDefinition, string] =
  var typed_args: seq[TypedArgumentDefinition]
  for arg in def.args:
    let typed_arg = ? assign_type(file, module, arg)
    typed_args.add(typed_arg)
  let typed_return = ? assign_type(file, module, def.returns)
  ok(new_typed_function_definition(def.name, typed_args, typed_return, def.location))

proc assign_type(file: parser.File, def: FunctionDefinition): Result[
    TypedFunctionDefinition, string] =
  var typed_args: seq[TypedArgumentDefinition]
  for arg in def.args:
    let typed_arg = ? assign_type(file, arg)
    typed_args.add(typed_arg)
  let typed_return = ? assign_type(file, def.returns)
  ok(new_typed_function_definition(def.name, typed_args, typed_return, def.location))

proc assign_type(file: parser.File, module: UserModule,
    init: LiteralInit): Result[TypedLiteralInit, string] =
  let module_ref = ? assign_type(file, module, init.module)
  ok(new_typed_literal_init(module_ref, init.literal))

proc assign_type(file: parser.File, init: LiteralInit): Result[
    TypedLiteralInit, string] =
  let module_ref = ? assign_type(file, init.module)
  ok(new_typed_literal_init(module_ref, init.literal))

proc assign_type(file: parser.File, module: UserModule,
    struct_ref: StructRef): Result[TypedStructRef, string] =
  let module_ref = ? assign_type(file, module, struct_ref.module)
  case struct_ref.kind:
  of SRK_DEFAULT: ok(new_typed_struct_ref(module_ref))
  of SRK_NAMED: ok(new_typed_struct_ref(module_ref, ? struct_ref.struct))

proc assign_type(file: parser.File, struct_ref: StructRef): Result[
    TypedStructRef, string] =
  let module_ref = ? assign_type(file, struct_ref.module)
  case struct_ref.kind:
  of SRK_DEFAULT: ok(new_typed_struct_ref(module_ref))
  of SRK_NAMED: ok(new_typed_struct_ref(module_ref, ? struct_ref.struct))

proc assign_type(file: parser.File, module: UserModule,
    init: StructInit): Result[TypedStructInit, string] =
  let struct_ref = ? assign_type(file, module, init.struct_ref)
  ok(new_typed_struct_init(struct_ref, init.args))

proc assign_type(file: parser.File, init: StructInit): Result[
    TypedStructInit, string] =
  let struct_ref = ? assign_type(file, init.struct_ref)
  ok(new_typed_struct_init(struct_ref, init.args))

proc assign_type(file: parser.File, module: UserModule,
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

proc assign_type(file: parser.File, init: Initializer): Result[
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

proc assign_type(file: parser.File, module: UserModule,
    fnref: FunctionRef, arity: uint): Result[TypedFunctionRef, string] =
  case fnref.kind:
  of FRK_LOCAL:
    ok(new_typed_function_ref(fnref.name, arity))
  of FRK_MODULE:
    let module_ref = ? assign_type(file, module, ? fnref.module)
    ok(new_typed_function_ref(module_ref, fnref.name, arity))

proc assign_type(file: parser.File, fnref: FunctionRef, arity: uint): Result[
    TypedFunctionRef, string] =
  case fnref.kind:
  of FRK_LOCAL:
    ok(new_typed_function_ref(fnref.name, arity))
  of FRK_MODULE:
    let module_ref = ? assign_type(file, ? fnref.module)
    ok(new_typed_function_ref(module_ref, fnref.name, arity))

proc assign_type(file: parser.File, module: UserModule,
    fncall: FunctionCall): Result[TypedFunctionCall, string] =
  let fnref = ? assign_type(file, module, fncall.fnref, fncall.args.len.uint)
  ok(new_typed_function_call(fnref, fncall.args))

proc assign_type(file: parser.File, fncall: FunctionCall): Result[
    TypedFunctionCall, string] =
  let fnref = ? assign_type(file, fncall.fnref, fncall.args.len.uint)
  ok(new_typed_function_call(fnref, fncall.args))

# Forward Declaration needed due to cyclic dependencies
proc assign_type(file: parser.File, module: UserModule, match: Match): Result[
    TypedMatch, string]

# Forward Declaration needed due to cyclic dependencies
proc assign_type(file: parser.File, match: Match): Result[
    TypedMatch, string]

# Helper function to handle expression case statement with optional module
proc assign_type_expression_helper(file: parser.File, expression: Expression,
    module: Option[UserModule]): Result[TypedExpression, string] =
  case expression.kind:
  of EK_MATCH:
    let match = ? expression.match
    let typed_match = if module.is_some:
      ? assign_type(file, module.get, match)
    else:
      ? assign_type(file, match)
    ok(new_typed_expression(typed_match))
  of EK_FNCALL:
    let fncall = ? expression.fncall
    let typed_fncall = if module.is_some:
      ? assign_type(file, module.get, fncall)
    else:
      ? assign_type(file, fncall)
    ok(new_typed_expression(typed_fncall))
  of EK_INIT:
    let init = ? expression.init
    let typed_init = if module.is_some:
      ? assign_type(file, module.get, init)
    else:
      ? assign_type(file, init)
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

proc assign_type(file: parser.File, module: UserModule,
    expression: Expression): Result[TypedExpression, string] =
  assign_type_expression_helper(file, expression, some(module))

proc assign_type(file: parser.File, expression: Expression): Result[
    TypedExpression, string] =
  assign_type_expression_helper(file, expression, none(UserModule))

proc assign_type(file: parser.File, module: UserModule,
    statement: Statement): Result[TypedStatement, string] =
  let typed_expression = ? assign_type(file, module, statement.expression)
  ok(new_typed_statement(statement.arg, typed_expression))

proc assign_type(file: parser.File, statement: Statement): Result[
    TypedStatement, string] =
  let typed_expression = ? assign_type(file, statement.expression)
  ok(new_typed_statement(statement.arg, typed_expression))

# Helper function to process statements with optional module
proc process_statements(file: parser.File, statements: seq[Statement],
    module: Option[UserModule]): Result[seq[TypedStatement], string] =
  var typed_statements: seq[TypedStatement]
  for statement in statements:
    let typed_statement = if module.is_some:
      ? assign_type(file, module.get, statement)
    else:
      ? assign_type(file, statement)
    typed_statements.add(typed_statement)
  ok(typed_statements)

proc assign_type(file: parser.File, module: UserModule,
    case_block: Case): Result[TypedCase, string] =
  let typed_statements = ? process_statements(file, case_block.statements, some(module))
  ok(new_typed_case(case_block.def.pattern, typed_statements,
      case_block.def.location))

proc assign_type(file: parser.File, case_block: Case): Result[
    TypedCase, string] =
  let typed_statements = ? process_statements(file, case_block.statements, none(UserModule))
  ok(new_typed_case(case_block.def.pattern, typed_statements,
      case_block.def.location))

proc assign_type(file: parser.File, module: UserModule,
    else_block: Else): Result[TypedElse, string] =
  let typed_statements = ? process_statements(file, else_block.statements, some(module))
  ok(new_typed_else(typed_statements, else_block.location))

proc assign_type(file: parser.File, else_block: Else): Result[
    TypedElse, string] =
  let typed_statements = ? process_statements(file, else_block.statements, none(UserModule))
  ok(new_typed_else(typed_statements, else_block.location))

# Helper function to process match with optional module
proc process_match(file: parser.File, match: Match,
    module: Option[UserModule]): Result[TypedMatch, string] =
  var typed_cases: seq[TypedCase]
  for case_block in match.case_blocks:
    let typed_case = if module.is_some:
      ? assign_type(file, module.get, case_block)
    else:
      ? assign_type(file, case_block)
    typed_cases.add(typed_case)

  case match.kind:
  of MK_CASE_ONLY:
    ok(new_typed_match(match.def.operand, match.def.arg, typed_cases,
        match.def.location))
  of MK_COMPLETE:
    let else_block = ? match.else_block
    let typed_else = if module.is_some:
      ? assign_type(file, module.get, else_block)
    else:
      ? assign_type(file, else_block)
    ok(new_typed_match(match.def.operand, match.def.arg, typed_cases,
        typed_else, match.def.location))

proc assign_type(file: parser.File, module: UserModule, match: Match): Result[
    TypedMatch, string] =
  process_match(file, match, some(module))

proc assign_type(file: parser.File, match: Match): Result[
    TypedMatch, string] =
  process_match(file, match, none(UserModule))

proc assign_type(file: parser.File, module: UserModule,
    function: Function): Result[TypedFunction, string] =
  let typed_def = ? assign_type(file, module, function.def)
  let typed_steps = ? process_statements(file, function.steps, some(module))
  ok(new_typed_function(typed_def, typed_steps))

proc assign_type(file: parser.File, function: Function): Result[
    TypedFunction, string] =
  let typed_def = ? assign_type(file, function.def)
  let typed_steps = ? process_statements(file, function.steps, none(UserModule))
  ok(new_typed_function(typed_def, typed_steps))

type TypedGeneric* = ref object of RootObj
  id: uint64
  generic: Generic
  defs: seq[TypedFunctionDefinition]
  defs_map: Table[TypedFunctionDefinition, TypedFunctionDefinition]
  location: Location

proc new_typed_generic(id: uint64, generic: Generic, defs: seq[
    TypedFunctionDefinition], location: Location): TypedGeneric =
  var defs_map: Table[TypedFunctionDefinition, TypedFunctionDefinition]
  for def in defs: defs_map[def] = def
  TypedGeneric(id: id, generic: generic, defs: defs, defs_map: defs_map,
      location: location)

proc module_deps(generic: TypedGeneric): HashSet[UserModule] =
  var module_set: HashSet[UserModule]
  for def in generic.defs:
    module_set.incl(def.module_deps)
  module_set

proc id*(generic: TypedGeneric): uint64 = generic.id
proc location*(generic: TypedGeneric): Location = generic.location
proc name*(generic: TypedGeneric): Identifier = generic.generic.name
proc defs*(generic: TypedGeneric): seq[TypedFunctionDefinition] = generic.defs
proc hash*(generic: TypedGeneric): Hash = generic.location.hash
proc `==`*(self: TypedGeneric, other: TypedGeneric): bool = self.hash == other.hash
proc asl*(generic: TypedGeneric): string = generic.name.asl

proc concrete_defs*(generic: TypedGeneric, module_ref: TypedModuleRef): seq[
    TypedFunctionDefinition] =
  var concrete_defs: seq[TypedFunctionDefinition]
  for def in generic.defs:
    let concrete_def = def.concretize(generic.generic, module_ref)
    concrete_defs.add(concrete_def)
  concrete_defs

proc find_function*(generic: TypedGeneric,
    def: TypedFunctionDefinition): Result[TypedFunctionDefinition, string] =
  if def in generic.defs_map:
    ok(generic.defs_map[def])
  else:
    err(fmt"failed to find function `{def.asl}`")

proc assign_type(file: parser.File, module: UserModule,
    generic: Generic, id: uint64): Result[TypedGeneric, string] =
  var typed_defs: seq[TypedFunctionDefinition]
  for def in generic.defs:
    let typed_def = ? assign_type(file, module, generic, def)
    typed_defs.add(typed_def)
  ok(new_typed_generic(id, generic, typed_defs, generic.location))

proc assign_type(file: parser.File, module: NativeModule,
    generic: Generic, id: uint64): Result[TypedGeneric, string] =
  var typed_defs: seq[TypedFunctionDefinition]
  for def in generic.defs:
    let typed_def = ? assign_type(file, module, generic, def)
    typed_defs.add(typed_def)
  ok(new_typed_generic(id, generic, typed_defs, generic.location))

proc assign_type(file: parser.File, module: UserModule, struct: Struct,
    id: uint64): Result[TypedStruct, string] =
  var typed_fields: seq[TypedArgumentDefinition]
  for field in struct.fields:
    let typed_field = ? assign_type(file, module, field)
    typed_fields.add(typed_field)
  case struct.def.kind:
  of SDK_DEFAULT:
    ok(new_typed_struct(id, typed_fields, struct.location))
  of SDK_NAMED:
    let struct_name = ? struct.name
    ok(new_typed_struct(id, struct_name, typed_fields, struct.location))

proc assign_type(file: parser.File, module: NativeModule, struct: Struct,
    id: uint64): Result[TypedStruct, string] =
  var typed_fields: seq[TypedArgumentDefinition]
  for field in struct.fields:
    let typed_field = ? assign_type(file, module, field)
    typed_fields.add(typed_field)
  case struct.def.kind:
  of SDK_DEFAULT:
    ok(new_typed_struct(id, typed_fields, struct.location))
  of SDK_NAMED:
    let struct_name = ? struct.name
    ok(new_typed_struct(id, struct_name, typed_fields, struct.location))

type TypedUserModule* = ref object of RootObj
  id: uint64
  name: Identifier
  location: Location
  generics: seq[TypedGeneric]
  generics_map: Table[Generic, TypedGeneric]
  structs: seq[TypedStruct]
  functions_map: Table[TypedFunctionDefinition, TypedFunction]
  functions: seq[TypedFunction]
  # NOTE: This map contains some auto generated function definitions like
  # `byte_size`, `read`, `write`. The codegenerator should generate the
  # function body for these corresponding internal functions.
  internal_functions_map: Table[TypedFunctionDefinition, TypedFunctionDefinition]

proc new_typed_user_module(id: uint64, name: Identifier, generic_pairs: seq[(
    Generic, TypedGeneric)], structs: seq[TypedStruct], functions: seq[
    TypedFunction], internal_functions: seq[TypedFunctionDefinition],
    location: Location): TypedUserModule =
  var generics: seq[TypedGeneric]
  var generics_map: Table[Generic, TypedGeneric]
  for (generic, typed_generic) in generic_pairs:
    generics.add(typed_generic)
    generics_map[generic] = typed_generic

  var functions_map: Table[TypedFunctionDefinition, TypedFunction]
  for function in functions: functions_map[function.def] = function

  var internal_functions_map: Table[TypedFunctionDefinition, TypedFunctionDefinition]
  for internal_function in internal_functions:
    internal_functions_map[internal_function] = internal_function

  TypedUserModule(id: id, name: name, location: location, generics: generics,
      generics_map: generics_map, structs: structs, functions: functions,
      functions_map: functions_map, internal_functions_map: internal_functions_map)

proc module_deps(module: TypedUserModule): HashSet[UserModule] =
  var module_set: HashSet[UserModule]
  for generic in module.generics:
    module_set.incl(generic.module_deps)
  for struct in module.structs:
    module_set.incl(struct.module_deps)
  for function in module.functions:
    module_set.incl(function.module_deps)
  module_set

proc id*(module: TypedUserModule): uint64 = module.id
proc location*(module: TypedUserModule): Location = module.location
proc name*(module: TypedUserModule): Identifier = module.name
proc generics*(module: TypedUserModule): seq[TypedGeneric] = module.generics
proc structs*(module: TypedUserModule): seq[TypedStruct] = module.structs
proc functions*(module: TypedUserModule): seq[TypedFunction] = module.functions
proc hash*(module: TypedUserModule): Hash = module.location.hash
proc `==`*(self: TypedUserModule, other: TypedUserModule): bool = self.hash == other.hash
proc asl*(module: TypedUserModule): string = module.name.asl

proc find_generic*(module: TypedUserModule, generic: Generic): Result[
    TypedGeneric, string] =
  if generic in module.generics_map:
    ok(module.generics_map[generic])
  else:
    err("failed to find generic `{generic.name.asl}`")

proc find_function*(module: TypedUserModule,
    def: TypedFunctionDefinition): Result[TypedFunctionDefinition, string] =
  if def in module.functions_map:
    ok(module.functions_map[def].def)
  elif def in module.internal_functions_map:
    ok(module.internal_functions_map[def])
  else:
    err(fmt"2 - failed to find function `{def.asl}`")

proc assign_type(file: parser.File, module: UserModule, id: uint64): Result[
    TypedUserModule, string] =
  var generic_pairs: seq[(Generic, TypedGeneric)]
  for index, generic in module.generics:
    let typed_generic = ? assign_type(file, module, generic, index.uint64)
    generic_pairs.add((generic, typed_generic))

  var typed_structs: seq[TypedStruct]
  for index, struct in module.structs:
    let typed_struct = ? assign_type(file, module, struct, index.uint64)
    typed_structs.add(typed_struct)

  var typed_functions: seq[TypedFunction]
  for function in module.functions:
    let typed_function = ? assign_type(file, module, function)
    typed_functions.add(typed_function)

  # NOTE: This internal functions are injected in every user defined module
  # since they are pointers under the hood and to make the array implementation
  # work every module needs to have `byte_size`, `read` and `write` functions
  # but adding them before codegen is hard in case of `read` and `write` because
  # there is no conversion utility between module and pointers.
  var internal_functions: seq[TypedFunctionDefinition]
  internal_functions.add( ? make_typed_function_def(file, "byte_size", @[("U64",
      "items")], "U64"))
  internal_functions.add( ? make_typed_function_def(file, "read", @[(
      "Pointer", "ptr"), ("U64", "offset")], module.name.asl))
  internal_functions.add( ? make_typed_function_def(file, "write", @[(
      module.name.asl, "item"), ("Pointer", "ptr"), ("U64", "offset")], "Pointer"))

  ok(new_typed_user_module(id, module.name, generic_pairs, typed_structs,
      typed_functions, internal_functions, module.location))

type TypedNativeFunction* = ref object of RootObj
  native: string
  def: TypedFunctionDefinition

proc new_typed_native_function(native: string,
    def: TypedFunctionDefinition): TypedNativeFunction =
  TypedNativeFunction(native: native, def: def)

proc native*(function: TypedNativeFunction): string = function.native
proc def*(function: TypedNativeFunction): TypedFunctionDefinition = function.def

proc assign_type(file: parser.File, module: NativeModule,
    function: ExternFunction): Result[TypedNativeFunction, string] =
  let typed_def = ? assign_type(file, module, function.def)
  ok(new_typed_native_function(function.extern, typed_def))

type TypedNativeModule* = ref object of RootObj
  id: uint64
  name: Identifier
  generics: seq[TypedGeneric]
  generics_map: Table[Generic, TypedGeneric]
  structs: seq[TypedStruct]
  functions: seq[TypedNativeFunction]
  functions_map: Table[TypedFunctionDefinition, TypedNativeFunction]

proc new_typed_native_module(name: Identifier, generic_pairs: seq[(Generic,
    TypedGeneric)], structs: seq[TypedStruct], functions: seq[
        TypedNativeFunction],
    id: uint64): TypedNativeModule =
  var generics: seq[TypedGeneric]
  var generics_map: Table[Generic, TypedGeneric]
  for (generic, typed_generic) in generic_pairs:
    generics.add(typed_generic)
    generics_map[generic] = typed_generic

  var functions_map: Table[TypedFunctionDefinition, TypedNativeFunction]
  for function in functions: functions_map[function.def] = function
  TypedNativeModule(id: id, name: name, generics: generics, structs: structs,
      generics_map: generics_map, functions: functions,
      functions_map: functions_map)

proc name*(module: TypedNativeModule): Identifier = module.name
proc generics*(module: TypedNativeModule): seq[TypedGeneric] = module.generics
proc structs*(module: TypedNativeModule): seq[TypedStruct] = module.structs
proc functions*(module: TypedNativeModule): seq[
    TypedNativeFunction] = module.functions

proc id*(module: TypedNativeModule): uint64 = module.id
proc hash*(module: TypedNativeModule): Hash = module.name.hash
proc `==`*(self: TypedNativeModule, other: TypedNativeModule): bool = self.hash == other.hash
proc asl*(module: TypedNativeModule): string = module.name.asl

proc find_generic*(module: TypedNativeModule, generic: Generic): Result[
    TypedGeneric, string] =
  if generic in module.generics_map:
    ok(module.generics_map[generic])
  else:
    err("failed to find generic `{generic.name.asl}`")

proc find_function*(module: TypedNativeModule,
    def: TypedFunctionDefinition): Result[TypedFunctionDefinition, string] =
  if def in module.functions_map:
    ok(module.functions_map[def].def)
  else:
    err(fmt"failed to find function `{def.asl}`")

proc validate(module: TypedNativeModule,
    integer_literal: IntegerLiteral): Result[void, string] =
  case module.name.asl:
  of "S8": safe_parse[int8](integer_literal.asl)
  of "S16": safe_parse[int16](integer_literal.asl)
  of "S32": safe_parse[int32](integer_literal.asl)
  of "S64": safe_parse[int64](integer_literal.asl)
  of "U8": safe_parse[uint8](integer_literal.asl)
  of "U16": safe_parse[uint16](integer_literal.asl)
  of "U32": safe_parse[uint32](integer_literal.asl)
  of "U64": safe_parse[uint64](integer_literal.asl)
  else: err("{integer_literal.location} integer can not be converted to module `{module.name.asl}`")

proc validate(module: TypedNativeModule, float_literal: FloatLiteral): Result[
    void, string] =
  case module.name.asl:
  of "F32": safe_parse[float32](float_literal.asl)
  of "F64": safe_parse[float64](float_literal.asl)
  else: err("{float_literal.location} float can not be converted to module `{module.name.asl}`")

proc validate(module: TypedNativeModule,
    string_literal: StringLiteral): Result[void, string] =
  case module.name.asl:
  of "String": ok()
  else: err("{string_literal.location} string can not be converted to module `{module.name.asl}`")

proc validate*(module: TypedNativeModule, literal: Literal): Result[void, string] =
  case literal.kind:
  of LK_INTEGER:
    let integer_literal = ? literal.integer_literal
    validate(module, integer_literal)
  of LK_FLOAT:
    let float_literal = ? literal.float_literal
    validate(module, float_literal)
  of LK_STRING:
    let string_literal = ? literal.string_literal
    validate(module, string_literal)

proc assign_type(file: parser.File, module: NativeModule, id: uint64): Result[
    TypedNativeModule, string] =
  var typed_generics: seq[(Generic, TypedGeneric)]
  for index, generic in module.generics:
    let typed_generic = ? assign_type(file, module, generic, index.uint64)
    typed_generics.add((generic, typed_generic))

  var typed_structs: seq[TypedStruct]
  for index, struct in module.structs:
    let typed_struct = ? assign_type(file, module, struct, index.uint64)
    typed_structs.add(typed_struct)

  var typed_functions: seq[TypedNativeFunction]
  for function in module.functions:
    let typed_function = ? assign_type(file, module, function)
    typed_functions.add(typed_function)
  ok(new_typed_native_module(module.name, typed_generics, typed_structs,
      typed_functions, id))

type TypedFile* = ref object of RootObj
  name: string
  indent: int
  maybe_start_def: Option[TypedFunctionDefinition]
  native_modules: seq[TypedNativeModule]
  native_modules_map: Table[NativeModule, TypedNativeModule]
  user_modules: seq[TypedUserModule]
  user_modules_map: Table[UserModule, TypedUserModule]
  functions: seq[TypedFunction]

proc new_typed_file(name: string, indent: int, maybe_start_def: Option[
    TypedFunctionDefinition], native_modules: seq[(NativeModule,
        TypedNativeModule)], user_modules: seq[TypedUserModule],
    user_modules_map: Table[UserModule, TypedUserModule], functions: seq[
    TypedFunction]): TypedFile =
  var native_modules_map: Table[NativeModule, TypedNativeModule]
  var typed_native_modules: seq[TypedNativeModule]
  for (native_module, typed_native_module) in native_modules:
    native_modules_map[native_module] = typed_native_module
    typed_native_modules.add(typed_native_module)
  TypedFile(name: name, indent: indent, maybe_start_def: maybe_start_def,
      native_modules: typed_native_modules,
      native_modules_map: native_modules_map,
      user_modules: user_modules,
      user_modules_map: user_modules_map, functions: functions)

proc path*(file: TypedFile): string = file.name
proc indent*(file: TypedFile): int = file.indent
proc start_def*(file: TypedFile): Result[TypedFunctionDefinition, string] =
  if file.maybe_start_def.is_some:
    ok(file.maybe_start_def.get)
  else:
    err(fmt"{file.path} failed to find `start` function")
proc native_modules*(file: TypedFile): seq[
    TypedNativeModule] = file.native_modules
proc user_modules*(file: TypedFile): seq[TypedUserModule] = file.user_modules
proc functions*(file: TypedFile): seq[TypedFunction] = file.functions
proc find_module*(file: TypedFile, module: UserModule): Result[
    TypedUserModule, string] =
  if module in file.user_modules_map:
    ok(file.user_modules_map[module])
  else:
    err("failed to find module `{module.name.asl}`")

proc find_module*(file: TypedFile, module: NativeModule): Result[
    TypedNativeModule, string] =
  if module in file.native_modules_map:
    ok(file.native_modules_map[module])
  else:
    err("failed to find native module `{module.name.asl}`")

proc assign_type*(file: parser.File): Result[TypedFile, string] =
  var native_modules: seq[(NativeModule, TypedNativeModule)]
  for index, module in file.native_modules:
    let typed_module = ? assign_type(file, module, index.uint64)
    native_modules.add((module, typed_module))

  var module_graph: Table[UserModule, HashSet[UserModule]]
  var modules_map: Table[UserModule, TypedUserModule]
  let offset = file.native_modules.len
  for index, module in file.user_modules:
    let typed_module = ? assign_type(file, module, (offset + index).uint64)
    let module_deps = typed_module.module_deps
    module_graph[module] = module_deps
    modules_map[module] = typed_module

  # NOTE: Cycle detection and Topologically sort based on module dependencies.
  let maybe_module_order = detect_cycle(module_graph)
  if maybe_module_order.is_err:
    let cycle = maybe_module_order.get
    var message = @["CYCLIC DEPENDENCIES ENCOUNTERED"]
    for module in cycle:
      message.add(fmt"{module.location} {module.name.asl}")
    return err(message.join("\n"))

  let module_resolution_order = maybe_module_order.get
  var typed_modules: seq[TypedUserModule]
  for module in module_resolution_order:
    typed_modules.add(modules_map[module])

  var maybe_start_def: Option[TypedFunctionDefinition]
  let maybe_start_def_def = ? make_typed_function_def(file, "start", @[(
      "U8", "seed")], "U8")

  var typed_functions: seq[TypedFunction]
  for function in file.functions:
    let typed_function = ? assign_type(file, function)
    typed_functions.add(typed_function)
    if typed_function.def == maybe_start_def_def:
      maybe_start_def = some(typed_function.def)

  if maybe_start_def.is_none:
    return err(fmt"{file.path} failed to find `start` function")

  ok(new_typed_file(file.path, file.indent, maybe_start_def,
      native_modules, typed_modules, modules_map, typed_functions))
