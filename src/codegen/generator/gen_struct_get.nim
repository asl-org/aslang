import strformat

import ../analyzer
import ../ir/constructors
import gen_module_ref

proc generate_struct_get*(struct_get: AnalyzedStructGet,
    result_arg: string): CStmt =
  let field_type = struct_get.field.module_ref.generate_type
  let getter_name = fmt"{struct_get.variable.module_ref.name}_get_{struct_get.field.name.asl}"
  c_decl_var(field_type, result_arg,
      c_call(getter_name, @[c_ident(struct_get.variable.name.asl)]))
