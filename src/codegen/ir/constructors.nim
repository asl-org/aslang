import tables

import types
export types

# CType constructors
proc c_void*(): CType = CType(kind: CTK_VOID)
proc c_named*(name: string): CType = CType(kind: CTK_NAMED, name: name)
proc c_pointer*(): CType = CType(kind: CTK_POINTER)
proc c_const_pointer*(): CType = CType(kind: CTK_CONST_POINTER)

# CExpr constructors
proc c_lit*(value: string): CExpr =
  CExpr(kind: CEK_LITERAL, literal_value: value)

proc c_ident*(name: string): CExpr =
  CExpr(kind: CEK_IDENT, ident_name: name)

proc c_call*(name: string, args: seq[CExpr] = @[]): CExpr =
  CExpr(kind: CEK_CALL, call_name: name, call_args: args)

proc c_binary*(op: string, lhs: CExpr, rhs: CExpr): CExpr =
  CExpr(kind: CEK_BINARY, op: op, lhs: lhs, rhs: rhs)

proc c_cast*(typ: CType, expr: CExpr): CExpr =
  CExpr(kind: CEK_CAST, cast_type: typ, cast_expr: expr)

# CStmt constructors
proc c_decl_var*(typ: CType, name: string, init: CExpr = nil): CStmt =
  CStmt(kind: CSK_DECL, decl_type: typ, decl_name: name, decl_init: init)

proc c_assign*(name: string, expr: CExpr): CStmt =
  CStmt(kind: CSK_ASSIGN, assign_name: name, assign_expr: expr)

proc c_return*(expr: CExpr): CStmt =
  CStmt(kind: CSK_RETURN, return_expr: expr)

proc c_expr_stmt*(expr: CExpr): CStmt =
  CStmt(kind: CSK_EXPR, expr: expr)

proc c_if*(branches: seq[(CExpr, seq[CStmt])],
    else_body: seq[CStmt] = @[]): CStmt =
  CStmt(kind: CSK_IF, branches: branches, else_body: else_body)

proc c_switch*(expr: CExpr, cases: seq[(CExpr, seq[CStmt])],
    default: seq[CStmt] = @[]): CStmt =
  CStmt(kind: CSK_SWITCH, switch_expr: expr, cases: cases,
      switch_default: default)

proc c_block*(stmts: seq[CStmt]): CStmt =
  CStmt(kind: CSK_BLOCK, block_stmts: stmts)

proc c_comment*(text: string): CStmt =
  CStmt(kind: CSK_COMMENT, comment: text)

proc c_raw*(text: string): CStmt =
  CStmt(kind: CSK_RAW, raw: text)

# CDecl constructors
proc c_typedef*(old_type: string, new_type: string): CDecl =
  CDecl(kind: CDK_TYPEDEF, typedef_old: old_type, typedef_new: new_type)

proc c_func_decl*(ret: CType, name: string,
    params: seq[(CType, string)]): CDecl =
  CDecl(kind: CDK_FUNC_DECL, func_return: ret, func_name: name,
      func_params: params, func_body: @[])

proc c_func_def*(ret: CType, name: string, params: seq[(CType, string)],
    body: seq[CStmt]): CDecl =
  CDecl(kind: CDK_FUNC_DEF, func_return: ret, func_name: name,
      func_params: params, func_body: body)

proc c_extern*(ret: CType, name: string,
    params: seq[(CType, string)]): CDecl =
  CDecl(kind: CDK_EXTERN, func_return: ret, func_name: name,
      func_params: params, func_body: @[])

proc c_include*(header: string): CDecl =
  CDecl(kind: CDK_INCLUDE, header: header)

# CProgram constructor
proc c_program*(includes: seq[CDecl], typedefs: seq[CDecl],
    forward_decls: seq[CDecl], definitions: seq[CDecl], main: CDecl,
    metadata: Table[string, FunctionMetadata] = init_table[string,
        FunctionMetadata]()): CProgram =
  CProgram(includes: includes, typedefs: typedefs,
      forward_decls: forward_decls, definitions: definitions, main: main,
      metadata: metadata)
