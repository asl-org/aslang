import strformat, strutils, sequtils

import ir/types

proc emit*(t: CType): string =
  case t.kind:
  of CTK_VOID: "void"
  of CTK_NAMED: t.name
  of CTK_POINTER: "Pointer"
  of CTK_CONST_POINTER: "const char *"

proc emit*(e: CExpr): string =
  case e.kind:
  of CEK_LITERAL: e.literal_value
  of CEK_IDENT: e.ident_name
  of CEK_CALL:
    let args = e.call_args.map_it(it.emit).join(", ")
    fmt"{e.call_name}({args})"
  of CEK_BINARY:
    fmt"{e.lhs.emit} {e.op} {e.rhs.emit}"
  of CEK_CAST:
    fmt"({e.cast_type.emit}){e.cast_expr.emit}"

proc emit*(s: CStmt): string =
  case s.kind:
  of CSK_DECL:
    if s.decl_init == nil:
      fmt"{s.decl_type.emit} {s.decl_name};"
    else:
      fmt"{s.decl_type.emit} {s.decl_name} = {s.decl_init.emit};"
  of CSK_ASSIGN:
    fmt"{s.assign_name} = {s.assign_expr.emit};"
  of CSK_RETURN:
    fmt"return {s.return_expr.emit};"
  of CSK_EXPR:
    fmt"{s.expr.emit};"
  of CSK_IF:
    var lines: seq[string]
    for index, (cond, body) in s.branches:
      let keyword = if index == 0: "if" else: "else if"
      lines.add(fmt"{keyword}({cond.emit})")
      lines.add("{")
      for stmt in body:
        lines.add(stmt.emit)
      lines.add("}")
    if s.else_body.len > 0:
      lines.add("else {")
      for stmt in s.else_body:
        lines.add(stmt.emit)
      lines.add("}")
    lines.join("\n")
  of CSK_SWITCH:
    var lines: seq[string]
    lines.add(fmt"switch({s.switch_expr.emit})")
    lines.add("{")
    for (case_val, body) in s.cases:
      lines.add(fmt"case {case_val.emit}:")
      lines.add("{")
      for stmt in body:
        lines.add(stmt.emit)
      lines.add("break;")
      lines.add("}")
    if s.switch_default.len > 0:
      lines.add("default:")
      lines.add("{")
      for stmt in s.switch_default:
        lines.add(stmt.emit)
      lines.add("break;")
      lines.add("}")
    lines.add("}")
    lines.join("\n")
  of CSK_BLOCK:
    var lines: seq[string]
    lines.add("{")
    for stmt in s.block_stmts:
      lines.add(stmt.emit)
    lines.add("}")
    lines.join("\n")
  of CSK_COMMENT:
    fmt"// {s.comment}"
  of CSK_RAW:
    s.raw

proc emit*(d: CDecl): string =
  case d.kind:
  of CDK_TYPEDEF:
    fmt"typedef {d.typedef_old} {d.typedef_new};"
  of CDK_FUNC_DECL:
    let params = d.func_params.map_it(fmt"{it[0].emit} {it[1]}").join(", ")
    fmt"{d.func_return.emit} {d.func_name}({params});"
  of CDK_FUNC_DEF:
    let params = d.func_params.map_it(fmt"{it[0].emit} {it[1]}").join(", ")
    var lines: seq[string]
    lines.add(fmt"{d.func_return.emit} {d.func_name}({params})")
    lines.add("{")
    for stmt in d.func_body:
      lines.add(stmt.emit)
    lines.add("}")
    lines.join("\n")
  of CDK_EXTERN:
    let params = d.func_params.map_it(fmt"{it[0].emit} {it[1]}").join(", ")
    fmt"extern {d.func_return.emit} {d.func_name}({params});"
  of CDK_INCLUDE:
    fmt"#include <{d.header}>"

proc emit*(p: CProgram): string =
  var sections: seq[string]
  for inc in p.includes:
    sections.add(inc.emit)
  sections.add("\n")
  for td in p.typedefs:
    sections.add(td.emit)
  sections.add("\n")
  for decl in p.forward_decls:
    sections.add(decl.emit)
  for def in p.definitions:
    sections.add(def.emit)
  sections.add("\n")
  sections.add(p.main.emit)
  sections.join("\n")
