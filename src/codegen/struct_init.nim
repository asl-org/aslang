import strformat, hashes, strutils

import analyzer
import module_ref
import arg
import struct_ref

proc c*(struct_init: AnalyzedStructInit, result_arg: string): seq[string] =
  var lines: seq[string]
  var args: seq[string]
  for index in 0..<struct_init.fields.len:
    let original_field = struct_init.data_ref.original_fields[index]
    let concrete_field = struct_init.data_ref.fields[index]
    let field_arg = struct_init.fields[index]
    case original_field.module_ref.kind:
    of AMRK_GENERIC:
      case concrete_field.module_ref.kind:
      of AMRK_GENERIC: args.add(field_arg.c)
      else:
        let arg_name = fmt"__asl_arg_{concrete_field.location.hash.to_hex}"
        lines.add(fmt"Pointer {arg_name} = System_box_{concrete_field.module_ref.c}({field_arg.c});")
        args.add(arg_name)
    else: args.add(field_arg.c)

  let args_str = args.join(", ")
  lines.add(fmt"Pointer {result_arg} = {struct_init.data_ref.c}_init({args_str});")
  return lines
