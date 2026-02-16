import strformat, strutils

import ../analyzer
import ../../ir/constructors
import ../../backend/emitter
import lower_fncall
import lower_initializer
import lower_struct_get
import lower_module_ref
import lower_arg_def

proc generate_match(match: AnalyzedMatch,
    result_arg: AnalyzedArgumentDefinition): seq[CStmt]

proc generate_expression*(expression: AnalyzedExpression,
    result_arg: AnalyzedArgumentDefinition): seq[CStmt] =
  case expression.kind:
  of REK_MATCH: expression.match.generate_match(result_arg)
  of REK_FNCALL: expression.fncall.generate_fncall(result_arg.name.asl)
  of REK_INIT: expression.init.generate_initializer(result_arg.name.asl)
  of REK_STRUCT_GET: expression.struct_get.generate_struct_get(
      result_arg.name.asl)
  of REK_VARIABLE:
    @[c_decl_var(expression.variable.module_ref.generate_type,
        result_arg.name.asl, c_ident(expression.variable.name.asl))]

proc generate_statement*(statement: AnalyzedStatement): seq[CStmt] =
  statement.expression.generate_expression(statement.arg)

proc generate_case(case_block: AnalyzedCase,
    operand: AnalyzedArgumentDefinition, result_arg: string,
    first: bool = false): (CExpr, seq[CStmt]) =
  var body: seq[CStmt]
  var condition: CExpr

  case case_block.pattern.kind:
  of RCPK_LITERAL:
    let literal = case_block.pattern.literal
    case literal.kind:
    of LK_FLOAT: discard # UNREACHABLE
    of LK_INTEGER:
      condition = c_binary("==", c_ident(operand.name.asl),
          c_lit(literal.asl))
    of LK_STRING:
      condition = c_binary("==",
          c_call("String_compare", @[c_ident(operand.name.asl),
              c_lit(literal.asl)]),
          c_lit("0"))
  of RCPK_UNION:
    let union_pattern = case_block.pattern.union_pattern
    let id_args = operand.module_ref.generate_impl_id_inline
    let id_call = c_call(
        fmt"{operand.module_ref.name}_get_id",
        id_args & @[c_ident(operand.name.asl)])
    condition = c_binary("==", id_call, c_lit($union_pattern.id))

    let prefix = fmt"{operand.module_ref.name}_{union_pattern.name.asl}"
    for index in 0..<union_pattern.args.len:
      let field = union_pattern.args[index][0]
      let key = union_pattern.args[index][1]
      let original_field = union_pattern.branch.fields[index]

      case original_field.module_ref.kind:
      of AMRK_GENERIC:
        case field.module_ref.kind:
        of AMRK_GENERIC:
          let (ftype, _) = field.generate_param
          body.add(c_decl_var(ftype, field.name.asl,
              c_call(fmt"{prefix}_get_{key.asl}",
              id_args & @[c_ident(operand.name.asl)])))
        else:
          let arg_name = fmt"__asl_arg_{key.location.hash.to_hex}"
          body.add(c_decl_var(original_field.module_ref.generate_type,
              arg_name,
              c_call(fmt"{prefix}_get_{key.asl}",
              id_args & @[c_ident(operand.name.asl)])))
          let (ftype, _) = field.generate_param
          body.add(c_decl_var(ftype, field.name.asl,
              c_call(fmt"{field.module_ref.generate_type.emit}_read",
              @[c_ident(arg_name), c_lit("0")])))
      else:
        let (ftype, _) = field.generate_param
        body.add(c_decl_var(ftype, field.name.asl,
            c_call(fmt"{prefix}_get_{key.asl}",
            id_args & @[c_ident(operand.name.asl)])))

  for statement in case_block.statements:
    body.add(statement.generate_statement)
  let last_statement = case_block.statements[^1].arg.name.asl
  body.add(c_assign(result_arg, c_ident(last_statement)))
  return (condition, body)

proc generate_else(else_block: AnalyzedElse,
    result_arg: string): seq[CStmt] =
  var stmts: seq[CStmt]
  for statement in else_block.statements:
    stmts.add(statement.generate_statement)
  let last_arg = else_block.statements[^1].arg.name.asl
  stmts.add(c_assign(result_arg, c_ident(last_arg)))
  return stmts

proc generate_match(match: AnalyzedMatch,
    result_arg: AnalyzedArgumentDefinition): seq[CStmt] =
  var stmts: seq[CStmt]
  # Declare the result variable uninitialized
  let (result_type, result_name) = result_arg.generate_param
  stmts.add(c_decl_var(result_type, result_name))

  var branches: seq[(CExpr, seq[CStmt])]
  for index, case_block in match.case_blocks:
    let (cond, body) = generate_case(case_block, match.operand,
        result_name, index == 0)
    branches.add((cond, body))

  var else_body: seq[CStmt]
  case match.kind:
  of RMK_CASE_ONLY: discard
  of RMK_COMPLETE:
    else_body = match.else_block.generate_else(result_name)

  stmts.add(c_if(branches, else_body))
  return stmts
