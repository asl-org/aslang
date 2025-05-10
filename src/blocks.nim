import results, strformat, strutils

import rules

const TAB_SIZE = 2

proc validate_prefix(spaces, level: int): Result[void, string] =
  let prefix = level * TAB_SIZE
  if spaces != prefix:
    return err(fmt"statement must be prefixed with {prefix} spaces but found {spaces}")
  return ok()

type Function = ref object of RootObj
  def: FunctionDefinition
  statements: seq[Statement]
  spaces: int

proc `$`*(fn: Function): string =
  let prefix = " ".repeat(fn.spaces)
  let child_prefix = (" ".repeat(TAB_SIZE)) & prefix
  var content: seq[string] = @[prefix & $(fn.def)]
  for statement in fn.statements:
    content.add((child_prefix & $(statement)))
  return content.join("\n")

proc new_function(def: FunctionDefinition,
    spaces: int): Function =
  Function(def: def, spaces: spaces)

# TODO: add duplicate block validation
proc add_statement(fn: Function, statement: Statement): void =
  fn.statements.add(statement)

# TODO: perform final validation
proc close(fn: Function): Result[void, string] =
  if fn.statements.len == 0:
    return err(fmt"function block must have at least one args block")
  ok()

type App = ref object of RootObj
  def: AppDefinition
  fns: seq[Function]
  spaces: int

proc `$`*(app: App): string =
  let prefix = " ".repeat(app.spaces)
  var content: seq[string] = @[prefix & $(app.def)]
  for fn in app.fns:
    content.add($(fn))
  content.join("\n")

proc new_app(def: AppDefinition, spaces: int): App =
  App(def: def, spaces: spaces)

# TODO: add duplicate block validation
proc add_fn(app: App, fn: Function): void =
  app.fns.add(fn)

# TODO: perform final validation
proc close(app: App): Result[void, string] =
  if app.fns.len == 0:
    return err(fmt"app block must have at least one function block")
  ok()

type AslFile = ref object of RootObj
  apps: seq[App]

proc `$`*(file: AslFile): string =
  $(file.apps[0])

# TODO: add duplicate block validation
proc add_app(file: AslFile, app: App): void =
  file.apps.add(app)

# TODO: perform final validation
proc close(file: AslFile): Result[void, string] =
  if file.apps.len != 1:
    return err(fmt"root block must have an app block")
  ok()

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
    of BK_APP: parent_block.file.add_app(child_block.app)
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

proc to_blocks(program: Program): Result[Block, string] =
  let lines = program.only_statements.lines
  var stack = Stack[Block](data: @[new_block()])
  for line in lines:
    while stack.len > 1:
      var child_block = ? stack.peek()
      if child_block.spaces < line.spaces: break
      child_block = ? stack.pop()
      var parent_block = ? stack.peek()
      child_block = ? child_block.close()
      parent_block = ? parent_block.add_block(child_block)
    let maybe_statement = line.safe_non_macro_statement()
    if maybe_statement.is_ok:
      var fn = ? stack.peek()
      if line.spaces != 4:
        return err(fmt"Expected 4 spaces before the statement but found {line.spaces}")
      fn.fn.add_statement(maybe_statement.get)
      continue

    let fn_def = line.safe_fn_def()
    if fn_def.is_ok:
      let fn = ? new_block(fn_def.get, line.spaces)
      stack.push(fn)
      continue

    let maybe_app_def = line.safe_app_def()
    if maybe_app_def.is_ok:
      let app = ? new_block(maybe_app_def.get, line.spaces)
      stack.push(app)
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
