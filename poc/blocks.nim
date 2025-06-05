import results, strformat, strutils, sequtils

import parser
export parser

type Function* = ref object of RootObj
  definition*: FunctionDefinition
  statements*: seq[Statement]

proc location*(function: Function): Location =
  function.definition.location

proc name*(function: Function): string =
  $(function.definition.name)

proc return_type*(function: Function): string =
  $(function.definition.return_type)

proc arity*(function: Function): int =
  function.definition.arg_def_list.len

proc arg_def_list*(function: Function): seq[ArgumentDefinition] =
  function.definition.arg_def_list

proc `$`*(function: Function): string =
  let prefix = " ".repeat(function.definition.location.column - 1)
  let child_prefix = " ".repeat(function.definition.location.column + 1)
  var lines = @[prefix & $(function.definition)]
  for statement in function.statements:
    lines.add(child_prefix & $(statement))
  lines.join("\n")

proc is_main*(function: Function): bool =
  let name = $(function.definition.name)
  let return_type = $(function.definition.return_type)
  let arity = function.definition.arg_def_list.len
  let first_arg_type = $(function.definition.arg_def_list[0].arg_type)
  return name == "main" and return_type == "U8" and arity == 1 and
      first_arg_type == "U8"

proc new_function*(definition: FunctionDefinition): Function =
  Function(definition: definition)

proc add_statement*(function: Function, statement: Statement): void =
  function.statements.add(statement)

type File* = ref object of RootObj
  location*: Location
  functions*: seq[Function]

proc name*(file: File): string =
  file.location.filename

proc `$`*(file: File): string =
  file.functions.map_it($(it)).join("\n\n")

proc find_main_function*(file: File): Result[Function, string] =
  for function in file.functions:
    if function.is_main():
      return ok(function)
  err(fmt"{file.name} failed to find main function")

proc check_if_duplicate(file: File, fn: Function): Result[void, string] =
  for function in file.functions:
    if function.name != fn.name: continue
    if function.arity != fn.arity: continue

    var matched = true
    for (function_arg, fn_arg) in zip(function.arg_def_list, fn.arg_def_list):
      if $(function_arg.arg_type) != $(fn_arg.arg_type):
        matched = false
    if matched:
      return err(fmt"{fn.location} {fn.name} is already defined in {function.location}")
  ok()

proc add_function*(file: File, function: Function): Result[void, string] =
  ? file.check_if_duplicate(function)
  file.functions.add(function)
  ok()

type
  BlockKind* = enum
    BK_FILE, BK_FUNCTION, BK_STATEMENT
  Block* = ref object of RootObj
    case kind*: BlockKind
    of BK_FILE: file*: File
    of BK_FUNCTION: function*: Function
    of BK_STATEMENT: statement*: Statement

proc location*(asl_block: Block): Location =
  case asl_block.kind:
  of BK_FILE: asl_block.file.location
  of BK_FUNCTION: asl_block.function.location
  of BK_STATEMENT: asl_block.statement.location

proc indent*(asl_block: Block): int =
  (asl_block.location.column - 1) div 2

proc `$`*(asl_block: Block): string =
  case asl_block.kind:
  of BK_FILE: $(asl_block.file)
  of BK_FUNCTION: $(asl_block.function)
  of BK_STATEMENT: $(asl_block.statement)

# TODO: implement block closing logic
proc close*(asl_block: Block): Result[void, string] =
  case asl_block.kind:
  of BK_FILE:
    if asl_block.file.functions.len == 0:
      return err(fmt"File must contain at least one function")
  of BK_FUNCTION:
    if asl_block.function.statements.len == 0:
      return err(fmt"Function must contain at least one statement")
  of BK_STATEMENT:
    discard
  ok()

proc add_child*(parent: Block, child: Block): Result[void, string] =
  case parent.kind:
  of BK_FILE:
    case child.kind:
    of BK_FUNCTION:
      ? parent.file.add_function(child.function)
      ok()
    else:
      err(fmt"File can only contain functions")
  of BK_FUNCTION:
    case child.kind:
    of BK_STATEMENT:
      parent.function.add_statement(child.statement)
      ok()
    else:
      err(fmt"Function can only contain statements")
  of BK_STATEMENT:
    err(fmt"Statement do not support further nesting")

proc new_block*(filename: string): Block =
  Block(kind: BK_FILE, file: File(location: new_file_location(filename)))

proc new_block*(line: Line): Result[Block, string] =
  let prefix = line.location.column - 1
  case line.kind:
  of LK_FUNCTION_DEFINITION:
    if prefix != 0:
      return err(fmt"{line.location} indentation error expected 0 spaces but found {prefix}")
    return ok(Block(kind: BK_FUNCTION, function: new_function(line.func_def)))
  of LK_STATEMENT:
    if prefix != 2:
      return err(fmt"{line.location} indentation error expected 2 spaces but found {prefix}")
    return ok(Block(kind: BK_STATEMENT, statement: line.statement))

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
    # statement is the leaf block
    of BK_STATEMENT: ? parent_block.add_child(current_block)
    else: stack.add(current_block)

  while stack.len > 1:
    let parent_block = stack[^2]
    let child_block = stack[^1]
    ? child_block.close()
    ? parent_block.add_child(child_block)
    stack.set_len(stack.len - 1)

  return ok(stack[^1].file)
