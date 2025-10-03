import results, strformat, strutils, sequtils, re, tables, hashes

import tokens

# ast node constants
const MAX_IDENTIFIER_LENGTH = 256
const MAX_TYPE_CHILDREN_COUNT = 8
const MAX_ARGS_LENGTH = 32

type Identifier* = ref object of RootObj
  name: string
  location: Location

proc new_identifier*(name: string, location: Location): Result[Identifier, string] =
  if name.len == 0:
    return err(fmt"{location} [UNREACHABLE] empty string can not be an identifier.")

  if name.len > MAX_IDENTIFIER_LENGTH:
    return err(fmt"{location} identifier length `{name.len}` exceeded maximum identifier length of `{MAX_IDENTIFIER_LENGTH}`")
  ok(Identifier(name: name, location: location))

proc asl(identifier: Identifier): string =
  identifier.name

proc hash(identifier: Identifier): Hash =
  hash(identifier.name)

type
  ArgumentTypeKind = enum
    ATK_SIMPLE, ATK_NESTED
  ArgumentType* = ref object of RootObj
    module: Identifier
    case kind: ArgumentTypeKind
    of ATK_SIMPLE: discard
    of ATK_NESTED: children: seq[ArgumentType]

proc new_argument_type*(module: Identifier): ArgumentType =
  ArgumentType(kind: ATK_SIMPLE, module: module)

proc new_argument_type*(module: Identifier, children: seq[
    ArgumentType]): Result[ArgumentType, string] =
  if children.len == 0:
    return err(fmt"{module.location} nested argument types can not have empty children type list")
  if children.len > MAX_TYPE_CHILDREN_COUNT:
    return err(fmt"{module.location} a nested type only supports upto `{MAX_TYPE_CHILDREN_COUNT}` children types but `{children.len}` were given")
  ok(ArgumentType(kind: ATK_NESTED, module: module, children: children))

proc location(argtype: ArgumentType): Location =
  argtype.module.location

proc asl(argtype: ArgumentType): string =
  case argtype.kind:
  of ATK_SIMPLE: argtype.module.asl
  of ATK_NESTED:
    var children: seq[string]
    for child in argtype.children:
      children.add(child.asl)
    let module_str = argtype.module.asl
    let children_str = children.join(", ")
    fmt"{module_str}[{children_str}]"

proc hash(argtype: ArgumentType): Hash =
  case argtype.kind:
  of ATK_SIMPLE: hash(argtype.module)
  of ATK_NESTED:
    var acc = hash(argtype.module)
    for child in argtype.children:
      acc = acc !& hash(child)
    return acc

type ArgumentDefinition* = ref object of RootObj
  name: Identifier
  argtype: ArgumentType

proc new_argument_definition*(name: Identifier,
    argtype: ArgumentType): ArgumentDefinition =
  ArgumentDefinition(name: name, argtype: argtype)

proc location(def: ArgumentDefinition): Location =
  def.argtype.location

proc asl(def: ArgumentDefinition): string =
  let name_str = def.name.asl
  let type_str = def.argtype.asl
  fmt"{type_str} {name_str}"

proc hash(def: ArgumentDefinition): Hash =
  hash(def.argtype)

type
  StructDefinitionKind = enum
    SDK_DEFAULT, SDK_NAMED
  StructDefinition* = ref object of RootObj
    location: Location
    case kind: StructDefinitionKind
    of SDK_DEFAULT: discard
    of SDK_NAMED: name: Identifier

proc new_struct_definition*(location: Location): StructDefinition =
  StructDefinition(kind: SDK_DEFAULT, location: location)

proc new_struct_definition*(name: Identifier,
    location: Location): StructDefinition =
  StructDefinition(kind: SDK_NAMED, name: name, location: location)

proc asl(def: StructDefinition): string =
  case def.kind:
  of SDK_DEFAULT: "struct:"
  of SDK_NAMED: fmt"struct {def.name.asl}:"

type Struct* = ref object of RootObj
  def: StructDefinition
  fields: seq[ArgumentDefinition]
  fields_map: Table[Identifier, int]

proc new_struct*(def: StructDefinition, fields: seq[
    ArgumentDefinition]): Result[Struct, string] =
  if fields.len == 0:
    return err(fmt"{def.location} struct block can not be empty")
  if fields.len > MAX_ARGS_LENGTH:
    return err(fmt"{def.location} struct field length `{fields.len}` exceeded maximum field length `{MAX_ARGS_LENGTH}`")

  var fields_map: Table[Identifier, int]
  for index, field in fields.pairs:
    if field.name in fields_map:
      let predefined_field_location = fields[fields_map[field.name]].location
      return err(fmt"{field.location} field `{field.name.asl}` is already defined at {predefined_field_location}")
    fields_map[field.name] = index

  ok(Struct(def: def, fields: fields, fields_map: fields_map))

proc location(struct: Struct): Location =
  struct.def.location

proc name(struct: Struct): Identifier =
  struct.def.name

proc asl(struct: Struct, indent: string): seq[string] =
  let header = struct.def.asl
  var fields: seq[string]
  for field in struct.fields:
    fields.add(indent & field.asl)

  return (@[header] & fields)

type FunctionDefinition* = ref object of RootObj
  name: Identifier
  returns: ArgumentType
  args: seq[ArgumentDefinition]
  args_map: Table[Identifier, int]
  location: Location

proc new_function_definition*(name: Identifier, args: seq[ArgumentDefinition],
    returns: ArgumentType, location: Location): Result[FunctionDefinition, string] =
  if args.len == 0:
    return err(fmt"{location} function argument list can not be empty")
  if args.len > MAX_ARGS_LENGTH:
    return err(fmt"{location} function argument length `{args.len}` exceeded maximum argument length `{MAX_ARGS_LENGTH}`")

  var args_map: Table[Identifier, int]
  for index, arg in args.pairs:
    if arg.name in args_map:
      let predefined_arg_location = args[args_map[arg.name]].location
      return err(fmt"{arg.location} argument `{arg.name.asl}` is already defined at {predefined_arg_location}")
    args_map[arg.name] = index

  ok(FunctionDefinition(name: name, args: args, args_map: args_map,
      returns: returns, location: location))

proc asl(def: FunctionDefinition): string =
  var args: seq[string]
  for arg in def.args:
    args.add(arg.asl)
  let args_str = args.join(", ")
  fmt"fn {def.name.asl}({args_str}): {def.returns.asl}"

proc hash(def: FunctionDefinition): Hash =
  var acc = hash(def.name)
  for arg in def.args:
    acc = acc !& hash(arg)
  return acc

type UnsignedIntegerLiteral* = ref object of RootObj
  value: string
  location: Location

proc new_unsigned_integer*(digits: Token): UnsignedIntegerLiteral =
  UnsignedIntegerLiteral(value: digits.value, location: digits.location)

proc asl(unsigned_integer: UnsignedIntegerLiteral): string =
  unsigned_integer.value

type
  SignedIntegerLiteralKind = enum
    SIK_POSITIVE, SIK_NEGATIVE
  SignedIntegerLiteral* = ref object of RootObj
    kind: SignedIntegerLiteralKind
    value: string
    location: Location

proc new_signed_integer*(sign: Token, unsigned_integer: UnsignedIntegerLiteral): Result[
    SignedIntegerLiteral, string] =
  case sign.kind:
  of TK_PLUS:
    ok(SignedIntegerLiteral(kind: SIK_NEGATIVE, value: unsigned_integer.value,
        location: sign.location))
  of TK_MINUS:
    ok(SignedIntegerLiteral(kind: SIK_POSITIVE, value: unsigned_integer.value,
        location: sign.location))
  else:
    return err(fmt"{sign.location} expected a sign `+` or `-` but found {sign.value}")

proc asl(signed_integer: SignedIntegerLiteral): string =
  let sign =
    case signed_integer.kind:
    of SIK_POSITIVE: "+"
    of SIK_NEGATIVE: "-"
  return sign & signed_integer.value

type
  IntegerLiteralKind = enum
    ILK_SIGNED, ILK_UNSIGNED
  IntegerLiteral* = ref object of RootObj
    case kind: IntegerLiteralKind
    of ILK_SIGNED: signed: SignedIntegerLiteral
    of ILK_UNSIGNED: unsigned: UnsignedIntegerLiteral

proc new_integer*(signed: SignedIntegerLiteral): IntegerLiteral =
  IntegerLiteral(kind: ILK_SIGNED, signed: signed)

proc new_integer*(unsigned: UnsignedIntegerLiteral): IntegerLiteral =
  IntegerLiteral(kind: ILK_UNSIGNED, unsigned: unsigned)

proc location(integer: IntegerLiteral): Location =
  case integer.kind:
  of ILK_SIGNED: integer.signed.location
  of ILK_UNSIGNED: integer.unsigned.location

proc asl(integer: IntegerLiteral): string =
  case integer.kind:
  of ILK_SIGNED: integer.signed.asl
  of ILK_UNSIGNED: integer.unsigned.asl

type FloatLiteral* = ref object of RootObj
  value: string
  location: Location

proc new_float*(first: IntegerLiteral, second: UnsignedIntegerLiteral): FloatLiteral =
  let value = first.asl & "." & second.asl
  FloatLiteral(value: value, location: first.location)

proc asl(float_literal: FloatLiteral): string =
  float_literal.value

type StringLiteral* = ref object of RootObj
  value: string
  location: Location

proc new_string*(token: Token): Result[StringLiteral, string] =
  case token.kind:
  of TK_STRING:
    ok(StringLiteral(value: token.value, location: token.location))
  else:
    err(fmt"{token.location} expected a string found token of type `{token.kind}` with value: `{token.value}`")

proc asl(string_literal: StringLiteral): string =
  string_literal.value

type
  LiteralKind = enum
    LK_INTEGER, LK_FLOAT, LK_STRING
  Literal* = ref object of RootObj
    case kind: LiteralKind
    of LK_INTEGER: integer_literal: IntegerLiteral
    of LK_FLOAT: float_literal: FloatLiteral
    of LK_STRING: string_literal: StringLiteral

proc new_literal*(integer_literal: IntegerLiteral): Literal =
  Literal(kind: LK_INTEGER, integer_literal: integer_literal)

proc new_literal*(float_literal: FloatLiteral): Literal =
  Literal(kind: LK_FLOAT, float_literal: float_literal)

proc new_literal*(string_literal: StringLiteral): Literal =
  Literal(kind: LK_STRING, string_literal: string_literal)

proc asl(literal: Literal): string =
  case literal.kind:
  of LK_INTEGER: literal.integer_literal.asl
  of LK_FLOAT: literal.float_literal.asl
  of LK_STRING: literal.string_literal.asl

type
  ArgumentKind = enum
    AK_LITERAL, AK_VARIABLE
  Argument* = ref object of RootObj
    case kind: ArgumentKind
    of AK_LITERAL: literal: Literal
    of AK_VARIABLE: variable: Identifier

proc new_argument*(literal: Literal): Argument =
  Argument(kind: AK_LITERAL, literal: literal)

proc new_argument*(variable: Identifier): Argument =
  Argument(kind: AK_VARIABLE, variable: variable)

# proc location(arg: Argument): Location =
#   case arg.kind:
#   of AK_LITERAL: arg.literal.location
#   of AK_VARIABLE: arg.variable.location

proc asl(arg: Argument): string =
  case arg.kind:
  of AK_LITERAL: arg.literal.asl
  of AK_VARIABLE: arg.variable.asl

type
  FunctionRefKind = enum
    FRK_LOCAL, FRK_MODULE
  FunctionRef* = ref object of RootObj
    name: Identifier
    case kind: FunctionRefKind
    of FRK_LOCAL: discard
    of FRK_MODULE: module: ArgumentType

proc new_function_ref*(name: Identifier): FunctionRef =
  FunctionRef(kind: FRK_LOCAL, name: name)

proc new_function_ref*(name: Identifier, module: ArgumentType): FunctionRef =
  FunctionRef(kind: FRK_MODULE, name: name, module: module)

proc location(fnref: FunctionRef): Location =
  case fnref.kind:
  of FRK_LOCAL: fnref.name.location
  of FRK_MODULE: fnref.module.location

proc asl(fnref: FunctionRef): string =
  case fnref.kind:
  of FRK_LOCAL: fnref.name.asl
  of FRK_MODULE: fmt"{fnref.module.asl}.{fnref.name.asl}"

type FunctionCall* = ref object of RootObj
  fnref: FunctionRef
  args: seq[Argument]

proc new_function_call*(fnref: FunctionRef, args: seq[Argument]): Result[
    FunctionCall, string] =
  if args.len == 0:
    return err(fmt"{fnref.location} function call argument list can not be empty")
  if args.len > MAX_ARGS_LENGTH:
    return err(fmt"{fnref.location} function call argument length `{args.len}` exceeded maximum args length `{MAX_ARGS_LENGTH}`")
  ok(FunctionCall(fnref: fnref, args: args))

# proc location(fncall: FunctionCall): Location =
#   fncall.fnref.location

proc asl(fncall: FunctionCall): string =
  var args: seq[string]
  for arg in fncall.args:
    args.add(arg.asl)
  let args_str = args.join(", ")
  fmt"{fncall.fnref.asl}({args_str})"

type LiteralInit* = ref object of RootObj
  module: ArgumentType
  literal: Literal

proc new_literal_init*(module: ArgumentType, literal: Literal): LiteralInit =
  LiteralInit(module: module, literal: literal)

# proc location(init: LiteralInit): Location =
#   init.module.location

proc asl(init: LiteralInit): string =
  fmt"{init.module.asl} {init.literal.asl}"

type KeywordArgument* = ref object of RootObj
  name: Identifier
  value: Argument

proc new_keyword_argument*(name: Identifier, value: Argument): KeywordArgument =
  KeywordArgument(name: name, value: value)

proc location(kwarg: KeywordArgument): Location =
  kwarg.name.location

proc asl(kwarg: KeywordArgument): string =
  fmt"{kwarg.name.asl}: {kwarg.value.asl}"

type
  StructRefKind = enum
    SRK_DEFAULT, SRK_NAMED
  StructRef* = ref object of RootObj
    module: ArgumentType
    case kind: StructRefKind
    of SRK_DEFAULT: discard
    of SRK_NAMED: struct: Identifier

proc new_struct_ref*(module: ArgumentType): StructRef =
  StructRef(kind: SRK_DEFAULT, module: module)

proc new_struct_ref*(module: ArgumentType, struct: Identifier): StructRef =
  StructRef(kind: SRK_NAMED, module: module, struct: struct)

proc location(struct_ref: StructRef): Location =
  struct_ref.module.location

proc asl(struct_ref: StructRef): string =
  case struct_ref.kind:
  of SRK_DEFAULT: struct_ref.module.asl
  of SRK_NAMED: fmt"{struct_ref.module.asl}.{struct_ref.struct.asl}"

type StructInit* = ref object of RootObj
  struct_ref: StructRef
  args: seq[KeywordArgument]
  args_map: Table[Identifier, int]

proc new_struct_init*(struct_ref: StructRef, args: seq[
    KeywordArgument]): Result[StructInit, string] =
  if args.len == 0:
    return err(fmt"{struct_ref.location} initializer field list can not be empty")

  if args.len > MAX_ARGS_LENGTH:
    return err(fmt"{struct_ref.location} initializer field length `{args.len}` exceeded maximum field length `{MAX_ARGS_LENGTH}`")

  var args_map: Table[Identifier, int]
  for index, arg in args.pairs:
    if arg.name in args_map:
      let predefined_arg_location = args[args_map[arg.name]].location
      return err(fmt"{arg.location} field `{arg.name.asl}` is already defined at {predefined_arg_location}")
    args_map[arg.name] = index

  ok(StructInit(struct_ref: struct_ref, args: args, args_map: args_map))

# proc location(init: StructInit): Location =
#   init.struct_ref.location

proc asl(init: StructInit): string =
  var args: seq[string]
  for arg in init.args:
    args.add(arg.asl)
  [init.struct_ref.asl, "{", args.join(", "), "}"].join(" ")

type
  InitializerKind = enum
    IK_LITERAL, IK_STRUCT
  Initializer* = ref object of RootObj
    case kind: InitializerKind
    of IK_LITERAL: literal: LiteralInit
    of IK_STRUCT: struct: StructInit

proc new_initializer*(literal: LiteralInit): Initializer =
  Initializer(kind: IK_LITERAL, literal: literal)

proc new_initializer*(struct: StructInit): Initializer =
  Initializer(kind: IK_STRUCT, struct: struct)

# proc location(init: Initializer): Location =
#   case init.kind:
#   of IK_LITERAL: init.literal.location
#   of IK_STRUCT: init.struct.location

proc asl(init: Initializer): string =
  case init.kind:
  of IK_LITERAL: init.literal.asl
  of IK_STRUCT: init.struct.asl

type StructGet* = ref object of RootObj
  name: Identifier
  field: Identifier

proc new_struct_get*(name: Identifier, field: Identifier): StructGet =
  StructGet(name: name, field: field)

# proc location(struct_get: StructGet): Location =
#   struct_get.name.location

proc asl(struct_get: StructGet): string =
  fmt"{struct_get.name.asl}.{struct_get.field.asl}"

type
  ExpressionKind = enum
    EK_FNCALL, EK_INIT, EK_STRUCT_GET, EK_VARIABLE
  Expression* = ref object of RootObj
    case kind: ExpressionKind
    of EK_FNCALL: fncall: FunctionCall
    of EK_INIT: init: Initializer
    of EK_STRUCT_GET: struct_get: StructGet
    of EK_VARIABLE: variable: Identifier

proc new_expression*(fncall: FunctionCall): Expression =
  Expression(kind: EK_FNCALL, fncall: fncall)

proc new_expression*(init: Initializer): Expression =
  Expression(kind: EK_INIT, init: init)

proc new_expression*(struct_get: StructGet): Expression =
  Expression(kind: EK_STRUCT_GET, struct_get: struct_get)

proc new_expression*(variable: Identifier): Expression =
  Expression(kind: EK_VARIABLE, variable: variable)

# proc location(expression: Expression): Location =
#   case expression.kind:
#   of EK_FNCALL: expression.fncall.location
#   of EK_INIT: expression.init.location
#   of EK_STRUCT_GET: expression.struct_get.location
#   of EK_VARIABLE: expression.variable.location

proc asl(expression: Expression): string =
  case expression.kind:
  of EK_FNCALL: expression.fncall.asl
  of EK_INIT: expression.init.asl
  of EK_STRUCT_GET: expression.struct_get.asl
  of EK_VARIABLE: expression.variable.asl

type Assignment* = ref object of RootObj
  arg: Identifier
  expression: Expression

proc new_assignment*(arg: Identifier, expression: Expression): Assignment =
  Assignment(arg: arg, expression: expression)

# proc location(assignment: Assignment): Location =
#   assignment.arg.location

proc asl(assignment: Assignment): string =
  fmt"{assignment.arg.asl} = {assignment.expression.asl}"

type
  StatementKind = enum
    SK_EXPR, SK_ASSIGN
  Statement* = ref object of RootObj
    case kind: StatementKind
    of SK_EXPR: expression: Expression
    of SK_ASSIGN: assignment: Assignment

proc new_statement*(expression: Expression): Statement =
  Statement(kind: SK_EXPR, expression: expression)

proc new_statement*(assignment: Assignment): Statement =
  Statement(kind: SK_ASSIGN, assignment: assignment)

# proc location(statement: Statement): Location =
#   case statement.kind:
#   of SK_ASSIGN: statement.assignment.location
#   of SK_EXPR: statement.expression.location

proc asl(statement: Statement): string =
  case statement.kind:
  of SK_ASSIGN: statement.assignment.asl
  of SK_EXPR: statement.expression.asl

type
  StructPatternKind = enum
    SPK_DEFAULT, SPK_NAMED
  StructPattern* = ref object of RootObj
    args: seq[(Identifier, Identifier)]
    args_map: Table[Identifier, int]
    case kind: StructPatternKind
    of SPK_DEFAULT: location: Location
    of SPK_NAMED: struct: Identifier

proc new_struct_pattern*(args: seq[(Identifier, Identifier)],
    location: Location): Result[StructPattern, string] =
  if args.len == 0:
    return err(fmt"{location} pattern field list can not be empty")
  if args.len > MAX_ARGS_LENGTH:
    return err(fmt"{location} pattern field length `{args.len}` exceeded maximum field length `{MAX_ARGS_LENGTH}`")

  var args_map: Table[Identifier, int]
  for index, (key, value) in args.pairs:
    if key in args_map:
      let predefined_field_location = args[args_map[key]][0].location
      return err(fmt"{key.location} field `{key.asl}` is already defined at {predefined_field_location}")
    args_map[key] = index

  ok(StructPattern(kind: SPK_DEFAULT, args: args, args_map: args_map,
      location: location))

proc new_struct_pattern*(struct: Identifier, pattern: StructPattern): Result[
    StructPattern, string] =
  case pattern.kind:
  of SPK_DEFAULT: discard
  of SPK_NAMED: return err(fmt"{struct.location} [UNREACHABLE] named struct pattern can not be converted to another named struct pattern")

  let args = pattern.args
  if args.len == 0:
    return err(fmt"{struct.location} pattern field list can not be empty")

  if args.len > MAX_ARGS_LENGTH:
    return err(fmt"{struct.location} pattern field length `{args.len}` exceeded maximum field length `{MAX_ARGS_LENGTH}`")

  var args_map: Table[Identifier, int]
  for index, (key, value) in args.pairs:
    if key in args_map:
      let predefined_field_location = args[args_map[key]][0].location
      return err(fmt"{key.location} field `{key.asl}` is already defined at {predefined_field_location}")
    args_map[key] = index

  ok(StructPattern(kind: SPK_NAMED, struct: struct, args: args,
      args_map: args_map))

# proc location(pattern: StructPattern): Location =
#   case pattern.kind:
#   of SPK_DEFAULT: pattern.location
#   of SPK_NAMED: pattern.struct.location

proc asl(pattern: StructPattern): string =
  var args: seq[string]
  for (key, val) in pattern.args:
    args.add(fmt"{key.asl}: {val.asl}")

  case pattern.kind:
  of SPK_DEFAULT: "{" & args.join(", ") & "}"
  of SPK_NAMED: pattern.struct.asl & "{" & args.join(", ") & "}"

type
  CasePatternKind = enum
    CPK_LITERAL, CPK_STRUCT
  CasePattern* = ref object of RootObj
    case kind: CasePatternKind
    of CPK_LITERAL: literal: Literal
    of CPK_STRUCT: struct: StructPattern

proc new_case_pattern*(literal: Literal): CasePattern =
  CasePattern(kind: CPK_LITERAL, literal: literal)

proc new_case_pattern*(struct: StructPattern): CasePattern =
  CasePattern(kind: CPK_STRUCT, struct: struct)

# proc location(pattern: CasePattern): Location =
#   case pattern.kind:
#   of CPK_LITERAL: pattern.literal.location
#   of CPK_STRUCT: pattern.struct.location

proc asl(pattern: CasePattern): string =
  case pattern.kind:
  of CPK_LITERAL: pattern.literal.asl
  of CPK_STRUCT: pattern.struct.asl

type CaseDefinition* = ref object of RootObj
  pattern: CasePattern
  location: Location

proc new_case_definition*(pattern: CasePattern,
    location: Location): CaseDefinition =
  CaseDefinition(pattern: pattern, location: location)

proc asl(def: CaseDefinition): string =
  fmt"case {def.pattern.asl}:"

type Case* = ref object of RootObj
  def: CaseDefinition
  statements: seq[Statement]

proc new_case*(def: CaseDefinition, statements: seq[Statement]): Result[Case, string] =
  if statements.len == 0:
    return err(fmt"{def.location} case block must have at least one statement")
  ok(Case(def: def, statements: statements))

# proc location(case_block: Case): Location =
#   case_block.def.location

proc asl(case_block: Case, indent: string): seq[string] =
  let header = case_block.def.asl

  var statements: seq[string]
  for statement in case_block.statements:
    statements.add(indent & statement.asl)

  return (@[header] & statements)

type Else* = ref object of RootObj
  statements: seq[Statement]
  location: Location

proc new_else*(statements: seq[Statement], location: Location): Result[Else, string] =
  if statements.len == 0:
    return err(fmt"{location} else block must have at least one statement")

  ok(Else(statements: statements, location: location))

proc asl(else_block: Else, indent: string): seq[string] =
  let header = "else: "

  var statements: seq[string]
  for statement in else_block.statements:
    statements.add(indent & statement.asl)

  return (@[header] & statements)

type
  MatchDefinitionKind = enum
    MDK_DEFAULT, MDK_ASSIGNED
  MatchDefinition* = ref object of RootObj
    operand: Identifier
    case kind: MatchDefinitionKind
    of MDK_DEFAULT: location: Location
    of MDK_ASSIGNED: arg: Identifier

proc new_match_definition*(operand: Identifier,
    location: Location): MatchDefinition =
  MatchDefinition(kind: MDK_DEFAULT, operand: operand, location: location)

proc new_match_definition*(def: MatchDefinition,
    arg: Identifier): Result[MatchDefinition, string] =
  case def.kind:
  of MDK_DEFAULT:
    ok(MatchDefinition(kind: MDK_ASSIGNED, arg: arg, operand: def.operand))
  of MDK_ASSIGNED:
    err(fmt"{def.location} [UNREACHABLE] match operation result can only be assigned to 1 variable")

proc location(def: MatchDefinition): Location =
  case def.kind:
  of MDK_DEFAULT: def.location
  of MDK_ASSIGNED: def.arg.location

proc asl(def: MatchDefinition): string =
  case def.kind:
  of MDK_DEFAULT: fmt"match {def.operand.asl}:"
  of MDK_ASSIGNED: fmt"{def.arg.asl} = match {def.operand.asl}:"

type
  MatchKind = enum
    MK_CASE_ONLY, MK_COMPLETE
  Match* = ref object of RootObj
    def: MatchDefinition
    case_blocks: seq[Case]
    case kind: MatchKind
    of MK_CASE_ONLY: discard
    of MK_COMPLETE: else_block: Else

proc new_match*(def: MatchDefinition, case_blocks: seq[Case]): Result[Match, string] =
  if case_blocks.len < 2:
    return err(fmt"{location(def)} match block must have at least 2 case blocks")
  ok(Match(kind: MK_CASE_ONLY, def: def, case_blocks: case_blocks))

proc new_match*(def: MatchDefinition, case_blocks: seq[Case],
    else_block: Else): Result[Match, string] =
  if case_blocks.len < 1:
    return err(fmt"{location(def)} match block must have at least 1 case block")

  ok(Match(kind: MK_COMPLETE, def: def, case_blocks: case_blocks,
      else_block: else_block))

# proc location(match: Match): Location =
#   match.def.location

proc asl(match: Match, indent: string): seq[string] =
  let header = match.def.asl

  var lines: seq[string]
  for case_block in match.case_blocks:
    for line in case_block.asl(indent):
      lines.add(indent & line)

  case match.kind:
  of MK_CASE_ONLY: discard
  of MK_COMPLETE:
    for line in match.else_block.asl(indent):
      lines.add(indent & line)

  return (@[header] & lines)

type
  FunctionStepKind = enum
    FSK_STATEMENT, FSK_MATCH
  FunctionStep* = ref object of RootObj
    case kind: FunctionStepKind
    of FSK_STATEMENT: statement: Statement
    of FSK_MATCH: match: Match

proc new_function_step*(statement: Statement): FunctionStep =
  FunctionStep(kind: FSK_STATEMENT, statement: statement)

proc new_function_step*(match: Match): FunctionStep =
  FunctionStep(kind: FSK_MATCH, match: match)

# proc location(step: FunctionStep): Location =
#   case step.kind:
#   of FSK_STATEMENT: step.statement.location
#   of FSK_MATCH: step.statement.location

proc asl(step: FunctionStep, indent: string): seq[string] =
  case step.kind:
  of FSK_STATEMENT: @[step.statement.asl]
  of FSK_MATCH: step.match.asl(indent)

type Function* = ref object of RootObj
  def: FunctionDefinition
  steps: seq[FunctionStep]

proc new_function*(def: FunctionDefinition, steps: seq[
    FunctionStep]): Result[Function, string] =
  if steps.len == 0:
    return err(fmt"{def.location} function `{def.name.asl}` must have at least one statement")
  ok(Function(def: def, steps: steps))

proc location(function: Function): Location =
  function.def.location

proc name(function: Function): Identifier =
  function.def.name

proc asl(function: Function, indent: string): seq[string] =
  let header = function.def.asl

  var lines: seq[string]
  for step in function.steps:
    for line in step.asl(indent):
      lines.add(indent & line)

  return (@[header] & lines)

type
  GenericKind = enum
    GK_DEFAULT, GK_CONSTRAINED
  Generic* = ref object of RootObj
    name: Identifier
    location: Location
    case kind: GenericKind
    of GK_DEFAULT: discard
    of GK_CONSTRAINED: defs: seq[FunctionDefinition]

proc new_generic*(name: Identifier, location: Location): Generic =
  Generic(kind: GK_DEFAULT, name: name, location: location)

proc new_generic*(name: Identifier, defs: seq[FunctionDefinition],
    location: Location): Result[Generic, string] =
  var defs_map: Table[Hash, int]
  for index, def in defs.pairs:
    let def_hash = def.hash
    if def_hash in defs_map:
      let predefined_def_location = defs[defs_map[def_hash]].location
      return err(fmt"{def.location} generic constraint `{def.name.asl}` is already defined at {predefined_def_location}")
    defs_map[def_hash] = index

  ok(Generic(kind: GK_CONSTRAINED, name: name, defs: defs, location: location))

proc asl(generic: Generic, indent: string): seq[string] =
  case generic.kind:
  of GK_DEFAULT:
    @[fmt"generic {generic.name.asl}"]
  of GK_CONSTRAINED:
    let header = fmt"generic {generic.name.asl}:"

    var defs: seq[string]
    for def in generic.defs:
      defs.add(indent & def.asl)

    @[header] & defs

type ModuleDefinition* = ref object of RootObj
  name: Identifier
  location: Location

proc new_module_definition*(name: Identifier,
    location: Location): ModuleDefinition =
  ModuleDefinition(name: name, location: location)

proc asl(def: ModuleDefinition): string =
  fmt"module {def.name.asl}:"

type Module* = ref object of RootObj
  def: ModuleDefinition
  generics: seq[Generic]
  generics_map: Table[Identifier, int]
  structs: seq[Struct]
  default_struct_index: int
  structs_map: Table[Identifier, int]
  functions: seq[Function]
  functions_map: Table[Hash, int]

proc new_module*(def: ModuleDefinition, generics: seq[Generic], structs: seq[
    Struct], functions: seq[Function]): Result[Module, string] =
  if generics.len + structs.len + functions.len == 0:
    return err(fmt"{def.location} module can not be empty")

  if generics.len > 0 and structs.len + functions.len == 0:
    return err(fmt"{def.location} module can not only contain generics")

  var generics_map: Table[Identifier, int]
  for index, generic in generics:
    if generic.name in generics_map:
      let predefined_generic_location = generics[generics_map[
          generic.name]].location
      return err(fmt"{generic.location} generic `{generic.name.asl}` is already defined at {predefined_generic_location}")
    generics_map[generic.name] = index

  var structs_map: Table[Identifier, int]
  var default_struct_index = -1
  for index, struct in structs:
    case struct.def.kind:
    of SDK_DEFAULT:
      if default_struct_index != -1:
        let predefined_default_struct_location = structs[
            default_struct_index].location
        return err(fmt"{struct.location} default struct is already defined at {predefined_default_struct_location}")
    of SDK_NAMED:
      if struct.name in generics_map:
        let generic = generics[generics_map[struct.name]]
        return err(fmt"{struct.location} struct `{struct.name.asl}` name conflicts with generic `{generic.name.asl}` at {generic.location}")

      if struct.name in structs_map:
        let predefined_struct_location = structs[structs_map[
            struct.name]].location
        return err(fmt"{struct.location} struct `{struct.name.asl}` is already defined at {predefined_struct_location}")

      structs_map[struct.name] = index

  var functions_map: Table[Hash, int]
  for index, function in functions:
    if function.name in generics_map:
      let generic = generics[generics_map[function.name]]
      return err(fmt"{function.location} function `{function.name.asl}` name conflicts with generic `{generic.name.asl}` at {generic.location}")

    if function.name in structs_map:
      let struct = structs[structs_map[function.name]]
      return err(fmt"{function.location} function `{function.name.asl}` name conflicts with generic `{struct.name.asl}` at {struct.location}")

    let def_hash = function.def.hash
    if def_hash in functions_map:
      let predefined_function_location = functions[functions_map[
          def_hash]].location
      return err(fmt"{function.location} function `{function.name.asl}` is already defined at {predefined_function_location}")

    functions_map[def_hash] = index

  ok(Module(def: def, structs: structs, structs_map: structs_map,
      default_struct_index: default_struct_index, generics: generics,
      generics_map: generics_map, functions: functions,
      functions_map: functions_map))

proc name(module: Module): Identifier =
  module.def.name

proc location(module: Module): Location =
  module.def.location

proc asl(module: Module, indent: string): seq[string] =
  let header = module.def.asl
  var lines: seq[string]
  for generic in module.generics:
    for line in generic.asl(indent):
      lines.add(indent & line)
  lines.add("\n")
  for struct in module.structs:
    for line in struct.asl(indent):
      lines.add(indent & line)
  lines.add("\n")
  for function in module.functions:
    for line in function.asl(indent):
      lines.add(indent & line)
    lines.add("\n")

  return (@[header] & lines)

type File* = ref object of RootObj
  path: string
  indent: int
  modules: seq[Module]
  modules_map: Table[Identifier, int]
  functions: seq[Function]
  functions_map: Table[Hash, int]

proc new_file*(path: string, modules: seq[Module], functions: seq[Function],
    indent: int): Result[File, string] =
  if functions.len + modules.len == 0:
    return err(fmt"{path} file can not be empty")

  # NOTE: Build index to enable module look by name
  var modules_map: Table[Identifier, int]
  for index, module in modules.pairs:
    # NOTE: Validation for module name collisions
    if module.name in modules_map:
      let predefined_module_location = modules[modules_map[
          module.name]].location
      return err(fmt"{module.location} module `{module.name.asl}` is already defined at {predefined_module_location}")
    modules_map[module.name] = index

  # NOTE: Build index to enable function look up by definition
  var functions_map: Table[Hash, int]
  for index, function in functions:
    # NOTE: Validate module and function name collisions
    if function.name in modules_map:
      let module = modules[modules_map[function.name]]
      return err(fmt"{function.location} function `{function.name.asl}` conflicts with module `{module.name.asl}` at {module.location}")

    # NOTE: Validate function definition collisions
    let def_hash = function.def.hash
    if def_hash in functions_map:
      let predefined_function_location = functions[functions_map[
          def_hash]].location
      return err(fmt"{function.location} function `{function.name.asl}` is already defined at {predefined_function_location}")
    functions_map[def_hash] = index

  ok(File(path: path, modules: modules, modules_map: modules_map,
      functions: functions, functions_map: functions_map, indent: indent))

proc asl*(file: File): string =
  var lines: seq[string]
  let indent = " ".repeat(file.indent)

  for module in file.modules:
    for line in module.asl(indent):
      lines.add(line)
    lines.add("\n")

  for function in file.functions:
    for line in function.asl(indent):
      lines.add(line)
    lines.add("\n")

  lines.map_it(it.strip(leading = false)).join("\n").replace(re"\n{3,}", "\n\n")
