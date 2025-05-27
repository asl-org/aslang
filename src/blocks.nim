import results, strformat

import rules

import blocks/common; export common
import blocks/matcher; export matcher
import blocks/function; export function
import blocks/module; export module
import blocks/scope; export scope

type
  BlockKind* = enum
    BK_FILE, BK_MODULE, BK_FUNCTION, BK_MATCH, BK_CASE, BK_ELSE, BK_STRUCT, BK_UNION
  Block* = ref object of RootObj
    case kind: BlockKind
    of BK_FILE: scope: Scope
    of BK_MODULE: module: Module
    of BK_FUNCTION: fn: Function
    of BK_MATCH: match_block: Match
    of BK_CASE: case_block: Case
    of BK_ELSE: else_block: Else
    of BK_STRUCT: struct_block: StructDef
    of BK_UNION: union_block: Union

proc `$`*(asl_block: Block): string =
  case asl_block.kind:
  of BK_FILE: $(asl_block.scope)
  of BK_MODULE: $(asl_block.module)
  of BK_FUNCTION: $(asl_block.fn)
  of BK_MATCH: $(asl_block.match_block)
  of BK_CASE: $(asl_block.case_block)
  of BK_ELSE: $(asl_block.else_block)
  of BK_STRUCT: $(asl_block.struct_block)
  of BK_UNION: $(asl_block.union_block)

proc new_block(def: ModuleDefinition, spaces: int): Result[Block, string] =
  ? validate_prefix(spaces, 0)
  ok(Block(kind: BK_MODULE, module: new_user_module(def, spaces)))

proc new_block(def: FunctionDefinition, spaces: int): Result[Block, string] =
  ? validate_prefix(spaces, 1)
  ok(Block(kind: BK_FUNCTION, fn: new_user_function(def, spaces)))

proc new_block(matcher: MatchDefinition, spaces: int): Result[Block, string] =
  ok(Block(kind: BK_MATCH, match_block: new_matcher(matcher.name, spaces)))

proc new_block(case_def: CaseDefinition, spaces: int): Result[Block, string] =
  ok(Block(kind: BK_CASE, case_block: new_case(case_def.value, spaces)))

proc new_else_block(spaces: int): Result[Block, string] =
  ok(Block(kind: BK_ELSE, else_block: new_else(spaces)))

proc new_struct_block(spaces: int): Result[Block, string] =
  ok(Block(kind: BK_STRUCT, struct_block: new_struct_def(spaces)))

proc new_union_block(spaces: int): Result[Block, string] =
  ok(Block(kind: BK_UNION, union_block: new_union(spaces)))

proc new_block(): Result[Block, string] =
  let scope = ? new_scope()
  ok(Block(kind: BK_FILE, scope: scope))

proc spaces*(asl_block: Block): int =
  case asl_block.kind:
  of BK_FILE: asl_block.scope.spaces
  of BK_MODULE: asl_block.module.spaces
  of BK_FUNCTION: asl_block.fn.spaces
  of BK_MATCH: asl_block.match_block.spaces
  of BK_CASE: asl_block.case_block.spaces
  of BK_ELSE: asl_block.else_block.spaces
  of BK_STRUCT: asl_block.struct_block.spaces
  of BK_UNION: asl_block.union_block.spaces

proc add_block(parent_block, child_block: Block): Result[Block, string] =
  case parent_block.kind:
  of BK_FILE:
    case child_block.kind:
    of BK_MODULE: ? parent_block.scope.add_user_module(child_block.module)
    else: return err(fmt"root block only supports module block as a child")
  of BK_MODULE:
    case child_block.kind:
    of BK_FUNCTION: ? parent_block.module.add_fn(child_block.fn)
    of BK_STRUCT: ? parent_block.module.add_fields(child_block.struct_block)
    of BK_UNION: ? parent_block.module.add_union(child_block.union_block)
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
  of BK_STRUCT:
    return err(fmt"struct block does not support any further nested blocks")
  of BK_UNION:
    return err(fmt"union block does not support any further nested blocks")
  return ok(parent_block)

proc close(child_block: Block): Result[Block, string] =
  case child_block.kind:
  of BK_FILE: ? child_block.scope.close()
  of BK_MODULE: ? child_block.module.close()
  of BK_FUNCTION: ? child_block.fn.close()
  of BK_MATCH: ? child_block.match_block.close()
  of BK_CASE: ? child_block.case_block.close()
  of BK_ELSE: ? child_block.else_block.close()
  of BK_STRUCT: ? child_block.struct_block.close()
  of BK_UNION: ? child_block.union_block.close()
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

    # statement
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
      # TODO: hacky stuff, using Statement for union definition because expr_init and
      # union_def syntax collides so if we encounter union_def with `union` as parent block
      # we convert expr_init to union_def. Need to be cleaned by introducing better syntax
      # current syntax: age = U32 0
      # new syntax: U32 age = 0
      of BK_UNION:
        if line.spaces != 4:
          return err(fmt"Expected 8 spaces before the union def but found {line.spaces}")
        let union_def = ? line.hacky_union_def()
        ? asl_block.union_block.add_union_def(union_def)
      else:
        return err(fmt"Line {line} can not be added to any block")

      continue

    # struct field def
    let maybe_struct_field_def = line.safe_struct_field_def()
    if maybe_struct_field_def.is_ok:
      var asl_block = ? stack.peek()
      # echo line
      # echo asl_block.kind
      case asl_block.kind:
      of BK_STRUCT:
        if line.spaces != 4:
          return err(fmt"Expected 4 spaces before the struct field definition but found {line.spaces}")
        ? asl_block.struct_block.add_field_def(maybe_struct_field_def.get)
      else: return err(fmt"Line {line} can not be added to any block")

      continue

    # TODO: Revive this code after fixing the initialzer and union def syntax collision
    # let maybe_union_def = line.safe_union_def()
    # if maybe_union_def.is_ok:
    #   var asl_block = ? stack.peek()
    #   echo asl_block
    #   case asl_block.kind:
    #   of BK_UNION:
    #     if line.spaces != 4:
    #       return err(fmt"Expected 4 spaces before the union definition but found {line.spaces}")
    #     ? asl_block.union_block.add_union_def(maybe_union_def.get)
    #   else: return err(fmt"Line {line} can not be added to any block")

    #   continue

    # struct macro
    let maybe_struct_macro = line.safe_struct_macro()
    if maybe_struct_macro.is_ok:
      let fields = ? new_struct_block(line.spaces)
      ? stack.push(fields)
      continue

    # union macro
    let maybe_union_macro = line.safe_union_macro()
    if maybe_union_macro.is_ok:
      let fields = ? new_union_block(line.spaces)
      ? stack.push(fields)
      continue

    # else block
    let maybe_else_def = line.safe_else_def()
    if maybe_else_def.is_ok:
      let fn = ? new_else_block(line.spaces)
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
  discard ? scope.close()
  ok(scope)

proc collect_defintions*(program: Program): Result[string, string] =
  let asl_block = ? program.to_blocks()
  let code = ? asl_block.scope.generate_app
  ok(code)
