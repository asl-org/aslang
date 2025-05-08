import sequtils, strutils, strformat, results

import statement
import macro_call
import assignment

type Comment* = ref object of RootObj
  content: string

proc new_comment*(content: string): Comment =
  Comment(content: content)

proc `$`*(comment: Comment): string =
  fmt"# {comment.content}"

type
  LineKind* = enum
    LK_STATEMENT, LK_COMMENT, LK_EMPTY
  Line* = ref object of RootObj
    spaces: int
    case kind: LineKind
    of LK_STATEMENT: statement: Statement
    of LK_COMMENT: comment: Comment
    of LK_EMPTY: discard

proc kind*(line: Line): LineKind = line.kind
proc statement*(line: Line): Statement = line.statement
proc spaces*(line: Line): int = line.spaces

proc safe_statement*(line: Line): Result[Statement, string] =
  case line.kind:
  of LK_STATEMENT: ok(line.statement)
  else: err("Line {line} is not a statement")

proc safe_assignment*(line: Line): Result[Assignment, string] =
  let statement = ? line.safe_statement()
  statement.safe_assignment()

proc safe_app_macro*(line: Line): Result[AppMacro, string] =
  let statement = ? line.safe_statement()
  statement.safe_app_macro()

proc safe_fn_macro*(line: Line): Result[FunctionMacro, string] =
  let statement = ? line.safe_statement()
  statement.safe_fn_macro()

proc safe_args_macro*(line: Line): Result[ArgumentDefintionList, string] =
  let statement = ? line.safe_statement()
  statement.safe_args_macro()

proc new_line*(statement: Statement, spaces: int): Line =
  Line(kind: LK_STATEMENT, statement: statement, spaces: spaces)

proc new_line*(comment: Comment, spaces: int): Line =
  Line(kind: LK_COMMENT, comment: comment, spaces: spaces)

proc new_empty_line*(spaces: int): Line =
  Line(kind: LK_EMPTY, spaces: spaces)

proc `$`*(line: Line): string =
  let content =
    case line.kind:
    of LK_STATEMENT: $(line.statement)
    of LK_COMMENT: $(line.comment)
    of LK_EMPTY: ""

  (" ".repeat(line.spaces)) & content

type Program* = ref object of RootObj
  lines: seq[Line]

proc `$`*(program: Program): string =
  program.lines.map(proc(x: Line): string = $(x)).join("\n")

proc new_program*(lines: seq[Line]): Program =
  Program(lines: lines)

proc lines*(program: Program): seq[Line] = program.lines

proc only_statements*(program: Program): Program =
  program.lines = program.lines.filter(proc(l: Line): bool = l.kind == LK_STATEMENT)
  return program
