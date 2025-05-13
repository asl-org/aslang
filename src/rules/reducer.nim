import parse_result
export parse_result

import strutils, sequtils

# raw.nim
proc raw_string_reducer*(location: Location, value: string): (Location, ParseResult) =
  var updated = location
  for x in value:
    if x == '\n': updated.line += 1; updated.col = 1
    else: updated.col += 1
  (updated, to_parse_result(value))

proc raw_parts_reducer*(location: Location, parts: seq[seq[seq[
    ParseResult]]]): (Location, ParseResult) =
  var value: string
  for prod in parts:
    for sym in prod:
      for item in sym:
        value.add($(item))
  (location, to_parse_result(value))

# identifier.nim
proc identifier_reducer*(location: Location, parts: seq[seq[seq[
    ParseResult]]]): (Location, ParseResult) =
  let head = parts[0][0][0].raw_string
  let tail = parts[0][1].map(proc(x: ParseResult): string = x.raw_string).join("")
  let identifier = new_identifier(head & tail, location)
  (location, identifier.to_parse_result())

# init.nim
proc init_reducer*(location: Location, parts: seq[seq[seq[
    ParseResult]]]): (Location, ParseResult) =
  let module_name = parts[0][0][0].identifier
  let literal = parts[0][2][0].raw_string
  let pr = new_init(module_name, literal, location).to_parse_result()

  (location, pr)

# arglist.nim
proc leading_arg_reducer*(location: Location, parts: seq[seq[seq[
    ParseResult]]]): (Location, ParseResult) = (location, parts[0][0][0])

proc arglist_reducer*(location: Location, parts: seq[seq[seq[
    ParseResult]]]): (Location, ParseResult) =
  let args = (parts[0][2] & parts[0][3]).map(proc(
      x: ParseResult): Identifier = x.identifier)
  let pr = new_arglist(args, location).to_parse_result()
  (location, pr)

# fncall.nim
proc fncall_reducer*(location: Location, parts: seq[seq[seq[
    ParseResult]]]): (Location, ParseResult) =
  let module_name = parts[0][0][0].identifier
  let fn_name = parts[0][2][0].identifier
  let arglist = parts[0][3][0].arglist
  let pr = new_fncall(module_name, fn_name, arglist).to_parse_result()

  (location, pr)

# value.nim
proc value_reducer*(location: Location, parts: seq[seq[seq[
    ParseResult]]]): (Location, ParseResult) =
  var pr: ParseResult
  if parts[0].len > 0:
    pr = parts[0][0][0].init.new_value().to_parse_result()
  elif parts[1].len > 0:
    pr = parts[1][0][0].fncall.new_value().to_parse_result()

  (location, pr)

# assignment.nim
proc assignment_reducer*(location: Location, parts: seq[seq[seq[
    ParseResult]]]): (Location, ParseResult) =
  let result_var_name = parts[0][0][0].identifier
  let value = parts[0][4][0].value
  let pr = new_assignment(result_var_name, value, location).to_parse_result()

  (location, pr)

# macro_call.nim
proc fn_def_reducer*(location: Location, parts: seq[seq[seq[
    ParseResult]]]): (Location, ParseResult) =
  let name = parts[0][2][0].identifier
  let arg_def_list = parts[0][4][0].arg_def_list
  let returns = parts[0][8][0].identifier

  (location, new_fn_def(name, returns, arg_def_list).to_parse_result())

proc arg_def_reducer*(location: Location, parts: seq[seq[seq[ParseResult]]]): (
    Location, ParseResult) =
  let module = parts[0][0][0].identifier
  let name = parts[0][2][0].identifier

  (location, new_arg_def(module, name).to_parse_result())

proc leading_arg_def_reducer*(location: Location, parts: seq[seq[seq[
    ParseResult]]]): (Location, ParseResult) = (location, parts[0][0][0])

proc arg_def_list_reducer*(location: Location, parts: seq[seq[seq[
    ParseResult]]]): (Location, ParseResult) =
  var defs: seq[ArgumentDefinition]
  let arg_def_list = parts[0][2] & parts[0][3]
  for arg_def in arg_def_list: defs.add(arg_def.arg_def)
  (location, new_arg_def_list(defs).to_parse_result())

proc app_def_reducer*(location: Location, parts: seq[seq[seq[
    ParseResult]]]): (Location, ParseResult) =
  let name = parts[0][2][0].identifier
  (location, name.new_app_def().to_parse_result())

proc module_def_reducer*(location: Location, parts: seq[seq[seq[
    ParseResult]]]): (Location, ParseResult) =
  let name = parts[0][2][0].identifier
  (location, name.new_module_def().to_parse_result())

proc struct_def_reducer*(location: Location, parts: seq[seq[seq[
    ParseResult]]]): (Location, ParseResult) =
  let name = parts[0][2][0].identifier
  (location, name.new_struct_def().to_parse_result())

proc union_def_reducer*(location: Location, parts: seq[seq[seq[
    ParseResult]]]): (Location, ParseResult) =
  let name = parts[0][2][0].identifier
  (location, name.new_union_def().to_parse_result())

proc macro_call_reducer*(location: Location, parts: seq[seq[seq[
    ParseResult]]]): (Location, ParseResult) =
  var macro_call: MacroCall
  if parts[0].len > 0:
    macro_call = new_macro_call(parts[0][0][0].fn_def)
  elif parts[1].len > 0: # app def
    macro_call = new_macro_call(parts[1][0][0].module_def)
  elif parts[2].len > 0: # module def
    macro_call = new_macro_call(parts[2][0][0].module_def)
  elif parts[3].len > 0: # struct def
    macro_call = new_macro_call(parts[3][0][0].module_def)
  elif parts[4].len > 0: # union def
    macro_call = new_macro_call(parts[4][0][0].module_def)

  (location, macro_call.to_parse_result())

# statement.nim
proc statement_reducer*(location: Location, parts: seq[seq[seq[
    ParseResult]]]): (Location, ParseResult) =
  var statement: Statement
  if parts[0].len > 0:
    statement = new_statement(parts[0][0][0].assign)
  elif parts[1].len > 0:
    statement = new_statement(parts[1][0][0].fncall)

  (location, to_parse_result(statement))

# program.nim

proc comment_reducer*(location: Location, parts: seq[seq[seq[ParseResult]]]): (
    Location, ParseResult) =
  var comment: string
  for x in parts[0][1]: comment.add(x.raw_string)
  let pr = new_comment(comment).to_parse_result()
  (location, pr)

proc line_reducer*(location: Location, parts: seq[seq[seq[
    ParseResult]]]): (Location, ParseResult) =
  var pr: ParseResult
  if parts[0].len > 0:
    let spaces = parts[0][0].len
    pr = parts[0][1][0].statement.new_line(spaces).to_parse_result()
  elif parts[1].len > 0:
    let spaces = parts[1][0].len
    pr = parts[1][1][0].macro_call.new_line(spaces).to_parse_result()
  elif parts[2].len > 0:
    let spaces = parts[2][0].len
    pr = parts[2][1][0].comment.new_line(spaces).to_parse_result()
  else:
    let spaces = parts[3][0].len
    pr = new_empty_line(spaces).to_parse_result()
  (location, pr)

proc leading_line_reducer*(location: Location, parts: seq[seq[seq[
    ParseResult]]]): (Location, ParseResult) = (location, parts[0][0][0])

proc program_reducer*(location: Location, parts: seq[seq[seq[ParseResult]]]): (
    Location, ParseResult) =
  let lines = parts[0][0] & parts[0][1]
  let program = lines.map(proc(x: ParseResult): Line = x.line).new_program()
  let pr = program.to_parse_result()
  (location, pr)

