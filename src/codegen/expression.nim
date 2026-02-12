import strformat, hashes, strutils

import analyzer
import fncall
import initializer
import struct_get
import module_ref
import arg_def

proc c(match: AnalyzedMatch, result_arg: AnalyzedArgumentDefinition): seq[string]

proc c(expression: AnalyzedExpression, result_arg: AnalyzedArgumentDefinition): seq[string] =
  case expression.kind:
  of REK_MATCH: expression.match.c(result_arg)
  of REK_FNCALL: expression.fncall.c(result_arg.name.asl)
  of REK_INIT: expression.init.c(result_arg.name.asl)
  of REK_STRUCT_GET: @[expression.struct_get.c(result_arg.name.asl)]
  of REK_VARIABLE: @[fmt"{expression.variable.module_ref.c} {result_arg.name.asl} = {expression.variable.name.asl};"]

proc c*(statement: AnalyzedStatement): seq[string] =
  statement.expression.c(statement.arg)

proc c(case_block: AnalyzedCase, operand: AnalyzedArgumentDefinition,
    result_arg: string, first: bool = false): seq[string] =
  var lines: seq[string]
  let conditional = if first: "if" else: "else if"
  case case_block.pattern.kind:
  of RCPK_LITERAL:
    let literal = case_block.pattern.literal
    case literal.kind:
    of LK_FLOAT: discard # UNREACHABLE
    of LK_INTEGER:
      lines.add(fmt"{conditional}({operand.name.asl} == {literal.asl})")
      lines.add("{")
    of LK_STRING:
      lines.add(fmt"{conditional}(String_compare({operand.name.asl}, {literal.asl}) == 0)")
      lines.add("{")
  of RCPK_STRUCT:
    let struct = case_block.pattern.struct
    let id_call = fmt"{operand.module_ref.name}_get_id({operand.name.asl})"
    lines.add(fmt"{conditional}({id_call} == {struct.id})")
    lines.add("{")

    case struct.kind:
    of RSPK_DEFAULT:
      let prefix = operand.module_ref.name
      for index in 0..<struct.args.len:
        let field = struct.args[index][0]
        let key = struct.args[index][1]
        let original_field = struct.struct.fields[index]

        case original_field.module_ref.kind:
        of AMRK_GENERIC:
          case field.module_ref.kind:
          of AMRK_GENERIC:
            lines.add(fmt"{field.c} = {prefix}_get_{key.asl}({operand.name.asl});")
          else:
            let arg_name = fmt"__asl_arg_{key.location.hash.to_hex}"
            lines.add(fmt"{original_field.module_ref.c} {arg_name} = {prefix}_get_{key.asl}({operand.name.asl});")
            lines.add(fmt"{field.c} = {field.module_ref.c}_read({arg_name}, 0);")
        else:
          lines.add(fmt"{field.c} = {prefix}_get_{key.asl}({operand.name.asl});")
    of RSPK_NAMED:
      let prefix = fmt"{operand.module_ref.name}_{struct.name.asl}"
      for index in 0..<struct.args.len:
        let field = struct.args[index][0]
        let key = struct.args[index][1]
        let original_field = struct.branch.fields[index]

        case original_field.module_ref.kind:
        of AMRK_GENERIC:
          case field.module_ref.kind:
          of AMRK_GENERIC:
            lines.add(fmt"{field.c} = {prefix}_get_{key.asl}({operand.name.asl});")
          else:
            let arg_name = fmt"__asl_arg_{key.location.hash.to_hex}"
            lines.add(fmt"{original_field.module_ref.c} {arg_name} = {prefix}_get_{key.asl}({operand.name.asl});")
            lines.add(fmt"{field.c} = {field.module_ref.c}_read({arg_name}, 0);")
        else:
          lines.add(fmt"{field.c} = {prefix}_get_{key.asl}({operand.name.asl});")

  for statement in case_block.statements:
    lines.add(statement.c)
  let last_statement = case_block.statements[^1].arg.name.asl
  lines.add(fmt"{result_arg} = {last_statement};")
  lines.add("}")

  return lines

proc c(else_block: AnalyzedElse, result_arg: string): seq[string] =
  var lines: seq[string]
  lines.add("else {")
  for statement in else_block.statements:
    lines.add(statement.c)
  let last_arg = else_block.statements[^1].arg.name.asl
  lines.add(fmt"{result_arg} = {last_arg};")
  lines.add("}")
  return lines

proc c(match: AnalyzedMatch, result_arg: AnalyzedArgumentDefinition): seq[string] =
  var lines: seq[string]
  lines.add(fmt"{result_arg.c};")
  for index, case_block in match.case_blocks:
    lines.add(case_block.c(match.operand, result_arg.name.asl, index == 0))
  case match.kind:
  of RMK_CASE_ONLY: discard
  of RMK_COMPLETE: lines.add(match.else_block.c(result_arg.name.asl))
  return lines
