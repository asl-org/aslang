import parse_result

proc fn_macro_reducer*(location: Location, parts: seq[seq[seq[
    ParserResult]]]): (Location, ParserResult) =
  let name = parts[0][2][0].content
  let module = parts[0][6][0].content

  (location, new_fn_macro(name, module).to_parse_result())

proc arg_def_reducer*(location: Location, parts: seq[seq[seq[ParserResult]]]): (
    Location, ParserResult) =
  let module = parts[0][0][0].content
  let name = parts[0][2][0].content

  (location, new_arg_def(module, name).to_parse_result())

proc leading_arg_def_reducer*(location: Location, parts: seq[seq[seq[
    ParserResult]]]): (Location, ParserResult) = (location, parts[0][0][0])

proc arg_def_list_reducer*(location: Location, parts: seq[seq[seq[
    ParserResult]]]): (Location, ParserResult) =
  var defs: seq[ArgumentDefintion]
  let arg_def_list = parts[0][2] & parts[0][3]
  for arg_def in arg_def_list: defs.add(arg_def.arg_def)
  (location, new_arg_def_list(defs).to_parse_result())

proc args_macro_reducer*(location: Location, parts: seq[seq[seq[
    ParserResult]]]): (Location, ParserResult) = (location, parts[0][2][0])

proc macro_call_reducer*(location: Location, parts: seq[seq[seq[
    ParserResult]]]): (Location, ParserResult) =
  var macro_call: MacroCall
  if parts[0].len > 0:
    macro_call = new_macro_call(parts[0][0][0].fn_macro)
  elif parts[1].len > 0:
    macro_call = new_macro_call(parts[1][0][0].arg_def_list)

  (location, macro_call.to_parse_result())
