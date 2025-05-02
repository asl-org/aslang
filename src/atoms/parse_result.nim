import raw_value
import identifier/struct
import numeric_literal/struct
import atom/struct

type
  ParseResultKind = enum
    PRK_RAW,
    PRK_IDENTIFIER,
    PRK_NUMERIC_LITERAL,
    PRK_ATOM,
    PRK_KWARG,
    # PRK_STRUCT,
    # PRK_LITERAL,
    # PRK_INITIALIZER,
    # PRK_ARGUMENT_LIST,
    # PRK_FUNCTION_CALL,
    # PRK_STATEMENT,
    # PRK_FN_MACRO,
    # PRK_ARGUMENT_DEF,
    # PRK_ARGUMENT_DEF_LIST,
    # PRK_MACRO,
    # PRK_LINE,
    # PRK_PROGRAM,

  ParseResult* = ref object of RootObj
    case kind: ParseResultKind
    of PRK_RAW: raw_value: RawValue
    of PRK_IDENTIFIER: identifier*: Identifier
    of PRK_NUMERIC_LITERAL: numeric_literal*: NumericLiteral
    of PRK_ATOM: atom*: Atom
    of PRK_KWARG: keyword_argument*: KeywordArgument
    # of PRK_STRUCT: struct_literal*: Struct
    # of PRK_LITERAL: literal*: Literal
    # of PRK_INITIALIZER: init*: Initializer
    # of PRK_ARGUMENT_LIST: arglist*: ArgumentList
    # of PRK_FUNCTION_CALL: fncall*: FunctionCall
    # of PRK_STATEMENT: statement*: Statement
    # of PRK_FN_MACRO: fn_macro*: FunctionMacro
    # of PRK_ARGUMENT_DEF: arg_def*: ArgumentDef
    # of PRK_ARGUMENT_DEF_LIST: arg_defs*: ArgumentDefList
    # of PRK_MACRO: macro_header*: MacroHeader
    # of PRK_LINE: line*: Line
    # of PRK_PROGRAM: program*: Program

proc `$`*(parse_result: ParseResult): string =
  case parse_result.kind:
  of PRK_RAW: $(parse_result.raw_value)
  of PRK_IDENTIFIER: $(parse_result.identifier)
  of PRK_NUMERIC_LITERAL: $(parse_result.numeric_literal)
  of PRK_ATOM: $(parse_result.atom)
  of PRK_KWARG: $(parse_result.keyword_argument)
  # of PRK_STRUCT: $(parse_result.struct_literal)
  # of PRK_LITERAL: $(parse_result.literal)
  # of PRK_INITIALIZER: $(parse_result.init)
  # of PRK_ARGUMENT_LIST: $(parse_result.arglist)
  # of PRK_FUNCTION_CALL: $(parse_result.fncall)
  # of PRK_STATEMENT: $(parse_result.statement)
  # of PRK_FN_MACRO: $(parse_result.fn_macro)
  # of PRK_ARGUMENT_DEF: $(parse_result.arg_def)
  # of PRK_ARGUMENT_DEF_LIST: $(parse_result.arg_defs)
  # of PRK_MACRO: $(parse_result.macro_header)
  # of PRK_LINE: $(parse_result.line)
  # of PRK_PROGRAM: $(parse_result.program)

proc new_raw_value*(raw_value: RawValue): ParseResult =
  ParseResult(kind: PRK_RAW, raw_value: raw_value)

proc new_identifier*(identifier: Identifier): ParseResult =
  ParseResult(kind: PRK_IDENTIFIER, identifier: identifier)

proc new_numeric_literal*(numeric_literal: NumericLiteral): ParseResult =
  ParseResult(kind: PRK_NUMERIC_LITERAL, numeric_literal: numeric_literal)

proc new_atom*(atom: Atom): ParseResult =
  ParseResult(kind: PRK_ATOM, atom: atom)

proc new_keyword_argument*(keyword_argument: KeywordArgument): ParseResult =
  ParseResult(kind: PRK_KWARG, keyword_argument: keyword_argument)

# proc new_struct_literal_parse_result*(struct_literal: Struct): ParseResult =
#   ParseResult(kind: PRK_STRUCT, struct_literal: struct_literal)

# proc new_literal_parse_result*(literal: Literal): ParseResult =
#   ParseResult(kind: PRK_LITERAL, literal: literal)

# proc new_initializer_parse_result*(init: Initializer): ParseResult =
#   ParseResult(kind: PRK_INITIALIZER, init: init)

# proc new_arg_list_parse_result*(arglist: ArgumentList): ParseResult =
#   ParseResult(kind: PRK_ARGUMENT_LIST, arglist: arglist)

# proc new_function_call_parse_result*(fncall: Functioncall): ParseResult =
#   ParseResult(kind: PRK_FUNCTION_CALL, fncall: fncall)

# proc new_statement_parse_result*(statement: Statement): ParseResult =
#   ParseResult(kind: PRK_STATEMENT, statement: statement)

# proc new_fn_macro_parse_result*(fn_macro: FunctionMacro): ParseResult =
#   ParseResult(kind: PRK_FN_MACRO, fn_macro: fn_macro)

# proc new_arg_def_parse_result*(arg_def: ArgumentDef): ParseResult =
#   ParseResult(kind: PRK_ARGUMENT_DEF, arg_def: arg_def)

# proc new_arg_def_list_parse_result*(arg_def_list: ArgumentDefList): ParseResult =
#   ParseResult(kind: PRK_ARGUMENT_DEF_LIST, arg_defs: arg_def_list)

# proc new_macro_header_parse_result*(macro_header: MacroHeader): ParseResult =
#   ParseResult(kind: PRK_MACRO, macro_header: macro_header)

# proc new_line_parse_result*(line: Line): ParseResult =
#   ParseResult(kind: PRK_LINE, line: line)

# proc new_program_parse_result*(program: Program): ParseResult =
#   ParseResult(kind: PRK_PROGRAM, program: program)

