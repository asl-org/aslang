import results, strformat

import blocks/token
export token

import blocks/arg_def
export arg_def

import blocks/function_call
export function_call

import blocks/statement
export statement

import blocks/line
export line

import blocks/case_block
export case_block

import blocks/else_block
export else_block

import blocks/match
export match

import blocks/function
export function

import blocks/struct
export struct

import blocks/module
export module

import blocks/file
export file

# Needed since nim also has a builtin `File` type
type File = file.File
const INDENT_SIZE = 2 # spaces

type
  BlockKind* = enum
    BK_STATEMENT, BK_MATCH, BK_CASE, BK_ELSE
    BK_STRUCT_FIELD, BK_STRUCT, BK_FUNCTION
    BK_MODULE, BK_FILE

  Block* = ref object of RootObj
    indent: int
    case kind*: BlockKind
    of BK_FILE: file*: File
    of BK_FUNCTION: function*: Function
    of BK_STATEMENT: statement*: Statement
    of BK_MATCH: match_block*: Match
    of BK_CASE: case_block*: Case
    of BK_ELSE: else_block*: Else
    of BK_STRUCT: struct: Struct
    of BK_STRUCT_FIELD: struct_field_def: ArgumentDefinition
    of BK_MODULE: module: Module

proc location*(asl_block: Block): Location =
  case asl_block.kind:
  of BK_FILE: asl_block.file.location
  of BK_FUNCTION: asl_block.function.location
  of BK_STATEMENT: asl_block.statement.location
  of BK_MATCH: asl_block.match_block.location
  of BK_CASE: asl_block.case_block.location
  of BK_ELSE: asl_block.else_block.location
  of BK_STRUCT: asl_block.struct.location
  of BK_STRUCT_FIELD: asl_block.struct_field_def.location
  of BK_MODULE: asl_block.module.location

proc indent*(asl_block: Block): int =
  (asl_block.location.column - 1) div 2

proc `$`*(asl_block: Block): string =
  case asl_block.kind:
  of BK_FILE: $(asl_block.file)
  of BK_FUNCTION: $(asl_block.function)
  of BK_STATEMENT: $(asl_block.statement)
  of BK_MATCH: $(asl_block.match_block)
  of BK_CASE: $(asl_block.case_block)
  of BK_ELSE: $(asl_block.else_block)
  of BK_STRUCT: $(asl_block.struct)
  of BK_STRUCT_FIELD: $(asl_block.struct_field_def)
  of BK_MODULE: $(asl_block.module)

# TODO: implement block closing logic
proc close*(asl_block: Block): Result[void, string] =
  case asl_block.kind:
  of BK_FILE:
    if asl_block.file.functions.len == 0:
      return err(fmt"File must contain at least one function")
  of BK_FUNCTION:
    if asl_block.function.steps == 0:
      return err(fmt"{asl_block.location} `fn` must contain at least one statement/match block")
  of BK_STATEMENT:
    discard
  of BK_MATCH:
    let case_count = asl_block.match_block.case_blocks.len
    let else_count = asl_block.match_block.else_blocks.len
    if case_count + else_count < 2:
      return err(fmt"{asl_block.location} `match` block must contain at least 2 case or else blocks")
    if else_count > 1:
      return err(fmt"{asl_block.location} `match` block cannot contain 2 else blocks")
  of BK_CASE:
    if asl_block.case_block.statements.len == 0:
      return err(fmt"{asl_block.location} `case` must contain at least one statement")
  of BK_ELSE:
    if asl_block.else_block.statements.len == 0:
      return err(fmt"{asl_block.location} `else` must contain at least one statement")
  of BK_STRUCT:
    if asl_block.struct.fields.len == 0:
      return err(fmt"{asl_block.location} `struct` must contain at least one field")
  of BK_STRUCT_FIELD:
    discard
  of BK_MODULE:
    if asl_block.module.functions.len == 0:
      return err(fmt"{asl_block.location} `module` must contain at least one function")
  ok()

proc add_child*(parent: Block, child: Block): Result[void, string] =
  if parent.indent + 1 != child.indent:
    return err(fmt"Indentation error child block {child.kind} must be nested with {INDENT_SIZE} spaces inside parent block {parent.kind}")

  case parent.kind:
  of BK_FILE:
    case child.kind:
    of BK_MODULE:
      ? parent.file.add_module(child.module)
      ok()
    of BK_FUNCTION:
      ? parent.file.add_function(child.function)
      ok()
    of BK_STRUCT:
      ? parent.file.add_struct(child.struct)
      ok()
    else:
      err(fmt"{parent.file.name} File can only contain functions")
  of BK_FUNCTION:
    case child.kind:
    of BK_STATEMENT:
      parent.function.add_statement(child.statement)
      ok()
    of BK_MATCH:
      parent.function.add_match(child.match_block)
      ok()
    else:
      err(fmt"{parent.location} `fn` can only contain statements")
  of BK_STATEMENT:
    err(fmt"{parent.location} statement does not support further nesting")
  of BK_MATCH:
    case child.kind:
    of BK_CASE:
      parent.match_block.add_case(child.case_block)
      ok()
    of BK_ELSE:
      parent.match_block.add_else(child.else_block)
      ok()
    else:
      err(fmt"{parent.location} `match` do not support further nesting")
  of BK_CASE:
    case child.kind:
    of BK_STATEMENT:
      parent.case_block.add_statement(child.statement)
      ok()
    else:
      err(fmt"{parent.location} `case` can only contain statements")
  of BK_ELSE:
    case child.kind:
    of BK_STATEMENT:
      parent.else_block.add_statement(child.statement)
      ok()
    else:
      err(fmt"{parent.location} `else` can only contain statements")
  of BK_STRUCT:
    case child.kind:
    of BK_STRUCT_FIELD:
      parent.struct.add_field(child.struct_field_def)
      ok()
    else:
      err(fmt"{parent.location} `struct` can only contain field definitions")
  of BK_STRUCT_FIELD:
    err(fmt"{parent.location} struct field definition does not support further nesting.")
  of BK_MODULE:
    case child.kind:
    of BK_FUNCTION:
      # TODO: Duplicate function/module name error handling
      parent.module.add_function(child.function)
      ok()
    else:
      err(fmt"{parent.module.name} Module can only contain functions")

proc new_block*(filename: string): Block =
  # file is the invisible parent block therefore -1 indent
  Block(indent: -1, kind: BK_FILE, file: new_file(filename))

proc new_block*(line: Line): Result[Block, string] =
  let spaces = line.location.column - 1
  if (spaces mod INDENT_SIZE) != 0:
    return err(fmt"Indentation error expected prefix spaces as multiple of {INDENT_SIZE} but found {spaces}")
  let indent = spaces div INDENT_SIZE

  let asl_block =
    case line.kind:
    of LK_FUNCTION_DEFINITION:
      Block(kind: BK_FUNCTION, indent: indent, function: new_function(line.func_def))
    of LK_STATEMENT:
      Block(kind: BK_STATEMENT, indent: indent, statement: line.statement)
    of LK_MATCH_DEFINITION:
      Block(kind: BK_MATCH, indent: indent, match_block: new_match(
          line.match_def))
    of LK_CASE_DEFINITION:
      Block(kind: BK_CASE, indent: indent, case_block: new_case(line.case_def))
    of LK_ELSE_DEFINITION:
      Block(kind: BK_ELSE, indent: indent, else_block: new_else(line.else_def))
    of LK_STRUCT_DEFINITION:
      Block(kind: BK_STRUCT, indent: indent, struct: new_struct(
          line.struct_def))
    of LK_STRUCT_FIELD_DEFINITION:
      Block(kind: BK_STRUCT_FIELD, indent: indent,
          struct_field_def: line.struct_field_def)
    of LK_MODULE_DEFINITION:
      Block(kind: BK_MODULE, indent: indent, module: new_module(
          line.module_def))
  ok(asl_block)

proc blockify*(filename: string, lines: seq[Line]): Result[File, string] =
  var stack = @[new_block(filename)]
  for line in lines:
    let current_block = ? new_block(line)
    while stack.len > 1:
      let child_block = stack[^1]
      if child_block.indent < current_block.indent: break
      if child_block.indent + 1 < current_block.indent:
        return err(fmt"{current_block.location} indentation error")
      stack.set_len(stack.len - 1) # pop child block

      let parent_block = stack[^1]
      ? child_block.close()
      ? parent_block.add_child(child_block)

    let parent_block = stack[^1]
    case current_block.kind:
    # statement & struct field is the leaf block
    of BK_STATEMENT: ? parent_block.add_child(current_block)
    of BK_STRUCT_FIELD: ? parent_block.add_child(current_block)
    else: stack.add(current_block)

  while stack.len > 1:
    let parent_block = stack[^2]
    let child_block = stack[^1]
    ? child_block.close()
    ? parent_block.add_child(child_block)
    stack.set_len(stack.len - 1)

  return ok(stack[^1].file)
