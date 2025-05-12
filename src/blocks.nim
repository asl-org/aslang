import results, strformat

import rules

import blocks/common; export common
import blocks/function; export function
import blocks/app; export app
import blocks/asl_file; export asl_file

type
  BlockKind* = enum
    BK_FILE, BK_APP, BK_FUNCTION
  Block* = ref object of RootObj
    spaces: int
    case kind: BlockKind
    of BK_FILE: file: AslFile
    of BK_APP: app: App
    of BK_FUNCTION: fn: Function

proc `$`*(asl_block: Block): string =
  case asl_block.kind:
  of BK_FILE: $(asl_block.file)
  of BK_APP: $(asl_block.app)
  of BK_FUNCTION: $(asl_block.fn)

proc new_block(def: AppDefinition, spaces: int): Result[Block, string] =
  ? validate_prefix(spaces, 0)
  ok(Block(kind: BK_APP, app: new_app(def, spaces)))

proc new_block(def: FunctionDefinition, spaces: int): Result[Block, string] =
  ? validate_prefix(spaces, 1)
  ok(Block(kind: BK_FUNCTION, fn: new_function(def, spaces)))

proc new_block(): Block = Block(kind: BK_FILE, file: AslFile())

proc add_block(parent_block, child_block: Block): Result[Block, string] =
  case parent_block.kind:
  of BK_FILE:
    case child_block.kind:
    of BK_APP: ? parent_block.file.add_app(child_block.app)
    else: return err(fmt"root block only supports app block as a child")
  of BK_APP:
    case child_block.kind:
    of BK_FUNCTION: parent_block.app.add_fn(child_block.fn)
    else: return err(fmt"app block only supports function block as a child")
  of BK_FUNCTION:
    return err(fmt"function block does not supported any further nested blocks")
  return ok(parent_block)

proc close(child_block: Block): Result[Block, string] =
  case child_block.kind:
  of BK_FILE: ? child_block.file.close()
  of BK_APP: ? child_block.app.close()
  of BK_FUNCTION: ? child_block.fn.close()
  return ok(child_block)

proc to_blocks(program: Program): Result[Block, string] =
  let lines = program.only_statements.lines
  var stack = ? @[new_block()].new_stack()
  for line in lines:
    while stack.len > 1:
      var child_block = ? stack.peek()
      if child_block.spaces < line.spaces: break
      child_block = ? stack.pop()
      var parent_block = ? stack.peek()
      child_block = ? child_block.close()
      parent_block = ? parent_block.add_block(child_block)

    let maybe_statement = line.safe_statement()
    if maybe_statement.is_ok:
      var fn_block = ? stack.peek()
      if line.spaces != 4:
        return err(fmt"Expected 4 spaces before the statement but found {line.spaces}")
      fn_block.fn.add_statement(maybe_statement.get)
      continue

    let maybe_fn_def = line.safe_fn_def()
    if maybe_fn_def.is_ok:
      let fn = ? new_block(maybe_fn_def.get, line.spaces)
      ? stack.push(fn)
      continue

    let maybe_app_def = line.safe_app_def()
    if maybe_app_def.is_ok:
      let app = ? new_block(maybe_app_def.get, line.spaces)
      ? stack.push(app)
      continue

    return err(fmt"Line {line} is invalid for macro processing")

  while stack.len > 1:
    var child_block = ? stack.peek()
    child_block = ? stack.pop()
    var parent_block = ? stack.peek()
    child_block = ? child_block.close()
    parent_block = ? parent_block.add_block(child_block)

  let file = ? stack.pop()
  ok(file)

proc collect_defintions*(program: Program): Result[void, string] =
  let asl_block = ? program.to_blocks()
  echo asl_block
  ok()
