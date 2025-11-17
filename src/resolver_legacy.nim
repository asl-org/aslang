import results, strformat, sequtils, tables, parseutils, strutils, sets

import resolver/deps_analyzer
export deps_analyzer

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


const DEBUG = false

proc resolve(file: ast.File, module: UserModule, generic: Generic,
    module_ref: ModuleRef): Result[ResolvedModuleRef, string] =
  if DEBUG:
    echo fmt"Resolving MODULE GENERIC ARG TYPE: {module_ref.location}"
  # NOTE: leaf argument types
  case module_ref.kind:
  of MRK_SIMPLE:
    # NOTE: generic module ref
    if module_ref.module == generic.name:
      let resolved_generic_type = new_resolved_generic_module_ref(module, generic)
      return ok(new_resolved_module_ref(module_ref, resolved_generic_type))
    # NOTE: concrete argument module ref
    let arg_module = ? file.find_module(module_ref.module)
    # NOTE: The module itself where generic is defined can not be used as argument to constraint
    if arg_module.hash == module.hash:
      return err(fmt"{module_ref.location} [RE103] module `{module_ref.module.asl}` can not be used as an argument in generic constraints")

    if arg_module.generics.len != 0:
      return err(fmt"{module_ref.location} [RE104] module `{module_ref.module.asl}` expects `{arg_module.generics.len}` generic types but `0` were given")

    let resolved_concrete_type = new_resolved_concrete_module_ref(arg_module)
    ok(new_resolved_module_ref(module_ref, resolved_concrete_type))
  # NOTE: nested argument module ref
  of MRK_NESTED:
    let arg_module = ? file.find_module(module_ref.module)
    # NOTE: The module itself where generic is defined can not be used as argument to constraint
    if arg_module.hash == module.hash:
      return err(fmt"{module_ref.location} [RE105] module `{module_ref.module.asl}` can not be used as an argument in generic constraints")

    if module_ref.children.len != arg_module.generics.len:
      return err(fmt"{module_ref.location} [RE106] module `{module_ref.module.asl}` expects `{arg_module.generics.len}` generic types but `{module_ref.children.len}` were given")

    let maybe_user_module = arg_module.user_module
    if maybe_user_module.is_err:
      return err(fmt"{module_ref.location} [RE111] module `{module_ref.module.asl}` does not expect generics")
    # NOTE: Only user modules can be nested
    var resolved_children: seq[ResolvedModuleRef]
    for child in module_ref.children:
      let resolved_child = ? resolve(file, module, generic, child)
      resolved_children.add(resolved_child)

    var concrete_map: Table[Generic, ResolvedModuleRef]
    for (child, generic) in zip(resolved_children, arg_module.generics):
      case child.kind:
      of RATK_CONCRETE:
        let child_module = child.concrete_type.module
        let new_arg_type = ? child_module.module_ref
        let concrete_defs = ? generic.concrete_function_definitions(new_arg_type)
        for def in concrete_defs:
          let maybe_found = child_module.find_function(def)
          # TODO: Resolve return type as well function definition does not account for return type in hash generation
          if maybe_found.is_err:
            return err(fmt"{module_ref.location} [RE107] module `{module_ref.module.asl}` expects `{child_module.name.asl}` to implement `{def.asl}`")
      of RATK_GENERIC:
        # NOTE: Handle generic parameters as nested type.
        let child_type = child.generic_type
        # NOTE: If the child type's module is same as parent module
        # Then we only allow generic types within.
        if child_type.module.hash != arg_module.hash or
            child_type.generic.hash != generic.hash:
          return err(fmt"{module_ref.location} [RE108] module `{module_ref.module.asl}` expects generic type `{generic.name.asl}` but found `{child_type.generic.name.asl}`")
      of RATK_NESTED:
        let child_module = child.module
        let child_module_ref = ? child_module.module_ref
        let concrete_defs = ? generic.concrete_function_definitions(child_module_ref)
        for def in concrete_defs:
          let maybe_found = child_module.find_function(def)
          # TODO: Resolve return type as well, since function definition hash does not account for return type
          if maybe_found.is_err:
            return err(fmt"{module_ref.location} [RE110] module `{module_ref.module.asl}` expects `{child.module.name.asl}` to implement `{def.asl}`")
      concrete_map[generic] = child

    ok(new_resolved_module_ref(module_ref, maybe_user_module.get,
        resolved_children, concrete_map))

proc resolve(file: ast.File, module: UserModule,
    module_ref: ModuleRef): Result[ResolvedModuleRef, string] =
  if DEBUG:
    echo fmt"Resolving MODULE ARG TYPE: {module_ref.location}"
  # NOTE: leaf argument types
  case module_ref.kind:
  of MRK_SIMPLE:
    # NOTE: generic argument type
    let maybe_generic = module.find_generic(module_ref.module)
    if maybe_generic.is_ok:
      let generic = maybe_generic.get
      let resolved_generic_type = new_resolved_generic_module_ref(module, generic)
      return ok(new_resolved_module_ref(module_ref, resolved_generic_type))

    # NOTE: concrete argument type
    let arg_module = ? file.find_module(module_ref.module)
    if arg_module.generics.len != 0:
      return err(fmt"{module_ref.location} [RE112] module `{module_ref.module.asl}` expects `{arg_module.generics.len}` generic types but `0` were given")
    let resolved_concrete_type = new_resolved_concrete_module_ref(arg_module)
    ok(new_resolved_module_ref(module_ref, resolved_concrete_type))
  # NOTE: nested argument type
  of MRK_NESTED:
    let arg_module = ? file.find_module(module_ref.module)
    if module_ref.children.len != arg_module.generics.len:
      return err(fmt"{module_ref.location} [RE113] module `{module_ref.module.asl}` expects `{arg_module.generics.len}` generic types but `{module_ref.children.len}` were given")

    let maybe_user_module = arg_module.user_module
    # NOTE: Only user modules can be nested
    if maybe_user_module.is_err:
      return err(fmt"{module_ref.location} [RE118] module `{module_ref.module.asl}` does not expect generics")

    var resolved_children: seq[ResolvedModuleRef]
    for child in module_ref.children:
      let resolved_child = ? resolve(file, module, child)
      resolved_children.add(resolved_child)

    var concrete_map: Table[Generic, ResolvedModuleRef]
    for (child, generic) in zip(resolved_children, arg_module.generics):
      case child.kind:
      of RATK_CONCRETE:
        let child_module = child.concrete_type.module
        let child_arg_type = ? child_module.module_ref
        let concrete_defs = ? generic.concrete_function_definitions(child_arg_type)
        for def in concrete_defs:
          let maybe_found = child_module.find_function(def)
          # TODO: Resolve return type as well function definition does not account for return type in hash generation
          if maybe_found.is_err:
            return err(fmt"{module_ref.location} [RE114] module `{module_ref.module.asl}` expects `{child_module.name.asl}` to implement `{def.asl}`")
      of RATK_GENERIC:
        # NOTE: Handle generic parameters as nested type.
        let child_type = child.generic_type
        # NOTE: If the child type's module is same as parent module
        # Then we only allow generic types within.
        if child_type.module.hash == arg_module.hash:
          if child_type.generic.hash != generic.hash:
            return err(fmt"{module_ref.location} [RE115] module `{module_ref.module.asl}` expects generic type `{generic.name.asl}` but found `{child_type.generic.name.asl}`")
        else:
          let concrete_defs = ? generic.concrete_function_definitions(
              child_type.generic.module_ref)
          for def in concrete_defs:
            let maybe_found = child_type.generic.find_function(def)
            # TODO: Resolve return type as well function definition does not account for return type in hash generation
            if maybe_found.is_err:
              return err(fmt"{module_ref.location} [RE123] module `{module_ref.module.asl}` expects `{child.module.name.asl}` to implement `{def.asl}`")
      of RATK_NESTED:
        let child_module = child.module
        let child_module_ref = ? child_module.module_ref
        let concrete_defs = ? generic.concrete_function_definitions(child_module_ref)
        for def in concrete_defs:
          let maybe_found = child_module.find_function(def)
          # TODO: Resolve return type as well function definition does not account for return type in hash generation
          if maybe_found.is_err:
            return err(fmt"{module_ref.location} [RE117] module `{module_ref.module.asl}` expects `{child.module.name.asl}` to implement `{def.asl}`")

      concrete_map[generic] = child

    ok(new_resolved_module_ref(module_ref, maybe_user_module.get,
        resolved_children, concrete_map))

proc resolve(file: ast.File, module_ref: ModuleRef): Result[
    ResolvedModuleRef, string] =
  if DEBUG:
    echo fmt"Resolving ARG TYPE: {module_ref.location}"
  # NOTE: leaf argument types
  case module_ref.kind:
  of MRK_SIMPLE:
    # NOTE: concrete argument type
    let arg_module = ? file.find_module(module_ref.module)
    if arg_module.generics.len != 0:
      return err(fmt"{module_ref.location} [RE119] module `{module_ref.module.asl}` expects `{arg_module.generics.len}` generic types but `{module_ref.children.len}` were given")
    let resolved_concrete_type = new_resolved_concrete_module_ref(arg_module)
    ok(new_resolved_module_ref(module_ref, resolved_concrete_type))
  # NOTE: nested argument type
  of MRK_NESTED:
    let arg_module = ? file.find_module(module_ref.module)
    if module_ref.children.len != arg_module.generics.len:
      return err(fmt"{module_ref.location} [RE120] module `{module_ref.module.asl}` expects `{arg_module.generics.len}` generic types but `{module_ref.children.len}` were given")

    let maybe_user_module = arg_module.user_module
    # NOTE: Only user modules can be nested
    if maybe_user_module.is_err:
      return err(fmt"{module_ref.location} [RE124] module `{module_ref.module.asl}` does not expect generics")

    var resolved_children: seq[ResolvedModuleRef]
    for child in module_ref.children:
      let resolved_child = ? resolve(file, child)
      resolved_children.add(resolved_child)

    var concrete_map: Table[Generic, ResolvedModuleRef]
    for (child, generic) in zip(resolved_children, arg_module.generics):
      case child.kind:
      of RATK_CONCRETE:
        let child_module = child.concrete_type.module
        let new_arg_type = ? child_module.module_ref
        let concrete_defs = ? generic.concrete_function_definitions(new_arg_type)
        for def in concrete_defs:
          let maybe_found = child_module.find_function(def)
          # TODO: Resolve return type as well function definition does not account for return type in hash generation
          if maybe_found.is_err:
            return err(fmt"{module_ref.location} [RE121] module `{module_ref.module.asl}` expects `{child.module.name.asl}` to implement `{def.asl}`")
      of RATK_GENERIC:
        # NOTE: File level functions will never have generic as input args so this
        # branch must always be unreachable unless there is some issue with the code.
        return err(fmt"{module_ref.location} [RE122] [UNREACHABLE] if you see this error that means something is wrong with the code")
      of RATK_NESTED:
        let child_module = child.module
        let child_module_ref = ? child_module.module_ref
        let concrete_defs = ? generic.concrete_function_definitions(child_module_ref)
        for def in concrete_defs:
          let maybe_found = child_module.find_function(def)
          # TODO: Resolve return type as well function definition does not account for return type in hash generation
          if maybe_found.is_err:
            return err(fmt"{module_ref.location} [RE123] module `{module_ref.module.asl}` expects `{child.module.name.asl}` to implement `{def.asl}`")

      concrete_map[generic] = child

    ok(new_resolved_module_ref(module_ref, maybe_user_module.get,
        resolved_children, concrete_map))

proc resolve(file: ast.File, module: UserModule, generic: Generic,
    def: ArgumentDefinition): Result[ResolvedArgumentDefinition, string] =
  if DEBUG:
    echo fmt"Resolving MODULE ARG DEF: {def.location}"
  let resolved_type = ? resolve(file, module, generic, def.module_ref)
  if resolved_type.is_struct:
    ok(new_resolved_argument_definition(def.name, resolved_type, def.location))
  else:
    err(fmt"{def.location} [RE125] module `{def.module_ref.module.asl}` is not a struct")

proc resolve(file: ast.File, module: UserModule,
    def: ArgumentDefinition): Result[ResolvedArgumentDefinition, string] =
  if DEBUG:
    echo fmt"Resolving MODULE ARG DEF: {def.location}"
  let resolved_type = ? resolve(file, module, def.module_ref)
  if resolved_type.is_struct:
    ok(new_resolved_argument_definition(def.name, resolved_type, def.location))
  else:
    err(fmt"{def.location} [RE126] module `{def.module_ref.module.asl}` is not a struct")

proc resolve(file: ast.File, def: ArgumentDefinition): Result[
    ResolvedArgumentDefinition, string] =
  if DEBUG:
    echo fmt"Resolving ARG DEF: {def.location}"
  let resolved_type = ? resolve(file, def.module_ref)
  if resolved_type.is_struct:
    ok(new_resolved_argument_definition(def.name, resolved_type, def.location))
  else:
    err(fmt"{def.location} [RE127] module `{def.module_ref.module.asl}` is not a struct")

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
    let module_ref = ? resolve(file, module, fnref_module)
    case module_ref.kind:
    of RATK_CONCRETE:
      let defs = ? module_ref.concrete_type.module.find_functions(fnref.name, arity)
      ok(new_resolved_function_ref(fnref, module_ref, defs))
    of RATK_GENERIC:
      let defs = ? module_ref.generic_type.generic.find_functions(fnref.name, arity)
      ok(new_resolved_function_ref(fnref, module_ref, defs))
    of RATK_NESTED:
      let defs = ? module_ref.module.find_functions(fnref.name, arity)
      ok(new_resolved_function_ref(fnref, module_ref, defs))

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
    let module_ref = ? resolve(file, fnref_module)
    case module_ref.kind:
    of RATK_CONCRETE:
      let defs = ? module_ref.concrete_type.module.find_functions(fnref.name, arity)
      ok(new_resolved_function_ref(fnref, module_ref, defs))
    of RATK_GENERIC:
      let defs = ? module_ref.generic_type.generic.find_functions(fnref.name, arity)
      ok(new_resolved_function_ref(fnref, module_ref, defs))
    of RATK_NESTED:
      let defs = ? module_ref.module.find_functions(fnref.name, arity)
      ok(new_resolved_function_ref(fnref, module_ref, defs))

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
    let module_ref = ? module.module_ref
    let concrete_type = new_resolved_concrete_module_ref(new_module(module))
    let concrete_module = new_resolved_module_ref(module_ref, concrete_type)
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
    let module_ref = ? module.module_ref
    let concrete_type = new_resolved_concrete_module_ref(new_module(module))
    let concrete_module = new_resolved_module_ref(module_ref, concrete_type)
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
    let module_ref = ? module.module_ref
    let concrete_type = new_resolved_concrete_module_ref(new_module(module))
    let concrete_module = new_resolved_module_ref(module_ref, concrete_type)
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
    case argdef.module_ref.kind:
    of RATK_CONCRETE:
      let argmodule = argdef.module_ref.concrete_type.module
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
    let actual_type = actual_argdef.module_ref
    let expected_type = argdef.module_ref
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
    case argdef.module_ref.kind:
    of RATK_CONCRETE:
      let argmodule = argdef.module_ref.concrete_type.module
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
    let actual_type = actual_argdef.module_ref
    let expected_type = argdef.module_ref
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
      let maybe_arg_user_module = resolved_fnref.module_ref.user_module
      if maybe_arg_user_module.is_ok:
        let resolved_def = ? resolve(file, maybe_arg_user_module.get, def)
        let concrete_def = resolved_def.concrete_function_definition(
            resolved_fnref.module_ref)
        let maybe_match = resolve(file, module, scope, concrete_def, fncall.args)
        if maybe_match.is_ok:
          return ok(new_resolved_function_call(fncall, resolved_fnref,
              concrete_def, maybe_match.get))
        # else:
        #   echo maybe_match.error

      let resolved_def = ? resolve(file, def)
      let concrete_def = resolved_def.concrete_function_definition(
            resolved_fnref.module_ref)
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
      let maybe_arg_user_module = resolved_fnref.module_ref.user_module
      if maybe_arg_user_module.is_ok:
        let resolved_def = ? resolve(file, maybe_arg_user_module.get, def)
        let concrete_def = resolved_def.concrete_function_definition(
            resolved_fnref.module_ref)
        let maybe_match = resolve(file, scope, concrete_def, fncall.args)
        if maybe_match.is_ok:
          return ok(new_resolved_function_call(fncall, resolved_fnref,
              concrete_def, maybe_match.get))
        # else:
        #   echo maybe_match.error

      let resolved_def = ? resolve(file, def)
      let concrete_def = resolved_def.concrete_function_definition(
            resolved_fnref.module_ref)
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
  let resolved_module_ref = ? resolve(file, module, struct_ref.module)
  let resolved_argmodule = ? resolved_module_ref.user_module
  let struct =
    case struct_ref.kind:
    of SRK_DEFAULT: ? resolved_argmodule.find_struct()
    of SRK_NAMED: ? resolved_argmodule.find_struct( ? struct_ref.struct)
  let resolved_struct = ? resolve(file, resolved_argmodule, struct)
  let concrete_struct = ? resolved_struct.concrete_struct(
      resolved_module_ref.concrete_map)
  ok(new_resolved_struct_ref(struct_ref, resolved_module_ref, concrete_struct))

proc resolve(file: ast.File, struct_ref: StructRef): Result[
    ResolvedStructRef, string] =
  if DEBUG:
    echo fmt"Resolving FUNCTION STRUCT REF: {struct_ref.location}"
  let resolved_module_ref = ? resolve(file, struct_ref.module)
  let resolved_argmodule = ? resolved_module_ref.user_module
  let struct =
    case struct_ref.kind:
    of SRK_DEFAULT: ? resolved_argmodule.find_struct()
    of SRK_NAMED: ? resolved_argmodule.find_struct( ? struct_ref.struct)
  let resolved_struct = ? resolve(file, resolved_argmodule, struct)
  let concrete_struct = ? resolved_struct.concrete_struct(
      resolved_module_ref.concrete_map)
  ok(new_resolved_struct_ref(struct_ref, resolved_module_ref, concrete_struct))

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
    let resolved_module_ref = ? resolve(file, literal_init.module)
    let literal_module = ? resolved_module_ref.native_module
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
  let argmodule = ? argdef.module_ref.user_module
  let default_struct = ? argmodule.find_struct()
  let resolved_struct = ? resolve(file, argmodule, default_struct)
  let concrete_struct = ? resolved_struct.concrete_struct(
      argdef.module_ref.concrete_map)
  let field_id = ? concrete_struct.find_field_id(struct_get.field)
  let resolved_field = concrete_struct.fields[field_id]
  ok(new_resolved_struct_get(struct_get, argdef.module_ref, resolved_field))

proc resolve(file: ast.File, scope: FunctionScope,
    struct_get: StructGet): Result[ResolvedStructGet, string] =
  if DEBUG:
    echo fmt"Resolving FUNCTION STEP STATEMENT EXPRESSION STRUCT GET: {struct_get.location}"
  let argdef = ? scope.get(struct_get.name)
  let argmodule = ? argdef.module_ref.user_module
  let default_struct = ? argmodule.find_struct()
  let resolved_struct = ? resolve(file, argmodule, default_struct)
  let concrete_struct = ? resolved_struct.concrete_struct(
      argdef.module_ref.concrete_map)
  let field_id = ? concrete_struct.find_field_id(struct_get.field)
  let resolved_field = concrete_struct.fields[field_id]
  ok(new_resolved_struct_get(struct_get, argdef.module_ref, resolved_field))

proc resolve(file: ast.File, module: UserModule, scope: FunctionScope,
    match: Match): Result[ResolvedMatch, string]
proc resolve(file: ast.File, scope: FunctionScope, match: Match): Result[
    ResolvedMatch, string]

proc resolve(file: ast.File, module: UserModule, scope: FunctionScope,
    expression: Expression): Result[ResolvedExpression, string] =
  if DEBUG:
    echo fmt"Resolving MODULE FUNCTION STEP STATEMENT EXPRESSION: {expression.location}"
  case expression.kind:
  of EK_MATCH:
    let match = ? expression.match
    let resolved_function_call = ? resolve(file, module, scope, match)
    ok(new_resolved_expression(expression, resolved_function_call))
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
  of EK_MATCH:
    let match = ? expression.match
    let resolved_function_call = ? resolve(file, scope, match)
    ok(new_resolved_expression(expression, resolved_function_call))
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
    let operand_module = ? operand.module_ref.user_module
    let struct = ? operand_module.find_struct()
    let resolved_struct = ? resolve(file, operand_module, struct)
    let concrete_struct = ? resolved_struct.concrete_struct(
        operand.module_ref.concrete_map)
    var fields: seq[ResolvedArgumentDefinition]
    for (key, value) in pattern.args:
      let field_id = ? concrete_struct.find_field_id(key)
      let resolved_field = concrete_struct.fields[field_id]
      let value_arg_def = new_resolved_argument_definition(value,
          resolved_field.module_ref, value.location)
      fields.add(value_arg_def)
    ok(new_resolved_struct_pattern(pattern, fields, resolved_struct))
  of SPK_NAMED:
    let operand_module = ? operand.module_ref.user_module
    let struct_name = ? pattern.struct
    let struct = ? operand_module.find_struct(struct_name)
    let resolved_struct = ? resolve(file, operand_module, struct)
    let concrete_struct = ? resolved_struct.concrete_struct(
        operand.module_ref.concrete_map)
    var fields: seq[ResolvedArgumentDefinition]
    for (key, value) in pattern.args:
      let field_id = ? concrete_struct.find_field_id(key)
      let resolved_field = concrete_struct.fields[field_id]
      let value_arg_def = new_resolved_argument_definition(value,
          resolved_field.module_ref, value.location)
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
      case operand.module_ref.kind:
      of RATK_CONCRETE:
        let native_module = ? operand.module_ref.native_module
        let resolved_literal = ? resolve(native_module, integer_literal)
        let resolved_case_pattern = new_resolved_case_pattern(def.pattern, resolved_literal)
        ok(new_resolved_case_definition(def, resolved_case_pattern))
      else:
        err(fmt"{literal.location} only native modules support literal matching")
    else:
      err(fmt"{literal.location} only integer literals supported in case pattern")
  of CPK_STRUCT:
    let operand_module = ? operand.module_ref.user_module
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
      case operand.module_ref.kind:
      of RATK_CONCRETE:
        let native_module = ? operand.module_ref.native_module
        let resolved_literal = ? resolve(native_module, integer_literal)
        let resolved_case_pattern = new_resolved_case_pattern(def.pattern, resolved_literal)
        ok(new_resolved_case_definition(def, resolved_case_pattern))
      else:
        err(fmt"{literal.location} only native modules support literal matching")
    else:
      err(fmt"{literal.location} only integer literals supported in case pattern")
  of CPK_STRUCT:
    let operand_module = ? operand.module_ref.user_module
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

# proc resolve(file: ast.File, module: UserModule, scope: FunctionScope,
#     step: FunctionStep): Result[ResolvedFunctionStep, string] =
#   if DEBUG:
#     echo fmt"Resolving MODULE FUNCTION STEP: {step.location}"
#   case step.kind:
#   of FSK_STATEMENT:
#     let statement = ? step.statement
#     let resolved_statement = ? resolve(file, module, scope, statement)
#     ok(new_resolved_function_step(step, resolved_statement))
#   of FSK_MATCH:
#     let match = ? step.match
#     let resolved_match = ? resolve(file, module, scope, match)
#     ok(new_resolved_function_step(step, resolved_match))

# proc resolve(file: ast.File, scope: FunctionScope,
#     step: FunctionStep): Result[ResolvedFunctionStep, string] =
#   if DEBUG:
#     echo fmt"Resolving FUNCTION STEP: {step.location}"
#   case step.kind:
#   of FSK_STATEMENT:
#     let statement = ? step.statement
#     let resolved_statement = ? resolve(file, scope, statement)
#     ok(new_resolved_function_step(step, resolved_statement))
#   of FSK_MATCH:
#     let match = ? step.match
#     let resolved_match = ? resolve(file, scope, match)
#     ok(new_resolved_function_step(step, resolved_match))

proc resolve(file: ast.File, module: UserModule, function: Function): Result[
    ResolvedFunction, string] =
  if DEBUG:
    echo fmt"Resolving MODULE FUNCTION: {function.location}"
  let resolved_function_def = ? resolve(file, module, function.def)
  var scope = FunctionScope()
  for arg in resolved_function_def.args:
    scope = ? scope.add(arg)

  var resolved_steps: seq[ResolvedStatement]
  for step in function.steps:
    let resolved_step = ? resolve(file, module, scope, step)
    resolved_steps.add(resolved_step)
    scope = ? scope.add(resolved_step.arg)

  let fn_return_type = resolved_steps[^1].arg.module_ref
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
  var resolved_steps: seq[ResolvedStatement]
  for step in function.steps:
    let resolved_step = ? resolve(file, scope, step)
    resolved_steps.add(resolved_step)
    scope = ? scope.add(resolved_step.arg)

  let fn_return_type = resolved_steps[^1].arg.module_ref
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
