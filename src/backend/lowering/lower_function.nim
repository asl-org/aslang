import ../../middle/analyzer
import ../ir/constructors
import lower_func_def
import lower_expression

proc generate_user_function*(function: AnalyzedUserFunction): seq[CDecl] =
  let decl = function.def.generate_func_decl
  # Build body
  var body: seq[CStmt]
  for statement in function.statements:
    body.add(statement.generate_statement)
  let last_arg = function.statements[^1].arg.name.asl
  body.add(c_return(c_ident(last_arg)))
  # Convert the declaration into a definition
  return @[c_func_def(decl.func_return, decl.func_name,
      decl.func_params, body)]

proc generate_function*(function: AnalyzedFunction): seq[CDecl] =
  case function.kind:
  of AFK_EXTERN: @[]
  of AFK_USER: function.user.generate_user_function
