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
  ok(Block(kind: BK_CASE, case_block: new_case(case_def.pattern, spaces)))

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

proc expand_kwarg(kwarg: KeywordArg, fn: Function,
    temp_var_count: var int): Result[(KeywordArg, int), string] =
  case kwarg.value.kind:
  of KWAV_IDENTIFIER:
    # No expansion needed
    return ok((kwarg, temp_var_count))
  of KWAV_ATOM:
    # 1. Extract out the atom and create a new assignment statement
    let temp_var = new_identifier(fmt"__asl_expanded_var_{temp_var_count}")
    temp_var_count += 1

    let module_ref = new_module_ref(@[new_identifier("Struct")],
        Location())
    let literal = new_literal(kwarg.value.atom)
    let init = new_init(module_ref, literal, Location())
    let expanded_expression = new_expression(init)
    let expanded_assignment = new_assignment(temp_var,
        expanded_expression, Location())
    let expanded_statement = new_statement(expanded_assignment)
    ? fn.add_statement(expanded_statement)

    # 2. Replace the struct with the expanded identifier `temp_var`
    let expanded_kwarg_value = new_keyword_arg_value(temp_var)
    let expanded_kwarg = new_keyword_arg(kwarg.name, expanded_kwarg_value)
    return ok((expanded_kwarg, temp_var_count))

proc expand_struct(struct: Struct, fn: Function,
    temp_var_count: var int): Result[(seq[KeywordArg], int), string] =
  var expanded_kwargs: seq[KeywordArg]
  for kwarg in struct.kwargs:
    let expanded = ? kwarg.expand_kwarg(fn, temp_var_count)
    let expanded_kwarg = expanded[0]
    temp_var_count = expanded[1]
    expanded_kwargs.add(expanded_kwarg)

  return ok((expanded_kwargs, temp_var_count))

proc expand_literal(literal: Literal, fn: Function,
    temp_var_count: var int): Result[(Literal, int), string] =
  case literal.kind:
  of LTK_NATIVE_NUMERIC:
    return ok((literal, temp_var_count))
  of LTK_STRUCT:
    let (expanded_kwargs, temp_var_count) = ? literal.struct.expand_struct(fn, temp_var_count)
    let expanded_struct = new_struct(expanded_kwargs,
        literal.struct.location)
    let expanded_literal = new_literal(expanded_struct)
    return ok((expanded_literal, temp_var_count))

proc expand_init(init: Initializer, fn: Function,
    temp_var_count: var int): Result[(Initializer, int), string] =
  let literal = init.literal
  let (expanded_literal, temp_var_count) = ? literal.expand_literal(fn, temp_var_count)
  let expanded_init = new_init(init.module_ref, expanded_literal, init.location)
  return ok((expanded_init, temp_var_count))

proc expand_expression(expression: Expression, fn: Function,
    temp_var_count: var int): Result[(Expression, int), string] =
  case expression.kind:
  of EK_INIT:
    let init = expression.init
    let (expanded_init, temp_var_count) = ? init.expand_init(fn, temp_var_count)
    let expanded_expression = new_expression(expanded_init)
    return ok((expanded_expression, temp_var_count))
  of EK_FNCALL:
    return ok((expression, temp_var_count))
  of EK_IDENTIFIER:
    return ok((expression, temp_var_count))

proc expand_assignment(assignment: Assignment, fn: Function,
    temp_var_count: var int): Result[(Assignment, int), string] =
  let (expanded_expression, temp_var_count) = ?
    assignment.expression.expand_expression(fn, temp_var_count)
  let expanded_assignment = new_assignment(assignment.dest, expanded_expression,
      assignment.location)
  return ok((expanded_assignment, temp_var_count))

proc expand_statement(statement: Statement, fn: Function,
    temp_var_count: var int): Result[(Statement, int), string] =
  case statement.kind:
  of SK_ASSIGNMENT:
    let (expanded_assignment, temp_var_count) = ?
      statement.assign.expand_assignment(fn, temp_var_count)
    let expanded_statement = new_statement(expanded_assignment)
    return ok((expanded_statement, temp_var_count))
  of SK_EXPR:
    var (expanded_expression, temp_var_count) = ?
      statement.expression.expand_expression(fn, temp_var_count)
    let temp_var = new_identifier(fmt"__asl_expanded_var_{temp_var_count}")
    temp_var_count += 1
    let assignment = new_assignment(temp_var, expanded_expression,
        statement.location)
    let expanded_statement = new_statement(assignment)
    return ok((expanded_statement, temp_var_count))

proc to_blocks(program: Program): Result[Block, string] =
  var scope = ? new_block()
  var stack = ? @[scope].new_stack()
  var temp_var_count = 0
  for line in program.only_statements.lines:
    while stack.len > 1:
      var child_block = ? stack.peek()
      if child_block.spaces < line.spaces: break
      child_block = ? stack.pop()
      var parent_block = ? stack.peek()
      child_block = ? child_block.close()
      parent_block = ? parent_block.add_block(child_block)

    case line.kind:
    of LK_STATEMENT:
      var asl_block = ? stack.peek()
      case asl_block.kind:
      of BK_FUNCTION:
        if line.spaces != 4:
          return err(fmt"Expected 4 spaces before the statement but found {line.spaces}")
        let expanded = ? line.statement.expand_statement(asl_block.fn, temp_var_count)
        let expanded_statement = expanded[0]
        temp_var_count = expanded[1]
        ? asl_block.fn.add_statement(expanded_statement)
      of BK_CASE:
        if line.spaces != 8:
          return err(fmt"Expected 8 spaces before the statement but found {line.spaces}")
        ? asl_block.case_block.add_statement(line.statement)
      of BK_ELSE:
        if line.spaces != 8:
          return err(fmt"Expected 8 spaces before the statement but found {line.spaces}")
        ? asl_block.else_block.add_statement(line.statement)
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
    of LK_MACRO_CALL:
      case line.macro_call.kind:
      of MCK_STRUCT_MACRO:
        ? stack.push( ? new_struct_block(line.spaces))
      of MCK_UNION_MACRO:
        ? stack.push( ? new_union_block(line.spaces))
      of MCK_MATCH_DEF:
        ? stack.push( ? new_block(line.macro_call.match_def, line.spaces))
      of MCK_CASE_DEF:
        ? stack.push( ? new_block(line.macro_call.case_def, line.spaces))
      of MCK_ELSE_DEF:
        ? stack.push( ? new_else_block(line.spaces))
      of MCK_FN:
        ? stack.push( ? new_block(line.macro_call.fn_def, line.spaces))
      of MCK_MODULE:
        ? stack.push( ? new_block(line.macro_call.module_def, line.spaces))
    of LK_STRUCT_FIELD_DEF:
      var asl_block = ? stack.peek()
      case asl_block.kind:
      of BK_STRUCT:
        if line.spaces != 4:
          return err(fmt"Expected 4 spaces before the struct field definition but found {line.spaces}")
        ? asl_block.struct_block.add_field_def(line.struct_field_def)
      else:
        return err(fmt"Line {line} can not be added to any block")
    of LK_UNION_DEF, LK_COMMENT, LK_EMPTY:
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
      discard

  while stack.len > 1:
    var child_block = ? stack.pop()
    child_block = ? child_block.close()
    var parent_block = ? stack.peek()
    parent_block = ? parent_block.add_block(child_block)

  scope = ? stack.pop()
  discard ? scope.close()
  # echo scope
  ok(scope)

proc collect_defintions*(program: Program): Result[string, string] =
  let asl_block = ? program.to_blocks()
  let code = ? asl_block.scope.generate_app
  ok(code)
