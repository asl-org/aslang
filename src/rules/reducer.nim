import parse_result
export parse_result

import strutils, sequtils

# raw.nim
proc raw_string_reducer*(location: Location, value: string): ParseResult =
  var updated = location
  for x in value:
    if x == '\n': updated.line += 1; updated.col = 1
    else: updated.col += 1
  value.new_atom(location).to_parse_result()

proc raw_parts_reducer*(location: Location, parts: seq[seq[seq[
    ParseResult]]]): ParseResult =
  var value: string
  for prod in parts:
    for sym in prod:
      for item in sym:
        value.add($(item))
  value.new_atom(location).to_parse_result()

# identifier.nim
proc identifier_reducer*(location: Location, parts: seq[seq[seq[
    ParseResult]]]): ParseResult =
  let head = $(parts[0][0][0].atom)
  let tail = parts[0][1].map(proc(x: ParseResult): string = $(x.atom)).join("")
  let identifier = new_identifier(head & tail, location)
  identifier.to_parse_result()

# keyword_arg.nim
proc keyword_arg_def_reducer*(location: Location, parts: seq[seq[seq[
    ParseResult]]]): ParseResult =
  let name = parts[0][0][0].identifier
  let module = parts[0][4][0].identifier
  module.new_arg_def(name).to_parse_result()

proc leading_keyword_arg_def_reducer*(location: Location, parts: seq[seq[seq[
    ParseResult]]]): ParseResult =
  parts[0][0][0]

# struct.nim
proc struct_def_reducer*(location: Location, parts: seq[seq[seq[
    ParseResult]]]): ParseResult =
  let kwarg_defs = (parts[0][2] & parts[0][3]).map(proc(
      x: ParseResult): ArgumentDefinition = x.arg_def)
  kwarg_defs.to_parse_result()

proc union_def_reducer*(location: Location, parts: seq[seq[seq[
    ParseResult]]]): ParseResult =
  let name = parts[0][0][0].identifier
  let fields = parts[0][2][0].arg_def_list
  name.new_union_def(fields, location).to_parse_result()

proc keyword_arg_value_reducer*(location: Location, parts: seq[seq[seq[
    ParseResult]]]): ParseResult =
  if parts[0].len > 0:
    return parts[0][0][0].atom.new_keyword_arg_value().to_parse_result()
  if parts[1].len > 0:
    return parts[1][0][0].identifier.new_keyword_arg_value().to_parse_result()

proc keyword_arg_reducer*(location: Location, parts: seq[seq[seq[
    ParseResult]]]): ParseResult =
  let name = parts[0][0][0].identifier
  let value = parts[0][4][0].kwarg_val
  name.new_keyword_arg(value).to_parse_result()

proc leading_keyword_arg_reducer*(location: Location, parts: seq[seq[seq[
    ParseResult]]]): ParseResult =
  parts[0][0][0]

# struct.nim
proc struct_reducer*(location: Location, parts: seq[seq[seq[
    ParseResult]]]): ParseResult =
  let kwargs = (parts[0][2] & parts[0][3]).map(proc(
      x: ParseResult): KeywordArg = x.kwarg)
  kwargs.new_struct(location).to_parse_result()

# literal.nim
proc literal_reducer*(location: Location, parts: seq[seq[seq[
    ParseResult]]]): ParseResult =
  if parts[0].len > 0:
    return parts[0][0][0].atom.new_literal().to_parse_result

  if parts[1].len > 0:
    return parts[1][0][0].struct.new_literal().to_parse_result

proc leading_module_ref_reducer*(location: Location, parts: seq[seq[seq[
    ParseResult]]]): ParseResult =
  parts[0][0][0].identifier.to_parse_result()

proc module_ref_reducer*(location: Location, parts: seq[seq[seq[
    ParseResult]]]): ParseResult =
  let refs = (parts[0][0] & parts[0][1]).map(proc(
      x: ParseResult): Identifier = x.identifier)
  refs.new_module_ref(location).to_parse_result()

# init.nim
proc init_reducer*(location: Location, parts: seq[seq[seq[
    ParseResult]]]): ParseResult =
  let module_ref = parts[0][0][0].module_ref
  let literal = parts[0][2][0].literal
  new_init(module_ref, literal, location).to_parse_result()

# argument.nim
proc arg_reducer*(location: Location, parts: seq[seq[seq[
    ParseResult]]]): ParseResult =
  if parts[0].len > 0:
    let target = parts[0][0][0].identifier
    let field = parts[0][2][0].identifier
    return target.new_struct_getter(field, location).new_argument().to_parse_result()
  elif parts[1].len > 0:
    return parts[1][0][0].identifier.new_argument().to_parse_result()
  elif parts[2].len > 0:
    return parts[2][0][0].literal.new_argument().to_parse_result()

# arglist.nim
proc leading_arg_reducer*(location: Location, parts: seq[seq[seq[
    ParseResult]]]): ParseResult =
  parts[0][0][0]

proc arglist_reducer*(location: Location, parts: seq[seq[seq[
    ParseResult]]]): ParseResult =
  let args = (parts[0][2] & parts[0][3]).map(proc(
      x: ParseResult): Argument = x.arg)
  args.to_parse_result()

# fncall.nim
proc fncall_reducer*(location: Location, parts: seq[seq[seq[
    ParseResult]]]): ParseResult =
  let module_name = parts[0][0][0].identifier
  let fn_name = parts[0][2][0].identifier
  let arglist = parts[0][3][0].arglist
  new_fncall(module_name, fn_name, arglist, location).to_parse_result()

# value.nim
proc value_reducer*(location: Location, parts: seq[seq[seq[
    ParseResult]]]): ParseResult =
  if parts[0].len > 0:
    return parts[0][0][0].init.new_value().to_parse_result()

  if parts[1].len > 0:
    return parts[1][0][0].fncall.new_value().to_parse_result()

  if parts[2].len > 0:
    return parts[2][0][0].identifier.new_value().to_parse_result()

# assignment.nim
proc assignment_reducer*(location: Location, parts: seq[seq[seq[
    ParseResult]]]): ParseResult =
  let result_var_name = parts[0][0][0].identifier
  let value = parts[0][4][0].expression
  new_assignment(result_var_name, value, location).to_parse_result()

# macro_call.nim
proc fn_def_reducer*(location: Location, parts: seq[seq[seq[
    ParseResult]]]): ParseResult =
  let name = parts[0][2][0].identifier
  let arg_def_list = parts[0][4][0].arg_def_list
  let returns = parts[0][8][0].identifier
  new_fn_def(name, returns, arg_def_list).to_parse_result()

proc arg_def_reducer*(location: Location, parts: seq[seq[seq[
    ParseResult]]]): ParseResult =
  let module = parts[0][0][0].identifier
  let name = parts[0][2][0].identifier
  new_arg_def(module, name).to_parse_result()

proc leading_arg_def_reducer*(location: Location, parts: seq[seq[seq[
    ParseResult]]]): ParseResult =
  parts[0][0][0]

proc arg_def_list_reducer*(location: Location, parts: seq[seq[seq[
    ParseResult]]]): ParseResult =
  var defs: seq[ArgumentDefinition]
  let arg_def_list = parts[0][2] & parts[0][3]
  for arg_def in arg_def_list: defs.add(arg_def.arg_def)
  defs.to_parse_result()

proc app_def_reducer*(location: Location, parts: seq[seq[seq[
    ParseResult]]]): ParseResult =
  let name = parts[0][2][0].identifier
  name.new_app_def(location).to_parse_result()

proc module_def_reducer*(location: Location, parts: seq[seq[seq[
    ParseResult]]]): ParseResult =
  let name = parts[0][2][0].identifier
  name.new_module_def(location).to_parse_result()

proc match_def_reducer*(location: Location, parts: seq[seq[seq[
    ParseResult]]]): ParseResult =
  let name = parts[0][2][0].identifier
  name.new_match_def().to_parse_result()

proc case_pattern_reducer*(location: Location, parts: seq[seq[seq[
    ParseResult]]]): ParseResult =
  if parts[0].len > 0:
    return parts[0][0][0].atom.new_case_pattern(location).to_parse_result()
  elif parts[1].len > 0:
    let module_ref = parts[1][0][0].module_ref
    let struct_value = parts[1][2][0].arg_def_list
    return module_ref.new_case_pattern(struct_value,
        location).to_parse_result()

proc case_def_reducer*(location: Location, parts: seq[seq[seq[
    ParseResult]]]): ParseResult =
  let case_pattern = parts[0][2][0].case_pattern
  case_pattern.new_case_def(location).to_parse_result()

proc else_def_reducer*(location: Location, parts: seq[seq[seq[
    ParseResult]]]): ParseResult =
  new_else_def().to_parse_result()

proc struct_macro_reducer*(location: Location, parts: seq[seq[seq[
    ParseResult]]]): ParseResult =
  new_struct_macro(location).to_parse_result()

proc union_macro_reducer*(location: Location, parts: seq[seq[seq[
    ParseResult]]]): ParseResult =
  new_union_macro(location).to_parse_result()

proc macro_call_reducer*(location: Location, parts: seq[seq[seq[
    ParseResult]]]): ParseResult =
  var macro_call: MacroCall
  if parts[0].len > 0:
    macro_call = new_macro_call(parts[0][0][0].fn_def)
  elif parts[1].len > 0: # app def
    macro_call = new_macro_call(parts[1][0][0].module_def)
  elif parts[2].len > 0: # module def
    macro_call = new_macro_call(parts[2][0][0].module_def)
  elif parts[3].len > 0: # match def
    macro_call = new_macro_call(parts[3][0][0].match_def)
  elif parts[4].len > 0: # case def
    macro_call = new_macro_call(parts[4][0][0].case_def)
  elif parts[5].len > 0: # else def
    macro_call = new_macro_call(parts[5][0][0].else_def)
  elif parts[6].len > 0: # struct macro
    macro_call = new_macro_call(parts[6][0][0].struct_macro)
  elif parts[7].len > 0: # union macro
    macro_call = new_macro_call(parts[7][0][0].union_macro)
  macro_call.to_parse_result()

# statement.nim
proc statement_reducer*(location: Location, parts: seq[seq[seq[
    ParseResult]]]): ParseResult =
  var statement: Statement
  if parts[0].len > 0:
    statement = new_statement(parts[0][0][0].assign)
  elif parts[1].len > 0:
    statement = new_statement(parts[1][0][0].expression)

  statement.to_parse_result()

# program.nim

proc comment_reducer*(location: Location, parts: seq[seq[seq[
    ParseResult]]]): ParseResult =
  var comment: string
  for x in parts[0][1]: comment.add($(x.atom))
  new_comment(comment).to_parse_result()

proc line_reducer*(location: Location, parts: seq[seq[seq[
    ParseResult]]]): ParseResult =
  var pr: ParseResult
  if parts[0].len > 0:
    let spaces = parts[0][0].len
    pr = parts[0][1][0].macro_call.new_line(spaces).to_parse_result()
  elif parts[1].len > 0:
    let spaces = parts[1][0].len
    pr = parts[1][1][0].arg_def.new_line(spaces).to_parse_result()
  elif parts[2].len > 0:
    let spaces = parts[2][0].len
    pr = parts[2][1][0].statement.new_line(spaces).to_parse_result()
  elif parts[3].len > 0:
    let spaces = parts[3][0].len
    pr = parts[3][1][0].union_def.new_line(spaces).to_parse_result()
  elif parts[4].len > 0:
    let spaces = parts[4][0].len
    pr = parts[4][1][0].comment.new_line(spaces).to_parse_result()
  else:
    let spaces = parts[5][0].len
    pr = new_empty_line(spaces).to_parse_result()
  pr

proc leading_line_reducer*(location: Location, parts: seq[seq[seq[
    ParseResult]]]): ParseResult =
  parts[0][0][0]

proc program_reducer*(location: Location, parts: seq[seq[seq[
    ParseResult]]]): ParseResult =
  let lines = parts[0][0] & parts[0][1]
  let program = lines.map(proc(x: ParseResult): Line = x.line).new_program()
  program.to_parse_result()

