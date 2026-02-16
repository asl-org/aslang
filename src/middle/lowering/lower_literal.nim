import ../analyzer
import ../../ir/constructors
import lower_module_ref

proc generate_typedef*(literal: AnalyzedLiteral, prefix: string): CDecl =
  c_typedef(literal.name, prefix)

proc generate_literal_init*(literal: AnalyzedLiteralInit,
    result_arg: string): CStmt =
  c_decl_var(literal.module_ref.generate_type, result_arg,
      c_lit(literal.literal.asl))
