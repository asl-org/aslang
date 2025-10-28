import results, strformat, sequtils, tables, strutils

import deps_analyzer

type ResolvedConcreteArgumentType* = ref object of RootObj
  module*: Module

proc new_resolved_concrete_argument_type*(
  module: Module): ResolvedConcreteArgumentType =
  ResolvedConcreteArgumentType(module: module)

proc is_struct*(argtype: ResolvedConcreteArgumentType): bool =
  argtype.module.is_struct

proc `==`*(self: ResolvedConcreteArgumentType,
    other: ResolvedConcreteArgumentType): bool =
  self.module.hash == other.module.hash

proc asl*(argtype: ResolvedConcreteArgumentType): string =
  argtype.module.name.asl

type ResolvedGenericArgumentType* = ref object of RootObj
  module*: UserModule
  generic*: Generic

proc new_resolved_generic_argument_type*(module: UserModule,
    generic: Generic): ResolvedGenericArgumentType =
  ResolvedGenericArgumentType(module: module, generic: generic)

proc is_struct*(argtype: ResolvedGenericArgumentType): bool =
  argtype.module.is_struct

proc `==`*(self: ResolvedGenericArgumentType,
    other: ResolvedGenericArgumentType): bool =
  self.module.hash == other.module.hash and self.generic.hash ==
      other.generic.hash

proc asl*(argtype: ResolvedGenericArgumentType): string =
  argtype.generic.name.asl

type
  ResolvedArgumentTypeKind* = enum
    RATK_CONCRETE, RATK_GENERIC, RATK_NESTED
  ResolvedArgumentType* = ref object of RootObj
    argtype: ArgumentType
    concrete_map*: Table[Generic, ResolvedArgumentType]
    case kind*: ResolvedArgumentTypeKind
    of RATK_CONCRETE: concrete_type*: ResolvedConcreteArgumentType
    of RATK_GENERIC: generic_type*: ResolvedGenericArgumentType
    of RATK_NESTED:
      module*: UserModule
      children*: seq[ResolvedArgumentType]

proc new_resolved_argument_type*(argtype: ArgumentType,
    concrete_type: ResolvedConcreteArgumentType): ResolvedArgumentType =
  ResolvedArgumentType(kind: RATK_CONCRETE, argtype: argtype,
      concrete_type: concrete_type)

proc new_resolved_argument_type*(argtype: ArgumentType,
    generic_type: ResolvedGenericArgumentType): ResolvedArgumentType =
  ResolvedArgumentType(kind: RATK_GENERIC, argtype: argtype,
      generic_type: generic_type)

proc new_resolved_argument_type*(argtype: ArgumentType, module: UserModule,
    children: seq[ResolvedArgumentType], concrete_map: Table[Generic,
        ResolvedArgumentType]): ResolvedArgumentType =
  ResolvedArgumentType(kind: RATK_NESTED, argtype: argtype, module: module,
      children: children, concrete_map: concrete_map)

proc concrete_argument_type*(argtype: ResolvedArgumentType, concrete_map: Table[
    Generic, ResolvedArgumentType]): ResolvedArgumentType =
  case argtype.kind:
  of RATK_CONCRETE: argtype
  of RATK_GENERIC:
    if argtype.generic_type.generic in concrete_map:
      concrete_map[argtype.generic_type.generic]
    else:
      argtype
  of RATK_NESTED:
    var children: seq[ResolvedArgumentType]
    var new_concrete_map: Table[Generic, ResolvedArgumentType]
    for (generic, child) in zip(argtype.module.generics, argtype.children):
      new_concrete_map[generic] = child.concrete_argument_type(concrete_map)
      children.add(new_concrete_map[generic])
    new_resolved_argument_type(argtype.argtype, argtype.module, children, new_concrete_map)

proc location*(argtype: ResolvedArgumentType): Location =
  argtype.argtype.location

proc user_module*(argtype: ResolvedArgumentType): Result[UserModule, string] =
  case argtype.kind:
  of RATK_CONCRETE:
    case argtype.concrete_type.module.kind:
    of MK_NATIVE: err(fmt"{argtype.location} expected user defined argument type but found native type")
    of MK_USER: argtype.concrete_type.module.user_module
  of RATK_GENERIC: ok(argtype.generic_type.module)
  of RATK_NESTED: ok(argtype.module)

proc native_module*(argtype: ResolvedArgumentType): Result[NativeModule, string] =
  case argtype.kind:
  of RATK_CONCRETE:
    case argtype.concrete_type.module.kind:
    of MK_NATIVE: argtype.concrete_type.module.native_module
    of MK_USER: err(fmt"{argtype.location} expected native argument type but found user defined type")
  of RATK_GENERIC: err(fmt"{argtype.location} expected native argument type but found user defined type")
  of RATK_NESTED: err(fmt"{argtype.location} expected native argument type but found user defined type")

proc is_struct*(argtype: ResolvedArgumentType): bool =
  case argtype.kind:
  of RATK_CONCRETE: argtype.concrete_type.is_struct
  of RATK_GENERIC: argtype.generic_type.is_struct
  of RATK_NESTED: argtype.module.is_struct

proc `==`*(self: ResolvedArgumentType, other: ResolvedArgumentType): bool =
  if self.kind != other.kind:
    return false
  case self.kind:
  of RATK_CONCRETE:
    self.concrete_type == other.concrete_type
  of RATK_GENERIC:
    self.generic_type == other.generic_type
  of RATK_NESTED:
    if self.module.hash != other.module.hash: return false
    if self.children.len != other.children.len: return false
    for (self_child, other_child) in zip(self.children, other.children):
      if self_child != other_child:
        return false
    return true

proc asl*(argtype: ResolvedArgumentType): string =
  case argtype.kind:
  of RATK_CONCRETE: argtype.concrete_type.asl
  of RATK_GENERIC: argtype.generic_type.asl
  of RATK_NESTED:
    let module = argtype.module.name.asl
    var children: seq[string]
    for child in argtype.children:
      children.add(child.asl)
    let children_str = children.join(", ")
    fmt"{module}[{children_str}]"

type ResolvedArgumentDefinition* = ref object of RootObj
  name: Identifier
  argtype*: ResolvedArgumentType
  location: Location

proc new_resolved_argument_definition*(name: Identifier,
    argtype: ResolvedArgumentType, location: Location): ResolvedArgumentDefinition =
  ResolvedArgumentDefinition(name: name, argtype: argtype, location: location)

proc concrete_argument_definition*(def: ResolvedArgumentDefinition,
    concrete_map: Table[Generic,
    ResolvedArgumentType]): ResolvedArgumentDefinition =
  new_resolved_argument_definition(def.name, def.argtype.concrete_argument_type(
      concrete_map), def.location)

proc asl*(def: ResolvedArgumentDefinition): string =
  fmt"{def.argtype.asl} {def.name.asl}"

type ResolvedFunctionDefinition* = ref object of RootObj
  def: FunctionDefinition
  args*: seq[ResolvedArgumentDefinition]
  returns*: ResolvedArgumentType

proc new_resolved_function_definition*(def: FunctionDefinition, args: seq[
    ResolvedArgumentDefinition],
    returns: ResolvedArgumentType): ResolvedFunctionDefinition =
  ResolvedFunctionDefinition(def: def, args: args, returns: returns)

proc concrete_function_definition*(def: ResolvedFunctionDefinition,
    argtype: ResolvedArgumentType): ResolvedFunctionDefinition =
  var concrete_args: seq[ResolvedArgumentDefinition]
  for arg in def.args:
    let concrete_arg = arg.concrete_argument_definition(argtype.concrete_map)
    concrete_args.add(concrete_arg)
  let concrete_return_type = def.returns.concrete_argument_type(
      argtype.concrete_map)
  new_resolved_function_definition(def.def, concrete_args, concrete_return_type)

proc asl*(def: ResolvedFunctionDefinition): string =
  let name = def.def.name
  let args_str = def.args.map_it(it.asl).join(", ")
  fmt"fn {name.asl}({args_str}): {def.returns.asl}"

type ResolvedGeneric* = ref object of RootObj
  generic: Generic
  defs: seq[ResolvedFunctionDefinition]

proc new_resolved_generic*(generic: Generic, defs: seq[
    ResolvedFunctionDefinition]): ResolvedGeneric =
  ResolvedGeneric(generic: generic, defs: defs)

type ResolvedStruct* = ref object of RootObj
  struct: Struct
  fields*: seq[ResolvedArgumentDefinition]
  fields_map: Table[Identifier, int]

proc new_resolved_struct*(struct: Struct, fields: seq[
    ResolvedArgumentDefinition]): Result[ResolvedStruct, string] =
  var fields_map: Table[Identifier, int]
  for index, field in fields.pairs:
    if field.name in fields_map:
      let predefined_location = fields[fields_map[field.name]].location
      return err(fmt"{struct.location} field `{field.name.asl}` is already defined at {predefined_location}")
    fields_map[field.name] = index
  ok(ResolvedStruct(struct: struct, fields: fields, fields_map: fields_map))

proc name*(struct: ResolvedStruct): Result[Identifier, string] =
  struct.struct.name

proc find_field_id*(struct: ResolvedStruct, name: Identifier): Result[int, string] =
  if name notin struct.fields_map:
    let struct_name = ? struct.name
    return err(fmt"{name.location} field `{name.asl}` does not exist in `{struct_name.asl}`")
  ok(struct.fields_map[name])

proc concrete_struct*(struct: ResolvedStruct, concrete_map: Table[Generic,
    ResolvedArgumentType]): Result[ResolvedStruct, string] =
  var fields: seq[ResolvedArgumentDefinition]
  for field in struct.fields:
    fields.add(field.concrete_argument_definition(concrete_map))
  new_resolved_struct(struct.struct, fields)

type
  ResolvedLiteralKind* = enum
    RLK_INTEGER, RLK_FLOAT, RLK_STRING
  ResolvedLiteral* = ref object of RootObj
    argtype: ResolvedArgumentType
    case kind: ResolvedLiteralKind
    of RLK_INTEGER: integer_literal: IntegerLiteral
    of RLK_FLOAT: float_literal: FloatLiteral
    of RLK_STRING: string_literal: StringLiteral

proc new_resolved_literal*(integer_literal: IntegerLiteral,
    argtype: ResolvedArgumentType): ResolvedLiteral =
  ResolvedLiteral(kind: RLK_INTEGER, integer_literal: integer_literal,
      argtype: argtype)

proc new_resolved_literal*(float_literal: FloatLiteral,
    argtype: ResolvedArgumentType): ResolvedLiteral =
  ResolvedLiteral(kind: RLK_FLOAT, float_literal: float_literal,
      argtype: argtype)

proc new_resolved_literal*(string_literal: StringLiteral,
    argtype: ResolvedArgumentType): ResolvedLiteral =
  ResolvedLiteral(kind: RLK_STRING, string_literal: string_literal,
      argtype: argtype)

type
  ResolvedArgumentKind* = enum
    RAK_LITERAL, RAK_VARIABLE
  ResolvedArgument* = ref object of RootObj
    arg: Argument
    case kind: ResolvedArgumentKind
    of RAK_LITERAL: literal: ResolvedLiteral
    of RAK_VARIABLE: variable: ResolvedArgumentDefinition

proc new_resolved_argument*(arg: Argument,
    literal: ResolvedLiteral): ResolvedArgument =
  ResolvedArgument(kind: RAK_LITERAL, arg: arg, literal: literal)

proc new_resolved_argument*(arg: Argument,
    variable: ResolvedArgumentDefinition): ResolvedArgument =
  ResolvedArgument(kind: RAK_VARIABLE, arg: arg, variable: variable)

type
  ResolvedFunctionRefKind* = enum
    RFRK_LOCAL, RFRK_MODULE
  ResolvedFunctionRef* = ref object of RootObj
    fnref: FunctionRef
    defs*: seq[FunctionDefinition]
    case kind*: ResolvedFunctionRefKind
    of RFRK_LOCAL: discard
    of RFRK_MODULE: argtype*: ResolvedArgumentType

proc new_resolved_function_ref*(fnref: FunctionRef, defs: seq[
    FunctionDefinition]): ResolvedFunctionRef =
  ResolvedFunctionRef(kind: RFRK_LOCAL, fnref: fnref, defs: defs)

proc new_resolved_function_ref*(fnref: FunctionRef,
    argtype: ResolvedArgumentType, defs: seq[
        FunctionDefinition]): ResolvedFunctionRef =
  ResolvedFunctionRef(kind: RFRK_MODULE, fnref: fnref, argtype: argtype, defs: defs)

proc asl*(fnref: ResolvedFunctionRef): string =
  case fnref.kind:
  of RFRK_LOCAL: ""
  of RFRK_MODULE: fnref.argtype.asl

type ResolvedFunctionCall* = ref object of RootObj
  fncall: FunctionCall
  fnref: ResolvedFunctionRef
  def: ResolvedFunctionDefinition
  args: seq[ResolvedArgument]

proc new_resolved_function_call*(fncall: FunctionCall,
    fnref: ResolvedFunctionRef, def: ResolvedFunctionDefinition, args: seq[
    ResolvedArgument]): ResolvedFunctionCall =
  ResolvedFunctionCall(fncall: fncall, fnref: fnref, def: def, args: args)

proc return_type*(fncall: ResolvedFunctionCall): ResolvedArgumentType =
  fncall.def.returns

type ResolvedLiteralInit* = ref object of RootObj
  init: LiteralInit
  literal: ResolvedLiteral

proc new_resolved_literal_init*(init: LiteralInit,
    literal: ResolvedLiteral): ResolvedLiteralInit =
  ResolvedLiteralInit(init: init, literal: literal)

proc return_type*(init: ResolvedLiteralInit): ResolvedArgumentType =
  init.literal.argtype

type ResolvedStructRef* = ref object of RootObj
  struct_ref: StructRef
  argtype: ResolvedArgumentType
  struct*: ResolvedStruct

proc new_resolved_struct_ref*(struct_ref: StructRef,
    argtype: ResolvedArgumentType, struct: ResolvedStruct): ResolvedStructRef =
  ResolvedStructRef(struct_ref: struct_ref, argtype: argtype, struct: struct)

type ResolvedStructInit* = ref object of RootObj
  init: StructInit
  struct_ref: ResolvedStructRef
  fields: seq[ResolvedArgument]

proc new_resolved_struct_init*(init: StructInit, struct_ref: ResolvedStructRef,
    fields: seq[ResolvedArgument]): ResolvedStructInit =
  ResolvedStructInit(init: init, struct_ref: struct_ref, fields: fields)

proc return_type*(init: ResolvedStructInit): ResolvedArgumentType =
  init.struct_ref.argtype

type
  ResolvedInitializerKind* = enum
    RIK_LITERAL, RIK_STRUCT
  ResolvedInitializer* = ref object of RootObj
    init: Initializer
    case kind: ResolvedInitializerKind
    of RIK_LITERAL: literal: ResolvedLiteralInit
    of RIK_STRUCT: struct: ResolvedStructInit

proc new_resolved_initializer*(init: Initializer,
    literal: ResolvedLiteralInit): ResolvedInitializer =
  ResolvedInitializer(kind: RIK_LITERAL, init: init, literal: literal)

proc new_resolved_initializer*(init: Initializer,
    struct: ResolvedStructInit): ResolvedInitializer =
  ResolvedInitializer(kind: RIK_STRUCT, init: init, struct: struct)

proc return_type*(init: ResolvedInitializer): ResolvedArgumentType =
  case init.kind:
  of RIK_LITERAL: init.literal.return_type
  of RIK_STRUCT: init.struct.return_type

type ResolvedStructGet* = ref object of RootObj
  struct_get: StructGet
  argtype: ResolvedArgumentType
  field: ResolvedArgumentDefinition

proc new_resolved_struct_get*(struct_get: StructGet,
    argtype: ResolvedArgumentType, field: ResolvedArgumentDefinition): ResolvedStructGet =
  ResolvedStructGet(struct_get: struct_get, argtype: argtype, field: field)

proc return_type*(struct_get: ResolvedStructGet): ResolvedArgumentType =
  struct_get.field.argtype

type
  ResolvedExpressionKind* = enum
    REK_FNCALL, REK_INIT, REK_STRUCT_GET, REK_VARIABLE
  ResolvedExpression* = ref object of RootObj
    expression: Expression
    case kind: ResolvedExpressionKind
    of REK_FNCALL: fncall: ResolvedFunctionCall
    of REK_INIT: init: ResolvedInitializer
    of REK_STRUCT_GET: struct_get: ResolvedStructGet
    of REK_VARIABLE: variable: ResolvedArgumentDefinition

proc new_resolved_expression*(expression: Expression,
    fncall: ResolvedFunctionCall): ResolvedExpression =
  ResolvedExpression(kind: REK_FNCALL, expression: expression, fncall: fncall)

proc new_resolved_expression*(expression: Expression,
    init: ResolvedInitializer): ResolvedExpression =
  ResolvedExpression(kind: REK_INIT, expression: expression, init: init)

proc new_resolved_expression*(expression: Expression,
    struct_get: ResolvedStructGet): ResolvedExpression =
  ResolvedExpression(kind: REK_STRUCT_GET, expression: expression,
      struct_get: struct_get)

proc new_resolved_expression*(expression: Expression,
    variable: ResolvedArgumentDefinition): ResolvedExpression =
  ResolvedExpression(kind: REK_VARIABLE, expression: expression,
      variable: variable)

proc return_type*(expression: ResolvedExpression): ResolvedArgumentType =
  case expression.kind:
  of REK_FNCALL: expression.fncall.return_type
  of REK_INIT: expression.init.return_type
  of REK_STRUCT_GET: expression.struct_get.return_type
  of REK_VARIABLE: expression.variable.argtype

type ResolvedStatement* = ref object of RootObj
  statement: Statement
  arg*: ResolvedArgumentDefinition
  expression: ResolvedExpression

proc new_resolved_statement*(statement: Statement,
    arg: ResolvedArgumentDefinition,
    expression: ResolvedExpression): ResolvedStatement =
  ResolvedStatement(statement: statement, arg: arg, expression: expression)

proc return_type*(statement: ResolvedStatement): ResolvedArgumentType =
  statement.expression.return_type

type
  ResolvedStructPatternKind* = enum
    RSPK_DEFAULT, RSPK_NAMED
  ResolvedStructPattern* = ref object of RootObj
    pattern: StructPattern
    fields*: seq[ResolvedArgumentDefinition]
    case kind: ResolvedStructPatternKind
    of RSPK_DEFAULT: discard
    of RSPK_NAMED: struct: ResolvedStruct

proc new_resolved_struct_pattern*(pattern: StructPattern, fields: seq[
    ResolvedArgumentDefinition],
    struct: ResolvedStruct): ResolvedStructPattern =
  ResolvedStructPattern(kind: RSPK_NAMED, pattern: pattern, fields: fields,
      struct: struct)

type
  ResolvedCasePatternKind = enum
    RCPK_LITERAL, RCPK_STRUCT
  ResolvedCasePattern = ref object of RootObj
    pattern: CasePattern
    case kind: ResolvedCasePatternKind
    of RCPK_LITERAL: literal: ResolvedLiteral
    of RCPK_STRUCT: struct: ResolvedStructPattern

proc new_resolved_case_pattern*(pattern: CasePattern,
    literal: ResolvedLiteral): ResolvedCasePattern =
  ResolvedCasePattern(kind: RCPK_LITERAL, pattern: pattern, literal: literal)

proc new_resolved_case_pattern*(pattern: CasePattern,
    struct: ResolvedStructPattern): ResolvedCasePattern =
  ResolvedCasePattern(kind: RCPK_STRUCT, pattern: pattern, struct: struct)

type ResolvedCaseDefinition* = ref object of RootObj
  def: CaseDefinition
  pattern: ResolvedCasePattern

proc new_resolved_case_definition*(def: CaseDefinition,
    pattern: ResolvedCasePattern): ResolvedCaseDefinition =
  ResolvedCaseDefinition(def: def, pattern: pattern)

type ResolvedCase* = ref object of RootObj
  case_block: Case
  def: ResolvedCaseDefinition
  statements: seq[ResolvedStatement]

proc new_resolved_case*(case_block: Case, def: ResolvedCaseDefinition,
    statements: seq[ResolvedStatement]): ResolvedCase =
  ResolvedCase(case_block: case_block, def: def, statements: statements)

proc return_type*(case_block: ResolvedCase): ResolvedArgumentType =
  case_block.statements[^1].return_type

proc location*(case_block: ResolvedCase): Location =
  case_block.case_block.location

type ResolvedElse* = ref object of RootObj
  else_block: Else
  statements: seq[ResolvedStatement]

proc new_resolved_else*(else_block: Else, statements: seq[
    ResolvedStatement]): ResolvedElse =
  ResolvedElse(else_block: else_block, statements: statements)

proc return_type*(else_block: ResolvedElse): ResolvedArgumentType =
  else_block.statements[^1].return_type

proc location*(else_block: ResolvedElse): Location =
  else_block.else_block.location

type
  ResolvedMatchKind* = enum
    RMK_CASE_ONLY, RMK_COMPLETE
  ResolvedMatch* = ref object of RootObj
    match: Match
    case_blocks: seq[ResolvedCase]
    case kind: ResolvedMatchKind
    of RMK_CASE_ONLY: discard
    of RMK_COMPLETE: else_block: ResolvedElse

proc new_resolved_match*(match: Match, case_blocks: seq[
    ResolvedCase]): ResolvedMatch =
  ResolvedMatch(kind: RMK_CASE_ONLY, match: match, case_blocks: case_blocks)

proc new_resolved_match*(match: Match, case_blocks: seq[ResolvedCase],
    else_block: ResolvedElse): ResolvedMatch =
  ResolvedMatch(kind: RMK_COMPLETE, match: match, case_blocks: case_blocks,
      else_block: else_block)

proc arg*(match: ResolvedMatch): ResolvedArgumentDefinition =
  new_resolved_argument_definition(match.match.def.arg, match.case_blocks[
      0].return_type, match.match.def.arg.location)

type
  ResolvedFunctionStepKind* = enum
    RFSK_MATCH, RFSK_STATEMENT
  ResolvedFunctionStep* = ref object of RootObj
    step: FunctionStep
    case kind: ResolvedFunctionStepKind
    of RFSK_STATEMENT: statement: ResolvedStatement
    of RFSK_MATCH: match: ResolvedMatch

proc new_resolved_function_step*(step: FunctionStep,
    statement: ResolvedStatement): ResolvedFunctionStep =
  ResolvedFunctionStep(kind: RFSK_STATEMENT, step: step, statement: statement)

proc new_resolved_function_step*(step: FunctionStep,
    match: ResolvedMatch): ResolvedFunctionStep =
  ResolvedFunctionStep(kind: RFSK_MATCH, step: step, match: match)

proc arg*(step: ResolvedFunctionStep): ResolvedArgumentDefinition =
  case step.kind:
  of RFSK_MATCH: step.match.arg
  of RFSK_STATEMENT: step.statement.arg

type ResolvedFunction* = ref object of RootObj
  function: Function
  def: ResolvedFunctionDefinition
  steps: seq[ResolvedFunctionStep]

proc new_resolved_function*(function: Function,
    def: ResolvedFunctionDefinition, steps: seq[
        ResolvedFunctionStep]): ResolvedFunction =
  ResolvedFunction(function: function, def: def, steps: steps)

type ResolvedModule* = ref object of RootObj
  module: UserModule
  generics: seq[ResolvedGeneric]
  structs: seq[ResolvedStruct]
  functions: seq[ResolvedFunction]

proc new_resolved_module*(module: UserModule, generics: seq[
    ResolvedGeneric], structs: seq[ResolvedStruct], functions: seq[
        ResolvedFunction]): ResolvedModule =
  ResolvedModule(module: module, generics: generics, structs: structs,
      functions: functions)

type ResolvedFile* = ref object of RootObj
  file: ast.File
  modules: seq[ResolvedModule]
  functions: seq[ResolvedFunction]

proc new_resolved_file*(file: ast.File, modules: seq[ResolvedModule],
    functions: seq[ResolvedFunction]): ResolvedFile =
  ResolvedFile(file: file, modules: modules, functions: functions)

type FunctionScope* = ref object of RootObj
  mapping: Table[Identifier, ResolvedArgumentDefinition]

proc add*(scope: FunctionScope, arg: ResolvedArgumentDefinition): Result[
    FunctionScope, string] =
  if arg.name in scope.mapping:
    let predefined_location = scope.mapping[arg.name].location
    return err(fmt"{arg.location} [RE101] argument `{arg.name.asl}` is already defined at {predefined_location}")
  scope.mapping[arg.name] = arg
  ok(scope)

proc get*(scope: FunctionScope, name: Identifier): Result[
    ResolvedArgumentDefinition, string] =
  if name notin scope.mapping:
    return err(fmt"{name.location} [RE102] argument `{name.asl}` is not present in scope")
  ok(scope.mapping[name])

proc clone*(scope: FunctionScope): FunctionScope =
  var mapping: Table[Identifier, ResolvedArgumentDefinition]
  for key, value in scope.mapping.pairs:
    mapping[key] = value
  FunctionScope(mapping: mapping)

