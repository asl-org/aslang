import tables

import ../metadata
export metadata

type
  CTypeKind* = enum
    CTK_VOID, CTK_NAMED, CTK_POINTER, CTK_CONST_POINTER
  CType* = ref object of RootObj
    case kind*: CTypeKind
    of CTK_VOID: discard
    of CTK_NAMED: name*: string
    of CTK_POINTER: discard
    of CTK_CONST_POINTER: discard

type
  CExprKind* = enum
    CEK_LITERAL, CEK_IDENT, CEK_CALL, CEK_BINARY, CEK_CAST
  CExpr* = ref object of RootObj
    case kind*: CExprKind
    of CEK_LITERAL: literal_value*: string
    of CEK_IDENT: ident_name*: string
    of CEK_CALL:
      call_name*: string
      call_args*: seq[CExpr]
    of CEK_BINARY:
      op*: string
      lhs*, rhs*: CExpr
    of CEK_CAST:
      cast_type*: CType
      cast_expr*: CExpr

type
  CStmtKind* = enum
    CSK_DECL, CSK_ASSIGN, CSK_RETURN, CSK_EXPR, CSK_IF, CSK_SWITCH,
    CSK_BLOCK, CSK_COMMENT, CSK_RAW
  CStmt* = ref object of RootObj
    case kind*: CStmtKind
    of CSK_DECL:
      decl_type*: CType
      decl_name*: string
      decl_init*: CExpr
    of CSK_ASSIGN:
      assign_name*: string
      assign_expr*: CExpr
    of CSK_RETURN:
      return_expr*: CExpr
    of CSK_EXPR:
      expr*: CExpr
    of CSK_IF:
      branches*: seq[(CExpr, seq[CStmt])]
      else_body*: seq[CStmt]
    of CSK_SWITCH:
      switch_expr*: CExpr
      cases*: seq[(CExpr, seq[CStmt])]
      switch_default*: seq[CStmt]
    of CSK_BLOCK:
      block_stmts*: seq[CStmt]
    of CSK_COMMENT:
      comment*: string
    of CSK_RAW:
      raw*: string

type
  CDeclKind* = enum
    CDK_TYPEDEF, CDK_FUNC_DECL, CDK_FUNC_DEF, CDK_EXTERN, CDK_INCLUDE
  CDecl* = ref object of RootObj
    case kind*: CDeclKind
    of CDK_TYPEDEF:
      typedef_old*: string
      typedef_new*: string
    of CDK_FUNC_DECL, CDK_FUNC_DEF, CDK_EXTERN:
      func_return*: CType
      func_name*: string
      func_params*: seq[(CType, string)]
      func_body*: seq[CStmt]
    of CDK_INCLUDE:
      header*: string

type CProgram* = ref object of RootObj
  includes*: seq[CDecl]
  typedefs*: seq[CDecl]
  forward_decls*: seq[CDecl]
  definitions*: seq[CDecl]
  main*: CDecl
  metadata*: Table[string, FunctionMetadata]
