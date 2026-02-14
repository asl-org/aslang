import strformat, strutils

import ../analyzer
import ../ir/constructors
import ../emitter/emit
import gen_module_ref
import gen_arg
import gen_struct_ref
import gen_literal

proc generate_struct_init*(struct_init: AnalyzedStructInit,
    result_arg: string): seq[CStmt] =
  var stmts: seq[CStmt]
  var args: seq[CExpr]
  for index in 0..<struct_init.fields.len:
    let original_field = struct_init.data_ref.original_fields[index]
    let concrete_field = struct_init.data_ref.fields[index]
    let field_arg = struct_init.fields[index]
    case original_field.module_ref.kind:
    of AMRK_GENERIC:
      case concrete_field.module_ref.kind:
      of AMRK_GENERIC: args.add(c_ident(field_arg.generate_arg))
      else:
        let arg_name = fmt"__asl_arg_{concrete_field.location.hash.to_hex}"
        stmts.add(c_decl_var(c_pointer(), arg_name,
            c_call(fmt"System_box_{concrete_field.module_ref.generate_type.emit}",
            @[c_ident(field_arg.generate_arg)])))
        args.add(c_ident(arg_name))
    else: args.add(c_ident(field_arg.generate_arg))

  stmts.add(c_decl_var(c_pointer(), result_arg,
      c_call(fmt"{struct_init.data_ref.generate_data_ref_name}_init", args)))
  return stmts

proc generate_initializer*(init: AnalyzedInitializer,
    result_arg: string): seq[CStmt] =
  case init.kind:
  of RIK_LITERAL: @[init.literal.generate_literal_init(result_arg)]
  of RIK_STRUCT: init.struct.generate_struct_init(result_arg)
