import results, strformat

import rules

import blocks/common; export common
import blocks/matcher; export matcher
import blocks/function; export function
import blocks/module; export module
import blocks/scope; export scope

type
  BlockKind* = enum
    BK_SCOPE, BK_MODULE, BK_FUNCTION, BK_MATCH, BK_CASE, BK_ELSE
  Block* = ref object of RootObj
    case kind: BlockKind
    of BK_SCOPE: scope: Scope
    of BK_MODULE: module: Module
    of BK_FUNCTION: fn: Function
    of BK_MATCH: match_block: Match
    of BK_CASE: case_block: Case
    of BK_ELSE: else_block: Else

proc `$`*(asl_block: Block): string =
  case asl_block.kind:
  of BK_SCOPE: $(asl_block.scope)
  of BK_MODULE: $(asl_block.module)
  of BK_FUNCTION: $(asl_block.fn)
  of BK_MATCH: $(asl_block.match_block)
  of BK_CASE: $(asl_block.case_block)
  of BK_ELSE: $(asl_block.else_block)

proc new_block(def: ModuleDefinition, spaces: int): Result[Block, string] =
  ? validate_prefix(spaces, 0)
  ok(Block(kind: BK_MODULE, module: new_user_module(def, spaces)))

proc new_block(def: FunctionDefinition, spaces: int): Result[Block, string] =
  ? validate_prefix(spaces, 1)
  ok(Block(kind: BK_FUNCTION, fn: new_user_function(def, spaces)))

proc new_block(matcher: MatchDefinition, spaces: int): Result[Block, string] =
  ok(Block(kind: BK_MATCH, match_block: new_matcher(matcher.name, spaces)))

proc new_block(case_def: CaseDefinition, spaces: int): Result[Block, string] =
  ok(Block(kind: BK_CASE, case_block: new_case($(case_def.value), spaces)))

proc new_block(spaces: int): Result[Block, string] =
  ok(Block(kind: BK_ELSE, else_block: new_else(spaces)))

proc new_block(): Result[Block, string] =
  let scope = ? new_scope()
  ok(Block(kind: BK_SCOPE, scope: scope))

proc spaces*(asl_block: Block): int =
  case asl_block.kind:
  of BK_SCOPE: asl_block.scope.spaces
  of BK_MODULE: asl_block.module.spaces
  of BK_FUNCTION: asl_block.fn.spaces
  of BK_MATCH: asl_block.match_block.spaces
  of BK_CASE: asl_block.case_block.spaces
  of BK_ELSE: asl_block.else_block.spaces

proc add_block(parent_block, child_block: Block): Result[Block, string] =
  case parent_block.kind:
  of BK_SCOPE:
    case child_block.kind:
    of BK_MODULE: ? parent_block.scope.add_user_module(child_block.module)
    else: return err(fmt"root block only supports module block as a child")
  of BK_MODULE:
    case child_block.kind:
    of BK_FUNCTION: ? parent_block.module.add_fn(child_block.fn)
    else: return err(fmt"module block only supports function block as a child")
  of BK_FUNCTION:
    case child_block.kind:
    of BK_MATCH:
      ? parent_block.fn.add_match_block(child_block.match_block)
    else:
      return err(fmt"function block does not support any further nested blocks")
  of BK_MATCH:
    case child_block.kind:
    of BK_CASE:
      ? parent_block.match_block.add_case(child_block.case_block)
    of BK_ELSE:
      ? parent_block.match_block.add_else(child_block.else_block)
    else:
      return err(fmt"match block does not support any further nested blocks")
  of BK_CASE:
    return err(fmt"case block does not support any further nested blocks")
  of BK_ELSE:
    return err(fmt"else block does not support any further nested blocks")
  return ok(parent_block)

proc close(child_block: Block): Result[Block, string] =
  case child_block.kind:
  of BK_SCOPE: ? child_block.scope.close()
  of BK_MODULE: ? child_block.module.close()
  of BK_FUNCTION: ? child_block.fn.close()
  of BK_MATCH: ? child_block.match_block.close()
  of BK_CASE: ? child_block.case_block.close()
  of BK_ELSE: ? child_block.else_block.close()
  return ok(child_block)

proc to_blocks(program: Program): Result[Block, string] =
  let lines = program.only_statements.lines
  var scope = ? new_block()
  var stack = ? @[scope].new_stack()
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
      var asl_block = ? stack.peek()
      case asl_block.kind:
      of BK_FUNCTION:
        if line.spaces != 4:
          return err(fmt"Expected 4 spaces before the statement but found {line.spaces}")
        ? asl_block.fn.add_statement(maybe_statement.get)
      of BK_CASE:
        if line.spaces != 8:
          return err(fmt"Expected 8 spaces before the statement but found {line.spaces}")
        ? asl_block.case_block.add_statement(maybe_statement.get)
      of BK_ELSE:
        if line.spaces != 8:
          return err(fmt"Expected 8 spaces before the statement but found {line.spaces}")
        ? asl_block.else_block.add_statement(maybe_statement.get)
      else:
        return err(fmt"Line {line} can not be added to any block")

      continue

    # else block
    let maybe_else_def = line.safe_else_def()
    if maybe_else_def.is_ok:
      let fn = ? new_block(line.spaces)
      ? stack.push(fn)
      continue

    # case block
    let maybe_case_def = line.safe_case_def()
    if maybe_case_def.is_ok:
      let fn = ? new_block(maybe_case_def.get, line.spaces)
      ? stack.push(fn)
      continue

    # match block
    let maybe_match_def = line.safe_match_def()
    if maybe_match_def.is_ok:
      let fn = ? new_block(maybe_match_def.get, line.spaces)
      ? stack.push(fn)
      continue

    # fn block
    let maybe_fn_def = line.safe_fn_def()
    if maybe_fn_def.is_ok:
      let fn = ? new_block(maybe_fn_def.get, line.spaces)
      ? stack.push(fn)
      continue

    # module/app/struct/union block
    let maybe_app_def = line.safe_module_def()
    if maybe_app_def.is_ok:
      let module = ? new_block(maybe_app_def.get, line.spaces)
      ? stack.push(module)
      continue

    return err(fmt"Line {line} is invalid for macro processing")

  while stack.len > 1:
    var child_block = ? stack.pop()
    child_block = ? child_block.close()
    var parent_block = ? stack.peek()
    parent_block = ? parent_block.add_block(child_block)

  scope = ? stack.pop()
  ok(scope)

proc collect_defintions*(program: Program): Result[string, string] =
  let asl_block = ? program.to_blocks()
  let code = ? asl_block.scope.generate_app
  ok(code)
