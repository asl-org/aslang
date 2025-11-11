import results, strformat, sequtils, tables, strutils

import deps_analyzer

type ResolvedConcreteModuleRef* = ref object of RootObj
  module*: Module

proc new_resolved_concrete_module_ref*(
  module: Module): ResolvedConcreteModuleRef =
  ResolvedConcreteModuleRef(module: module)

proc is_struct*(module_ref: ResolvedConcreteModuleRef): bool =
  module_ref.module.is_struct

proc `==`*(self: ResolvedConcreteModuleRef,
    other: ResolvedConcreteModuleRef): bool =
  self.module.hash == other.module.hash

proc asl*(module_ref: ResolvedConcreteModuleRef): string =
  module_ref.module.name.asl

type ResolvedGenericModuleRef* = ref object of RootObj
  module*: UserModule
  generic*: Generic

proc new_resolved_generic_module_ref*(module: UserModule,
    generic: Generic): ResolvedGenericModuleRef =
  ResolvedGenericModuleRef(module: module, generic: generic)

proc is_struct*(module_ref: ResolvedGenericModuleRef): bool =
  module_ref.module.is_struct

proc `==`*(self: ResolvedGenericModuleRef,
    other: ResolvedGenericModuleRef): bool =
  self.module.hash == other.module.hash and self.generic.hash ==
      other.generic.hash

proc asl*(module_ref: ResolvedGenericModuleRef): string =
  module_ref.generic.name.asl

type
  ResolvedModuleRefKind* = enum
    RATK_CONCRETE, RATK_GENERIC, RATK_NESTED
  ResolvedModuleRef* = ref object of RootObj
    module_ref: ModuleRef
    concrete_map*: Table[Generic, ResolvedModuleRef]
    case kind*: ResolvedModuleRefKind
    of RATK_CONCRETE: concrete_type*: ResolvedConcreteModuleRef
    of RATK_GENERIC: generic_type*: ResolvedGenericModuleRef
    of RATK_NESTED:
      module*: UserModule
      children*: seq[ResolvedModuleRef]

proc new_resolved_module_ref*(module_ref: ModuleRef,
    concrete_type: ResolvedConcreteModuleRef): ResolvedModuleRef =
  ResolvedModuleRef(kind: RATK_CONCRETE, module_ref: module_ref,
      concrete_type: concrete_type)

proc new_resolved_module_ref*(module_ref: ModuleRef,
    generic_type: ResolvedGenericModuleRef): ResolvedModuleRef =
  ResolvedModuleRef(kind: RATK_GENERIC, module_ref: module_ref,
      generic_type: generic_type)

proc new_resolved_module_ref*(module_ref: ModuleRef, module: UserModule,
    children: seq[ResolvedModuleRef], concrete_map: Table[Generic,
        ResolvedModuleRef]): ResolvedModuleRef =
  ResolvedModuleRef(kind: RATK_NESTED, module_ref: module_ref,
      module: module, children: children, concrete_map: concrete_map)

proc concrete_module_ref*(module_ref: ResolvedModuleRef,
    concrete_map: Table[Generic, ResolvedModuleRef]): ResolvedModuleRef =
  case module_ref.kind:
  of RATK_CONCRETE: module_ref
  of RATK_GENERIC:
    if module_ref.generic_type.generic in concrete_map:
      concrete_map[module_ref.generic_type.generic]
    else:
      module_ref
  of RATK_NESTED:
    var children: seq[ResolvedModuleRef]
    var new_concrete_map: Table[Generic, ResolvedModuleRef]
    for (generic, child) in zip(module_ref.module.generics,
        module_ref.children):
      new_concrete_map[generic] = child.concrete_module_ref(concrete_map)
      children.add(new_concrete_map[generic])
    new_resolved_module_ref(module_ref.module_ref, module_ref.module,
        children, new_concrete_map)

proc location*(module_ref: ResolvedModuleRef): Location =
  module_ref.module_ref.location

proc user_module*(module_ref: ResolvedModuleRef): Result[UserModule, string] =
  case module_ref.kind:
  of RATK_CONCRETE:
    case module_ref.concrete_type.module.kind:
    of MK_NATIVE: err(fmt"{module_ref.location} expected user module ref but found native module")
    of MK_USER: module_ref.concrete_type.module.user_module
  of RATK_GENERIC: ok(module_ref.generic_type.module)
  of RATK_NESTED: ok(module_ref.module)

proc native_module*(module_ref: ResolvedModuleRef): Result[NativeModule, string] =
  case module_ref.kind:
  of RATK_CONCRETE:
    case module_ref.concrete_type.module.kind:
    of MK_NATIVE: module_ref.concrete_type.module.native_module
    of MK_USER: err(fmt"{module_ref.location} expected native module ref but found user module")
  of RATK_GENERIC: err(fmt"{module_ref.location} expected native module ref but found user module")
  of RATK_NESTED: err(fmt"{module_ref.location} expected native module ref but found user module")

proc is_struct*(module_ref: ResolvedModuleRef): bool =
  case module_ref.kind:
  of RATK_CONCRETE: module_ref.concrete_type.is_struct
  of RATK_GENERIC: module_ref.generic_type.is_struct
  of RATK_NESTED: module_ref.module.is_struct

proc `==`*(self: ResolvedModuleRef, other: ResolvedModuleRef): bool =
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

proc asl*(module_ref: ResolvedModuleRef): string =
  case module_ref.kind:
  of RATK_CONCRETE: module_ref.concrete_type.asl
  of RATK_GENERIC: module_ref.generic_type.asl
  of RATK_NESTED:
    let module = module_ref.module.name.asl
    var children: seq[string]
    for child in module_ref.children:
      children.add(child.asl)
    let children_str = children.join(", ")
    fmt"{module}[{children_str}]"

type ResolvedArgumentDefinition* = ref object of RootObj
  name: Identifier
  module_ref*: ResolvedModuleRef
  location: Location

proc new_resolved_argument_definition*(name: Identifier,
    module_ref: ResolvedModuleRef, location: Location): ResolvedArgumentDefinition =
  ResolvedArgumentDefinition(name: name, module_ref: module_ref,
      location: location)

proc concrete_argument_definition*(def: ResolvedArgumentDefinition,
    concrete_map: Table[Generic,
    ResolvedModuleRef]): ResolvedArgumentDefinition =
  new_resolved_argument_definition(def.name,
      def.module_ref.concrete_module_ref(concrete_map), def.location)

proc asl*(def: ResolvedArgumentDefinition): string =
  fmt"{def.module_ref.asl} {def.name.asl}"

type ResolvedFunctionDefinition* = ref object of RootObj
  def: FunctionDefinition
  args*: seq[ResolvedArgumentDefinition]
  returns*: ResolvedModuleRef

proc new_resolved_function_definition*(def: FunctionDefinition, args: seq[
    ResolvedArgumentDefinition],
    returns: ResolvedModuleRef): ResolvedFunctionDefinition =
  ResolvedFunctionDefinition(def: def, args: args, returns: returns)

proc concrete_function_definition*(def: ResolvedFunctionDefinition,
    module_ref: ResolvedModuleRef): ResolvedFunctionDefinition =
  var concrete_args: seq[ResolvedArgumentDefinition]
  for arg in def.args:
    let concrete_arg = arg.concrete_argument_definition(module_ref.concrete_map)
    concrete_args.add(concrete_arg)
  let concrete_return_type = def.returns.concrete_module_ref(
      module_ref.concrete_map)
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
    ResolvedModuleRef]): Result[ResolvedStruct, string] =
  var fields: seq[ResolvedArgumentDefinition]
  for field in struct.fields:
    fields.add(field.concrete_argument_definition(concrete_map))
  new_resolved_struct(struct.struct, fields)

type
  ResolvedLiteralKind* = enum
    RLK_INTEGER, RLK_FLOAT, RLK_STRING
  ResolvedLiteral* = ref object of RootObj
    module_ref: ResolvedModuleRef
    case kind: ResolvedLiteralKind
    of RLK_INTEGER: integer_literal: IntegerLiteral
    of RLK_FLOAT: float_literal: FloatLiteral
    of RLK_STRING: string_literal: StringLiteral

proc new_resolved_literal*(integer_literal: IntegerLiteral,
    module_ref: ResolvedModuleRef): ResolvedLiteral =
  ResolvedLiteral(kind: RLK_INTEGER, integer_literal: integer_literal,
      module_ref: module_ref)

proc new_resolved_literal*(float_literal: FloatLiteral,
    module_ref: ResolvedModuleRef): ResolvedLiteral =
  ResolvedLiteral(kind: RLK_FLOAT, float_literal: float_literal,
      module_ref: module_ref)

proc new_resolved_literal*(string_literal: StringLiteral,
    module_ref: ResolvedModuleRef): ResolvedLiteral =
  ResolvedLiteral(kind: RLK_STRING, string_literal: string_literal,
      module_ref: module_ref)

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
    of RFRK_MODULE: module_ref*: ResolvedModuleRef

proc new_resolved_function_ref*(fnref: FunctionRef, defs: seq[
    FunctionDefinition]): ResolvedFunctionRef =
  ResolvedFunctionRef(kind: RFRK_LOCAL, fnref: fnref, defs: defs)

proc new_resolved_function_ref*(fnref: FunctionRef,
    module_ref: ResolvedModuleRef, defs: seq[
        FunctionDefinition]): ResolvedFunctionRef =
  ResolvedFunctionRef(kind: RFRK_MODULE, fnref: fnref, module_ref: module_ref, defs: defs)

proc asl*(fnref: ResolvedFunctionRef): string =
  case fnref.kind:
  of RFRK_LOCAL: ""
  of RFRK_MODULE: fnref.module_ref.asl

type ResolvedFunctionCall* = ref object of RootObj
  fncall: FunctionCall
  fnref: ResolvedFunctionRef
  def: ResolvedFunctionDefinition
  args: seq[ResolvedArgument]

proc new_resolved_function_call*(fncall: FunctionCall,
    fnref: ResolvedFunctionRef, def: ResolvedFunctionDefinition, args: seq[
    ResolvedArgument]): ResolvedFunctionCall =
  ResolvedFunctionCall(fncall: fncall, fnref: fnref, def: def, args: args)

proc return_type*(fncall: ResolvedFunctionCall): ResolvedModuleRef =
  fncall.def.returns

type ResolvedLiteralInit* = ref object of RootObj
  init: LiteralInit
  literal: ResolvedLiteral

proc new_resolved_literal_init*(init: LiteralInit,
    literal: ResolvedLiteral): ResolvedLiteralInit =
  ResolvedLiteralInit(init: init, literal: literal)

proc return_type*(init: ResolvedLiteralInit): ResolvedModuleRef =
  init.literal.module_ref

type ResolvedStructRef* = ref object of RootObj
  struct_ref: StructRef
  module_ref: ResolvedModuleRef
  struct*: ResolvedStruct

proc new_resolved_struct_ref*(struct_ref: StructRef,
    module_ref: ResolvedModuleRef, struct: ResolvedStruct): ResolvedStructRef =
  ResolvedStructRef(struct_ref: struct_ref, module_ref: module_ref,
      struct: struct)

type ResolvedStructInit* = ref object of RootObj
  init: StructInit
  struct_ref: ResolvedStructRef
  fields: seq[ResolvedArgument]

proc new_resolved_struct_init*(init: StructInit, struct_ref: ResolvedStructRef,
    fields: seq[ResolvedArgument]): ResolvedStructInit =
  ResolvedStructInit(init: init, struct_ref: struct_ref, fields: fields)

proc return_type*(init: ResolvedStructInit): ResolvedModuleRef =
  init.struct_ref.module_ref

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

proc return_type*(init: ResolvedInitializer): ResolvedModuleRef =
  case init.kind:
  of RIK_LITERAL: init.literal.return_type
  of RIK_STRUCT: init.struct.return_type

type ResolvedStructGet* = ref object of RootObj
  struct_get: StructGet
  module_ref: ResolvedModuleRef
  field: ResolvedArgumentDefinition

proc new_resolved_struct_get*(struct_get: StructGet,
    module_ref: ResolvedModuleRef, field: ResolvedArgumentDefinition): ResolvedStructGet =
  ResolvedStructGet(struct_get: struct_get, module_ref: module_ref, field: field)

proc return_type*(struct_get: ResolvedStructGet): ResolvedModuleRef =
  struct_get.field.module_ref

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

type
  ResolvedExpressionKind* = enum
    REK_MATCH, REK_FNCALL, REK_INIT, REK_STRUCT_GET, REK_VARIABLE
  ResolvedExpression* = ref object of RootObj
    expression: Expression
    case kind: ResolvedExpressionKind
    of REK_MATCH: match: ResolvedMatch
    of REK_FNCALL: fncall: ResolvedFunctionCall
    of REK_INIT: init: ResolvedInitializer
    of REK_STRUCT_GET: struct_get: ResolvedStructGet
    of REK_VARIABLE: variable: ResolvedArgumentDefinition
  ResolvedStatement* = ref object of RootObj
    statement: Statement
    arg*: ResolvedArgumentDefinition
    expression: ResolvedExpression
  ResolvedCase* = ref object of RootObj
    case_block: Case
    def: ResolvedCaseDefinition
    statements: seq[ResolvedStatement]
  ResolvedElse* = ref object of RootObj
    else_block: Else
    statements: seq[ResolvedStatement]
  ResolvedMatchKind* = enum
    RMK_CASE_ONLY, RMK_COMPLETE
  ResolvedMatch* = ref object of RootObj
    match: Match
    case_blocks: seq[ResolvedCase]
    case kind: ResolvedMatchKind
    of RMK_CASE_ONLY: discard
    of RMK_COMPLETE: else_block: ResolvedElse

proc new_resolved_expression*(expression: Expression,
    match: ResolvedMatch): ResolvedExpression =
  ResolvedExpression(kind: REK_MATCH, expression: expression, match: match)

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

proc return_type(match: ResolvedMatch): ResolvedModuleRef

proc return_type*(expression: ResolvedExpression): ResolvedModuleRef =
  case expression.kind:
  of REK_MATCH: expression.match.return_type
  of REK_FNCALL: expression.fncall.return_type
  of REK_INIT: expression.init.return_type
  of REK_STRUCT_GET: expression.struct_get.return_type
  of REK_VARIABLE: expression.variable.module_ref

proc new_resolved_statement*(statement: Statement,
    arg: ResolvedArgumentDefinition,
    expression: ResolvedExpression): ResolvedStatement =
  ResolvedStatement(statement: statement, arg: arg, expression: expression)

proc return_type*(statement: ResolvedStatement): ResolvedModuleRef =
  statement.expression.return_type

proc new_resolved_case*(case_block: Case, def: ResolvedCaseDefinition,
    statements: seq[ResolvedStatement]): ResolvedCase =
  ResolvedCase(case_block: case_block, def: def, statements: statements)

proc return_type*(case_block: ResolvedCase): ResolvedModuleRef =
  case_block.statements[^1].return_type

proc location*(case_block: ResolvedCase): Location =
  case_block.case_block.location

proc new_resolved_else*(else_block: Else, statements: seq[
    ResolvedStatement]): ResolvedElse =
  ResolvedElse(else_block: else_block, statements: statements)

proc return_type*(else_block: ResolvedElse): ResolvedModuleRef =
  else_block.statements[^1].return_type

proc location*(else_block: ResolvedElse): Location =
  else_block.else_block.location

proc new_resolved_match*(match: Match, case_blocks: seq[
    ResolvedCase]): ResolvedMatch =
  ResolvedMatch(kind: RMK_CASE_ONLY, match: match, case_blocks: case_blocks)

proc new_resolved_match*(match: Match, case_blocks: seq[ResolvedCase],
    else_block: ResolvedElse): ResolvedMatch =
  ResolvedMatch(kind: RMK_COMPLETE, match: match, case_blocks: case_blocks,
      else_block: else_block)

proc return_type(match: ResolvedMatch): ResolvedModuleRef =
  match.case_blocks[0].return_type

proc arg*(match: ResolvedMatch): ResolvedArgumentDefinition =
  new_resolved_argument_definition(match.match.def.arg, match.case_blocks[
      0].return_type, match.match.def.arg.location)

# type
#   ResolvedFunctionStepKind* = enum
#     RFSK_MATCH, RFSK_STATEMENT
#   ResolvedFunctionStep* = ref object of RootObj
#     step: FunctionStep
#     case kind: ResolvedFunctionStepKind
#     of RFSK_STATEMENT: statement: ResolvedStatement
#     of RFSK_MATCH: match: ResolvedMatch

# proc new_resolved_function_step*(step: FunctionStep,
#     statement: ResolvedStatement): ResolvedFunctionStep =
#   ResolvedFunctionStep(kind: RFSK_STATEMENT, step: step, statement: statement)

# proc new_resolved_function_step*(step: FunctionStep,
#     match: ResolvedMatch): ResolvedFunctionStep =
#   ResolvedFunctionStep(kind: RFSK_MATCH, step: step, match: match)

# proc arg*(step: ResolvedFunctionStep): ResolvedArgumentDefinition =
#   case step.kind:
#   of RFSK_MATCH: step.match.arg
#   of RFSK_STATEMENT: step.statement.arg

type ResolvedFunction* = ref object of RootObj
  function: Function
  def: ResolvedFunctionDefinition
  steps: seq[ResolvedStatement]

proc new_resolved_function*(function: Function,
    def: ResolvedFunctionDefinition, steps: seq[
        ResolvedStatement]): ResolvedFunction =
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

