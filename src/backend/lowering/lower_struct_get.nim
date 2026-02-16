import strformat

import ../../middle/analyzer
import ../ir/constructors
import lower_module_ref

proc generate_struct_get*(struct_get: AnalyzedStructGet,
    result_arg: string): seq[CStmt] =
  let field_type = struct_get.field.module_ref.generate_type
  let getter_name = fmt"{struct_get.variable.module_ref.name}_get_{struct_get.field.name.asl}"
  let id_args = struct_get.variable.module_ref.generate_impl_id_inline
  @[c_decl_var(field_type, result_arg,
      c_call(getter_name, id_args & @[c_ident(struct_get.variable.name.asl)]))]
