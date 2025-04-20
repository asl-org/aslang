import strformat, strutils, sequtils

type
  Location* = object
    filename*: string
    line*: int = 1
    column*: int = 1
    index*: int = 0

proc `$`*(location: Location): string =
  fmt"{location.filename}({location.line}, {location.column})"

type Identifier* = ref object of RootObj
  name: string
  location: Location

proc `$`*(identifier: Identifier): string = identifier.name

proc new_identifier*(name: string, location: Location): Identifier =
  Identifier(name: name, location: location)

type
  LiteralKind = enum
    LK_INTEGER, LK_FLOAT, LK_STRING
  Literal* = ref object of RootObj
    location: Location
    case kind: LiteralKind
    of LK_INTEGER: integer_value: string
    of LK_FLOAT: float_value: string
    of LK_STRING: string_value: string

proc `$`*(literal: Literal): string =
  case literal.kind:
    of LK_INTEGER: literal.integer_value
    of LK_FLOAT: literal.float_value
    of LK_STRING: "\"" & literal.string_value & "\""

proc new_int_literal*(value: string, location: Location): Literal =
  Literal(kind: LK_INTEGER, integer_value: value, location: location)

proc new_float_literal*(value: string, location: Location): Literal =
  Literal(kind: LK_FLOAT, float_value: value, location: location)

proc new_str_literal*(value: string, location: Location): Literal =
  Literal(kind: LK_STRING, string_value: value, location: location)

type
  ArgumentKind = enum
    AK_LITERAL, AK_IDENTIFIER
  Argument* = ref object of RootObj
    location: Location
    case kind: ArgumentKind
    of AK_LITERAL: literal: Literal
    of AK_IDENTIFIER: identifier: Identifier

proc `$`*(argument: Argument): string =
  case argument.kind:
  of AK_LITERAL: $(argument.literal)
  of AK_IDENTIFIER: $(argument.identifier)

proc new_literal_argument*(literal: Literal, location: Location): Argument =
  Argument(kind: AK_LITERAL, literal: literal, location: location)

proc new_identifier_argument*(identifier: Identifier,
    location: Location): Argument =
  Argument(kind: AK_IDENTIFIER, identifier: identifier, location: location)

type Field* = ref object of RootObj
  name: Identifier
  value: Argument
  location: Location

proc `$`*(field: Field): string =
  fmt"{field.name}: {field.value}"

proc new_field*(name: Identifier, value: Argument, location: Location): Field =
  Field(name: name, value: value, location: location)

type Struct* = ref object of RootObj
  fields: seq[Field]
  location: Location

proc `$`*(literal: Struct): string =
  let fields = literal.fields.map(proc(f: Field): string = $(f)).join(", ")
  "{ " & fields & " }"

proc new_struct*(fields: seq[Field], location: Location): Struct =
  Struct(fields: fields, location: location)

type ModuleRef* = ref object of RootObj
  refs*: seq[Identifier]
  location: Location

proc `$`*(module_ref: ModuleRef): string =
  module_ref.refs.map(proc(m: Identifier): string = $(m)).join(".")

proc new_module_ref*(refs: seq[Identifier], location: Location): ModuleRef =
  ModuleRef(refs: refs, location: location)

type Initializer* = ref object of RootObj
  result: Identifier
  module: ModuleRef
  struct: Struct
  location: Location

proc `$`*(init: Initializer): string =
  fmt"{init.result} = {init.module} {init.struct}"

proc new_initializer*(dest: Identifier, module: ModuleRef,
    struct: Struct, location: Location): Initializer =
  Initializer(result: dest, module: module, struct: struct, location: location)

type ArgumentList* = ref object of RootObj
  arguments: seq[Argument]
  location: Location

proc `$`*(arglist: ArgumentList): string =
  let args = arglist.arguments.map(proc(a: Argument): string = $(a)).join(", ")
  fmt"({args})"

proc new_argument_list*(args: seq[Argument], location: Location): ArgumentList =
  ArgumentList(arguments: args, location: location)

type Functioncall* = ref object of RootObj
  result: Identifier
  module: ModuleRef
  arglist: ArgumentList
  location: Location

proc `$`*(fncall: Functioncall): string =
  fmt"{fncall.result} = {fncall.module}{fncall.arglist}"

proc new_function_call*(dest: Identifier, module: ModuleRef,
    arglist: ArgumentList, location: Location): Functioncall =
  Functioncall(result: dest, module: module, arglist: arglist,
      location: location)

type
  StatementKind = enum
    SK_INITIALIZER, SK_FUNCTION_CALL

  Statement* = ref object of RootObj
    location: Location
    case kind: StatementKind
    of SK_INITIALIZER: init: Initializer
    of SK_FUNCTION_CALL: fncall: Functioncall

proc `$`*(statement: Statement): string =
  case statement.kind:
  of SK_INITIALIZER: $(statement.init)
  of SK_FUNCTION_CALL: $(statement.fncall)

proc new_init_statement*(init: Initializer, location: Location): Statement =
  Statement(kind: SK_INITIALIZER, init: init, location: location)

proc new_fncall_statement*(fncall: Functioncall,
    location: Location): Statement =
  Statement(kind: SK_FUNCTION_CALL, fncall: fncall, location: location)

type Program* = ref object of RootObj
  statements*: seq[Statement]
  location: Location

proc `$`*(program: Program): string =
  program.statements.map(proc(s: Statement): string = $(s)).join("\n")

proc new_program*(statements: seq[Statement], location: Location): Program =
  Program(statements: statements, location: location)
