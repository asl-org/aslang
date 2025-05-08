import results, strformat, options

import rules

const TAB_SIZE = 2

type
  BlockKind* = enum
    BK_ROOT, BK_APP, BK_FUNCTION, BK_ARGS
  Block* = ref object of RootObj
    spaces: int
    case kind: BlockKind
    of BK_ROOT:
      app_block: Option[Block]
    of BK_APP:
      app_macro: AppMacro
      fn_blocks: seq[Block]
    of BK_FUNCTION:
      fn_macro: FunctionMacro
      arg_blocks: seq[Block]
    of BK_ARGS:
      args_macro: ArgumentDefintionList
      assignments: seq[Assignment]

proc validate_prefix(spaces, level: int): Result[void, string] =
  let prefix = level * TAB_SIZE
  if spaces != prefix:
    return err(fmt"statement must be prefixed with {prefix} spaces but found {spaces}")
  return ok()

proc new_block(app_macro: AppMacro, spaces: int): Result[Block, string] =
  ? validate_prefix(spaces, 0)
  ok(Block(kind: BK_APP, spaces: spaces, app_macro: app_macro))

proc new_block(fn_macro: FunctionMacro, spaces: int): Result[Block, string] =
  ? validate_prefix(spaces, 1)
  ok(Block(kind: BK_FUNCTION, spaces: spaces, fn_macro: fn_macro))

proc new_block(args_macro: ArgumentDefintionList, spaces: int): Result[Block, string] =
  ? validate_prefix(spaces, 2)
  ok(Block(kind: BK_ARGS, spaces: spaces, args_macro: args_macro))

proc new_root_block(): Block = Block(kind: BK_ROOT)

proc add_assignment(asl_block: Block, assignment: Assignment,
    spaces: int): Result[Block, string] =
  case asl_block.kind:
  of BK_ARGS:
    asl_block.assignments.add(assignment)
    return ok(asl_block)
  else:
    return err(fmt"{asl_block.kind} does not support statements")

proc add_block(parent_block, child_block: Block): Result[Block, string] =
  case parent_block.kind:
  of BK_ROOT:
    case child_block.kind:
    of BK_APP: parent_block.app_block = some(child_block)
    else: return err(fmt"root block only supports app block as a child")
  of BK_APP:
    case child_block.kind:
    of BK_FUNCTION: parent_block.fn_blocks.add(child_block)
    else: return err(fmt"app block only supports function block as a child")
  of BK_FUNCTION:
    case child_block.kind:
    of BK_ARGS: parent_block.arg_blocks.add(child_block)
    else: return err(fmt"function block only supports arg block as a child")
  of BK_ARGS:
    return err(fmt"args block does not supported any further nested blocks")
  return ok(parent_block)

proc close(child_block: Block): Result[Block, string] =
  case child_block.kind:
  of BK_ROOT:
    if child_block.app_block.is_some:
      return err(fmt"root block must have exactly one app block")
  of BK_APP:
    if child_block.fn_blocks.len == 0:
      return err(fmt"app block must have at least one function block")
  of BK_FUNCTION:
    if child_block.arg_blocks.len == 0:
      return err(fmt"function block must have at least one args block")
  of BK_ARGS:
    if child_block.assignments.len == 0:
      return err(fmt"args block must have at least one statement")
  return ok(child_block)

type Stack[T] = ref object of RootObj
  data: seq[T]

proc len(stack: Stack): int = stack.data.len
proc empty(stack: Stack): bool = stack.len == 0

# TODO: May error in case of stack overflow
proc push[T](stack: Stack, asl_block: T): void =
  stack.data.add(asl_block)

proc peek[T](stack: Stack[T]): Result[T, string] =
  if stack.empty(): return err(fmt"Block stack is empty")
  let value = stack.data[^1]
  ok(value)

proc pop[T](stack: Stack[T]): Result[T, string] =
  let value = ? stack.peek()
  stack.data.set_len(stack.data.len - 1)
  return ok(value)

proc to_blocks*(program: Program): Result[Block, string] =
  let lines = program.only_statements.lines
  var stack = Stack[Block](data: @[new_root_block()])
  for line in lines:
    while stack.len > 1:
      var child_block = ? stack.peek()
      if child_block.spaces < line.spaces: break
      child_block = ? stack.pop()
      var parent_block = ? stack.peek()
      child_block = ? child_block.close()
      parent_block = ? parent_block.add_block(child_block)

    let maybe_assignment = line.safe_assignment()
    if maybe_assignment.is_ok:
      var arg_block = ? stack.peek()
      arg_block = ? arg_block.add_assignment(maybe_assignment.get, line.spaces)
      continue

    let maybe_args_macro = line.safe_args_macro()
    if maybe_args_macro.is_ok:
      let arg_block = ? new_block(maybe_args_macro.get, line.spaces)
      stack.push(arg_block)
      continue

    let maybe_fn_macro = line.safe_fn_macro()
    if maybe_fn_macro.is_ok:
      let fn_block = ? new_block(maybe_fn_macro.get, line.spaces)
      stack.push(fn_block)
      continue

    let maybe_app_macro = line.safe_app_macro()
    if maybe_app_macro.is_ok:
      let app_block = ? new_block(maybe_app_macro.get, line.spaces)
      stack.push(app_block)
      continue

    return err(fmt"Line {line} is invalid for macro processing")

  while stack.len > 1:
    var child_block = ? stack.peek()
    child_block = ? stack.pop()
    var parent_block = ? stack.peek()
    child_block = ? child_block.close()
    parent_block = ? parent_block.add_block(child_block)

  let root_block = ? stack.pop()
  echo root_block.app_block.is_some
  ok(root_block)
