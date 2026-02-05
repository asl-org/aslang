import results, strformat, tables, hashes, strutils, sets, options

import resolver
import module_ref
import arg_def
import struct
import module_def
import file_def
import func_ref
import fncall
import initializer
import struct_get
import struct_pattern
import case_pattern

type
  AnalyzedExpressionKind = enum
    REK_MATCH, REK_FNCALL, REK_INIT, REK_STRUCT_GET, REK_VARIABLE
  AnalyzedExpression = ref object of RootObj
    case kind: AnalyzedExpressionKind
    of REK_MATCH: match: AnalyzedMatch
    of REK_FNCALL: fncall: AnalyzedFunctionCall
    of REK_INIT: init: AnalyzedInitializer
    of REK_STRUCT_GET: struct_get: AnalyzedStructGet
    of REK_VARIABLE: variable: AnalyzedArgumentDefinition
  AnalyzedStatement* = ref object of RootObj
    arg: AnalyzedArgumentDefinition
    expression: AnalyzedExpression
  AnalyzedCase = ref object of RootObj
    pattern: AnalyzedCasePattern
    statements: seq[AnalyzedStatement]
    location: Location
  AnalyzedElse = ref object of RootObj
    location: Location
    statements: seq[AnalyzedStatement]
  AnalyzedMatchKind = enum
    RMK_CASE_ONLY, RMK_COMPLETE
  AnalyzedMatch = ref object of RootObj
    location: Location
    operand: AnalyzedArgumentDefinition
    case_blocks: seq[AnalyzedCase]
    case kind: AnalyzedMatchKind
    of RMK_CASE_ONLY: discard
    of RMK_COMPLETE: else_block: AnalyzedElse

proc new_analyzed_expression(match: AnalyzedMatch): AnalyzedExpression =
  AnalyzedExpression(kind: REK_MATCH, match: match)

proc new_analyzed_expression(fncall: AnalyzedFunctionCall): AnalyzedExpression =
  AnalyzedExpression(kind: REK_FNCALL, fncall: fncall)

proc new_analyzed_expression(init: AnalyzedInitializer): AnalyzedExpression =
  AnalyzedExpression(kind: REK_INIT, init: init)

proc new_analyzed_expression(struct_get: AnalyzedStructGet): AnalyzedExpression =
  AnalyzedExpression(kind: REK_STRUCT_GET, struct_get: struct_get)

proc new_analyzed_expression(variable: AnalyzedArgumentDefinition): AnalyzedExpression =
  AnalyzedExpression(kind: REK_VARIABLE, variable: variable)

proc returns(match: AnalyzedMatch): AnalyzedModuleRef

proc returns(expression: AnalyzedExpression): AnalyzedModuleRef =
  case expression.kind:
  of REK_MATCH: expression.match.returns
  of REK_FNCALL: expression.fncall.returns
  of REK_INIT: expression.init.returns
  of REK_STRUCT_GET: expression.struct_get.returns
  of REK_VARIABLE: expression.variable.module_ref

proc generic_impls(match: AnalyzedMatch): Table[ResolvedModule, seq[HashSet[
    AnalyzedImpl]]]

proc generic_impls(expression: AnalyzedExpression): Table[ResolvedModule,
    seq[HashSet[AnalyzedImpl]]] =
  case expression.kind:
  of REK_MATCH: expression.match.generic_impls
  of REK_FNCALL: expression.fncall.generic_impls
  of REK_INIT: expression.init.generic_impls
  of REK_STRUCT_GET: expression.struct_get.generic_impls
  of REK_VARIABLE: expression.variable.generic_impls

proc asl(match: AnalyzedMatch, indent: string): seq[string]

proc asl(expression: AnalyzedExpression, indent: string): seq[string] =
  case expression.kind:
  of REK_MATCH: expression.match.asl(indent)
  of REK_FNCALL: @[expression.fncall.asl]
  of REK_INIT: @[expression.init.asl]
  of REK_STRUCT_GET: @[expression.struct_get.asl]
  of REK_VARIABLE: @[expression.variable.asl]

proc c(match: AnalyzedMatch, result_arg: AnalyzedArgumentDefinition): seq[string]

proc c(expression: AnalyzedExpression, result_arg: AnalyzedArgumentDefinition): seq[string] =
  case expression.kind:
  of REK_MATCH: expression.match.c(result_arg)
  of REK_FNCALL: expression.fncall.c(result_arg.name.asl)
  of REK_INIT: expression.init.c(result_arg.name.asl)
  of REK_STRUCT_GET: @[expression.struct_get.c(result_arg.name.asl)]
  of REK_VARIABLE: @[fmt"{expression.variable.module_ref.c} {result_arg.name.asl} = {expression.variable.name.asl};"]

proc analyze*(file_def: AnalyzedFileDefinition,
    module_def: AnalyzedModuleDefinition, scope: FunctionScope,
    match: ResolvedMatch): Result[AnalyzedMatch, string]

proc analyze(file_def: AnalyzedFileDefinition,
    module_def: AnalyzedModuleDefinition, scope: FunctionScope,
    expression: ResolvedExpression): Result[AnalyzedExpression, string] =
  case expression.kind:
  of TEK_FNCALL:
    let fncall = ? expression.fncall
    let analyzed_function_call = ? analyze(file_def, scope, fncall, some(module_def))
    ok(new_analyzed_expression(analyzed_function_call))
  of TEK_INIT:
    let init = ? expression.init
    let analyzed_init = ? analyze(file_def, module_def, scope, init)
    ok(new_analyzed_expression(analyzed_init))
  of TEK_STRUCT_GET:
    let struct_get = ? expression.struct_get
    let analyzed_struct_get = ? analyze(file_def, scope, struct_get, some(module_def))
    ok(new_analyzed_expression(analyzed_struct_get))
  of TEK_VARIABLE:
    let variable = ? expression.variable
    let analyzed_variable = ? analyze(scope, variable)
    ok(new_analyzed_expression(analyzed_variable))
  of TEK_MATCH:
    let match = ? expression.match
    let analyzed_match = ? analyze(file_def, module_def, scope, match)
    ok(new_analyzed_expression(analyzed_match))

proc analyze*(file_def: AnalyzedFileDefinition, scope: FunctionScope,
    match: ResolvedMatch): Result[AnalyzedMatch, string]

proc analyze(file_def: AnalyzedFileDefinition, scope: FunctionScope,
    expression: ResolvedExpression): Result[AnalyzedExpression, string] =
  case expression.kind:
  of TEK_FNCALL:
    let fncall = ? expression.fncall
    let analyzed_function_call = ? analyze(file_def, scope, fncall)
    ok(new_analyzed_expression(analyzed_function_call))
  of TEK_INIT:
    let init = ? expression.init
    let analyzed_init = ? analyze(file_def, scope, init)
    ok(new_analyzed_expression(analyzed_init))
  of TEK_STRUCT_GET:
    let struct_get = ? expression.struct_get
    let analyzed_struct_get = ? analyze(file_def, scope, struct_get)
    ok(new_analyzed_expression(analyzed_struct_get))
  of TEK_VARIABLE:
    let variable = ? expression.variable
    let analyzed_variable = ? analyze(scope, variable)
    ok(new_analyzed_expression(analyzed_variable))
  of TEK_MATCH:
    let match = ? expression.match
    let analyzed_match = ? analyze(file_def, scope, match)
    ok(new_analyzed_expression(analyzed_match))

# Statement
proc new_analyzed_statement(arg: AnalyzedArgumentDefinition,
    expression: AnalyzedExpression): AnalyzedStatement =
  AnalyzedStatement(arg: arg, expression: expression)

proc returns(statement: AnalyzedStatement): AnalyzedModuleRef =
  statement.expression.returns

proc arg*(statement: AnalyzedStatement): AnalyzedArgumentDefinition =
  statement.arg

proc generic_impls*(statement: AnalyzedStatement): Table[ResolvedModule, seq[
    HashSet[AnalyzedImpl]]] = statement.expression.generic_impls

proc asl*(statement: AnalyzedStatement, indent: string): seq[string] =
  var lines = statement.expression.asl(indent)
  lines[0] = fmt"{statement.arg.asl} = {lines[0]}"
  lines

proc c*(statement: AnalyzedStatement): seq[string] =
  statement.expression.c(statement.arg)

proc analyze*(file_def: AnalyzedFileDefinition,
    module_def: AnalyzedModuleDefinition, scope: FunctionScope,
    statement: ResolvedStatement): Result[AnalyzedStatement, string] =
  let analyzed_expression = ? analyze(file_def, module_def, scope,
      statement.expression)
  let analyzed_arg = new_analyzed_argument_definition(
      analyzed_expression.returns, statement.arg)
  ok(new_analyzed_statement(analyzed_arg, analyzed_expression))

proc analyze*(file_def: AnalyzedFileDefinition, scope: FunctionScope,
    statement: ResolvedStatement): Result[AnalyzedStatement, string] =
  let analyzed_expression = ? analyze(file_def, scope, statement.expression)
  let analyzed_arg = new_analyzed_argument_definition(
      analyzed_expression.returns, statement.arg)
  ok(new_analyzed_statement(analyzed_arg, analyzed_expression))

# Case
proc new_analyzed_case(pattern: AnalyzedCasePattern, statements: seq[
    AnalyzedStatement], location: Location): AnalyzedCase =
  AnalyzedCase(pattern: pattern, statements: statements, location: location)

proc returns(case_block: AnalyzedCase): AnalyzedModuleRef =
  case_block.statements[^1].returns

proc generic_impls(case_block: AnalyzedCase): Table[ResolvedModule, seq[
    HashSet[AnalyzedImpl]]] =
  var impl_set: Table[ResolvedModule, seq[HashSet[AnalyzedImpl]]]
  impl_set = impl_set.merge(case_block.pattern.generic_impls)
  for statement in case_block.statements:
    impl_set = impl_set.merge(statement.generic_impls)
  return impl_set

proc asl(case_block: AnalyzedCase, indent: string): seq[string] =
  var lines = @[fmt"case {case_block.pattern.asl}:"]
  for statement in case_block.statements:
    for line in statement.asl(indent):
      lines.add(indent & line)
  lines

proc c(case_block: AnalyzedCase, operand: AnalyzedArgumentDefinition,
    result_arg: string, first: bool = false): seq[string] =
  var lines: seq[string]
  let conditional = if first: "if" else: "else if"
  case case_block.pattern.kind:
  of RCPK_LITERAL:
    let literal = case_block.pattern.literal
    case literal.kind:
    of LK_FLOAT: discard # UNREACHABLE
    of LK_INTEGER:
      lines.add(fmt"{conditional}({operand.name.asl} == {literal.asl})")
      lines.add("{")
    of LK_STRING:
      lines.add(fmt"{conditional}(String_compare({operand.name.asl}, {literal.asl}) == 0)")
      lines.add("{")
  of RCPK_STRUCT:
    let struct = case_block.pattern.struct
    let id_call = fmt"{operand.module_ref.name}_get_id({operand.name.asl})"
    lines.add(fmt"{conditional}({id_call} == {struct.id})")
    lines.add("{")

    case struct.kind:
    of RSPK_DEFAULT:
      let prefix = operand.module_ref.name
      for index in 0..<struct.args.len:
        let field = struct.args[index][0]
        let key = struct.args[index][1]
        let original_field = struct.struct.fields[index]

        case original_field.module_ref.kind:
        of AMRK_GENERIC:
          case field.module_ref.kind:
          of AMRK_GENERIC:
            lines.add(fmt"{field.c} = {prefix}_get_{key.asl}({operand.name.asl});")
          else:
            let arg_name = fmt"__asl_arg_{key.location.hash.to_hex}"
            lines.add(fmt"{original_field.module_ref.c} {arg_name} = {prefix}_get_{key.asl}({operand.name.asl});")
            lines.add(fmt"{field.c} = {field.module_ref.c}_read({arg_name}, 0);")
        else:
          lines.add(fmt"{field.c} = {prefix}_get_{key.asl}({operand.name.asl});")
    of RSPK_NAMED:
      let prefix = fmt"{operand.module_ref.name}_{struct.name.asl}"
      for index in 0..<struct.args.len:
        let field = struct.args[index][0]
        let key = struct.args[index][1]
        let original_field = struct.branch.fields[index]

        case original_field.module_ref.kind:
        of AMRK_GENERIC:
          case field.module_ref.kind:
          of AMRK_GENERIC:
            lines.add(fmt"{field.c} = {prefix}_get_{key.asl}({operand.name.asl});")
          else:
            let arg_name = fmt"__asl_arg_{key.location.hash.to_hex}"
            lines.add(fmt"{original_field.module_ref.c} {arg_name} = {prefix}_get_{key.asl}({operand.name.asl});")
            lines.add(fmt"{field.c} = {field.module_ref.c}_read({arg_name}, 0);")
        else:
          lines.add(fmt"{field.c} = {prefix}_get_{key.asl}({operand.name.asl});")

  for statement in case_block.statements:
    lines.add(statement.c)
  let last_statement = case_block.statements[^1].arg.name.asl
  lines.add(fmt"{result_arg} = {last_statement};")
  lines.add("}")

  return lines

proc analyze(file_def: AnalyzedFileDefinition,
    module_def: AnalyzedModuleDefinition, scope: FunctionScope,
    operand: AnalyzedModuleRef, case_block: ResolvedCase): Result[AnalyzedCase, string] =
  var case_scope = scope.clone()
  let analyzed_case_pattern = ? analyze(file_def, scope, operand,
      case_block.pattern)

  case analyzed_case_pattern.kind:
  of RCPK_LITERAL: discard
  of RCPK_STRUCT:
    let analyzed_struct_pattern = analyzed_case_pattern.struct
    for (field, name) in analyzed_struct_pattern.args:
      case_scope = ? case_scope.set(field)

  var analyzed_statements: seq[AnalyzedStatement]
  for statement in case_block.statements:
    let analyzed_statement = ? analyze(file_def, module_def, case_scope, statement)
    analyzed_statements.add(analyzed_statement)
    case_scope = ? case_scope.set(analyzed_statement.arg)
  ok(new_analyzed_case(analyzed_case_pattern, analyzed_statements,
      case_block.location))

proc analyze(file_def: AnalyzedFileDefinition, scope: FunctionScope,
    operand: AnalyzedModuleRef, case_block: ResolvedCase): Result[AnalyzedCase, string] =
  var case_scope = scope.clone()
  let analyzed_case_pattern = ? analyze(file_def, scope, operand,
      case_block.pattern)
  case analyzed_case_pattern.kind:
  of RCPK_LITERAL: discard
  of RCPK_STRUCT:
    let analyzed_struct_pattern = analyzed_case_pattern.struct
    for (field, name) in analyzed_struct_pattern.args:
      case_scope = ? case_scope.set(field)

  var analyzed_statements: seq[AnalyzedStatement]
  for statement in case_block.statements:
    let analyzed_statement = ? analyze(file_def, case_scope, statement)
    analyzed_statements.add(analyzed_statement)
    case_scope = ? case_scope.set(analyzed_statement.arg)
  ok(new_analyzed_case(analyzed_case_pattern, analyzed_statements,
      case_block.location))

# Else
proc new_analyzed_else(statements: seq[AnalyzedStatement],
    location: Location): AnalyzedElse =
  AnalyzedElse(statements: statements, location: location)

proc returns(else_block: AnalyzedElse): AnalyzedModuleRef =
  else_block.statements[^1].returns

proc generic_impls(else_block: AnalyzedElse): Table[ResolvedModule, seq[
    HashSet[AnalyzedImpl]]] =
  var impl_set: Table[ResolvedModule, seq[HashSet[AnalyzedImpl]]]
  for statement in else_block.statements: impl_set = impl_set.merge(
      statement.generic_impls)
  return impl_set

proc asl(else_block: AnalyzedElse, indent: string): seq[string] =
  var lines = @["else:"]
  for statement in else_block.statements:
    for line in statement.asl(indent):
      lines.add(indent & line)
  return lines

proc c(else_block: AnalyzedElse, result_arg: string): seq[string] =
  var lines: seq[string]
  lines.add("else {")
  for statement in else_block.statements:
    lines.add(statement.c)
  let last_arg = else_block.statements[^1].arg.name.asl
  lines.add(fmt"{result_arg} = {last_arg};")
  lines.add("}")
  return lines

proc analyze(file_def: AnalyzedFileDefinition,
    module_def: AnalyzedModuleDefinition, scope: FunctionScope,
    else_block: ResolvedElse): Result[AnalyzedElse, string] =
  var else_scope = scope.clone()
  var analyzed_statements: seq[AnalyzedStatement]
  for statement in else_block.statements:
    let analyzed_statement = ? analyze(file_def, module_def, else_scope, statement)
    analyzed_statements.add(analyzed_statement)
    else_scope = ? else_scope.set(analyzed_statement.arg)
  ok(new_analyzed_else(analyzed_statements, else_block.location))

proc analyze(file_def: AnalyzedFileDefinition, scope: FunctionScope,
    else_block: ResolvedElse): Result[AnalyzedElse, string] =
  var else_scope = scope.clone()
  var analyzed_statements: seq[AnalyzedStatement]
  for statement in else_block.statements:
    let analyzed_statement = ? analyze(file_def, else_scope, statement)
    analyzed_statements.add(analyzed_statement)
    else_scope = ? else_scope.set(analyzed_statement.arg)
  ok(new_analyzed_else(analyzed_statements, else_block.location))

# Match
proc new_analyzed_match(operand: AnalyzedArgumentDefinition, case_blocks: seq[
    AnalyzedCase], else_block: AnalyzedElse,
    location: Location): AnalyzedMatch =
  AnalyzedMatch(kind: RMK_COMPLETE, operand: operand, case_blocks: case_blocks,
      else_block: else_block, location: location)

proc new_analyzed_match(operand: AnalyzedArgumentDefinition, case_blocks: seq[
    AnalyzedCase], location: Location): AnalyzedMatch =
  AnalyzedMatch(kind: RMK_CASE_ONLY, operand: operand, case_blocks: case_blocks,
      location: location)

proc returns(match: AnalyzedMatch): AnalyzedModuleRef =
  match.case_blocks[0].returns

proc generic_impls(match: AnalyzedMatch): Table[ResolvedModule, seq[HashSet[
    AnalyzedImpl]]] =
  var impl_set: Table[ResolvedModule, seq[HashSet[AnalyzedImpl]]]
  for case_block in match.case_blocks: impl_set = impl_set.merge(
      case_block.generic_impls)

  case match.kind:
  of RMK_CASE_ONLY: discard
  of RMK_COMPLETE: impl_set = impl_set.merge(match.else_block.generic_impls)
  return impl_set

proc asl(match: AnalyzedMatch, indent: string): seq[string] =
  var lines = @[fmt"match {match.operand.name.asl}:"]
  for case_block in match.case_blocks:
    for line in case_block.asl(indent):
      lines.add(indent & line)

  case match.kind:
  of RMK_CASE_ONLY: discard
  of RMK_COMPLETE:
    for line in match.else_block.asl(indent):
      lines.add(indent & line)

  lines

proc c(match: AnalyzedMatch, result_arg: AnalyzedArgumentDefinition): seq[string] =
  var lines: seq[string]
  lines.add(fmt"{result_arg.c};")
  for index, case_block in match.case_blocks:
    lines.add(case_block.c(match.operand, result_arg.name.asl, index == 0))
  case match.kind:
  of RMK_CASE_ONLY: discard
  of RMK_COMPLETE: lines.add(match.else_block.c(result_arg.name.asl))
  return lines

proc analyze*(file_def: AnalyzedFileDefinition,
    module_def: AnalyzedModuleDefinition, scope: FunctionScope,
    match: ResolvedMatch): Result[AnalyzedMatch, string] =
  let analyzed_operand_module_ref = ? scope.get(match.operand)
  case analyzed_operand_module_ref.kind:
    of AMRK_GENERIC:
      return err(fmt"{match.location} match expression does not support generic operands")
    of AMRK_MODULE:
      let module = analyzed_operand_module_ref.module
      let analyzed_operand_module = ? file_def.find_module_def(module)
      case analyzed_operand_module.data.kind:
      of ADK_NONE:
        case analyzed_operand_module.name.asl:
        of "S8", "S16", "S32", "S64", "U8", "U16", "U32", "U64": discard
        else: return err(fmt"{match.location} module `{analyzed_operand_module.name.asl}` is does not have a data block")
      of ADK_STRUCT:
        return err(fmt"{match.location} module `{analyzed_operand_module.name.asl}` is a struct and not supported in match blocks")
      else: discard

  let analyzed_operand = new_analyzed_argument_definition(
      analyzed_operand_module_ref, match.operand)
  case match.kind:
  of TMK_CASE_ONLY:
    var analyzed_case_blocks: seq[AnalyzedCase]
    for case_block in match.case_blocks:
      let analyzed_case_block = ? analyze(file_def, module_def, scope,
          analyzed_operand_module_ref, case_block)
      analyzed_case_blocks.add(analyzed_case_block)

    var unique_patterns: Table[AnalyzedCasePattern, AnalyzedCase]
    for case_block in analyzed_case_blocks:
      # NOTE: Ensure all the case block returns type is same.
      if case_block.returns != analyzed_case_blocks[0].returns:
        return err(fmt"{case_block.location} returns `{case_block.returns.asl}` but expected `{analyzed_case_blocks[0].returns.asl}`")

      # NOTE: Detect duplicate patterns
      if case_block.pattern in unique_patterns:
        let prev_case_block = unique_patterns[case_block.pattern]
        return err(fmt"{case_block.location} duplicate case block found at `{prev_case_block.location}`")
      else:
        unique_patterns[case_block.pattern] = case_block

    # NOTE: Make sure all the cases are covered
    case analyzed_operand_module_ref.kind:
    of AMRK_GENERIC:
      return err(fmt"{match.location} match expression does not support generic operands")
    of AMRK_MODULE:
      let module = analyzed_operand_module_ref.module
      let analyzed_operand_module = ? file_def.find_module_def(module)
      case analyzed_operand_module.data.kind:
      of ADK_UNION:
        if unique_patterns.len < analyzed_operand_module.data.union.branches.len:
          return err(fmt"{match.location} match expression does not cover all cases, an else block is required")
      else: discard

    ok(new_analyzed_match(analyzed_operand, analyzed_case_blocks,
        match.location))
  of TMK_COMPLETE:
    var analyzed_case_blocks: seq[AnalyzedCase]
    for case_block in match.case_blocks:
      let analyzed_case_block = ? analyze(file_def, module_def, scope,
          analyzed_operand_module_ref, case_block)
      analyzed_case_blocks.add(analyzed_case_block)

    let else_block = ? match.else_block
    let analyzed_else_block = ? analyze(file_def, module_def, scope, else_block)

    var unique_patterns: Table[AnalyzedCasePattern, AnalyzedCase]
    for case_block in analyzed_case_blocks:
      if case_block.returns != analyzed_else_block.returns:
        return err(fmt"{case_block.location} returns `{case_block.returns.asl}` but expected `{analyzed_else_block.returns.asl}`")

      # NOTE: Detect duplicate patterns
      if case_block.pattern in unique_patterns:
        let prev_case_block = unique_patterns[case_block.pattern]
        return err(fmt"{case_block.location} duplicate case block found at `{prev_case_block.location}`")
      else:
        unique_patterns[case_block.pattern] = case_block

    # NOTE: Make sure all the cases are covered
    case analyzed_operand_module_ref.kind:
    of AMRK_GENERIC:
      return err(fmt"{match.location} match expression does not support generic operands")
    of AMRK_MODULE:
      let module = analyzed_operand_module_ref.module
      let analyzed_operand_module = ? file_def.find_module_def(module)
      case analyzed_operand_module.data.kind:
      of ADK_UNION:
        if unique_patterns.len == analyzed_operand_module.data.union.branches.len:
          return err(fmt"{match.location} match expression already covers all cases, else block is not required")
      else: discard

    ok(new_analyzed_match(analyzed_operand, analyzed_case_blocks,
        analyzed_else_block, match.location))

proc analyze*(file_def: AnalyzedFileDefinition, scope: FunctionScope,
    match: ResolvedMatch): Result[AnalyzedMatch, string] =
  let analyzed_operand_module_ref = ? scope.get(match.operand)
  case analyzed_operand_module_ref.kind:
    of AMRK_GENERIC:
      return err(fmt"{match.location} match expression does not support generic operands")
    of AMRK_MODULE:
      let module = analyzed_operand_module_ref.module
      let analyzed_operand_module = ? file_def.find_module_def(module)
      case analyzed_operand_module.data.kind:
      of ADK_NONE:
        case analyzed_operand_module.name.asl:
        of "S8", "S16", "S32", "S64", "U8", "U16", "U32", "U64": discard
        else: return err(fmt"{match.location} module `{analyzed_operand_module.name.asl}` is does not have a data block")
      of ADK_STRUCT:
        return err(fmt"{match.location} module `{analyzed_operand_module.name.asl}` is a struct and not supported in match blocks")
      else: discard

  let analyzed_operand = new_analyzed_argument_definition(
      analyzed_operand_module_ref, match.operand)
  case match.kind:
  of TMK_CASE_ONLY:
    var analyzed_case_blocks: seq[AnalyzedCase]
    for case_block in match.case_blocks:
      let analyzed_case_block = ? analyze(file_def, scope,
          analyzed_operand_module_ref, case_block)
      analyzed_case_blocks.add(analyzed_case_block)

    var unique_patterns: Table[AnalyzedCasePattern, AnalyzedCase]
    for case_block in analyzed_case_blocks:
      if case_block.returns != analyzed_case_blocks[0].returns:
        return err(fmt"{case_block.location} returns `{case_block.returns.asl}` but expected `{analyzed_case_blocks[0].returns.asl}`")

      # NOTE: Detect duplicate patterns
      if case_block.pattern in unique_patterns:
        let prev_case_block = unique_patterns[case_block.pattern]
        return err(fmt"{case_block.location} duplicate case block found at `{prev_case_block.location}`")
      else:
        unique_patterns[case_block.pattern] = case_block

    # NOTE: Make sure all the cases are covered
    case analyzed_operand_module_ref.kind:
    of AMRK_GENERIC:
      return err(fmt"{match.location} match expression does not support generic operands")
    of AMRK_MODULE:
      let module = analyzed_operand_module_ref.module
      let analyzed_operand_module = ? file_def.find_module_def(module)
      case analyzed_operand_module.data.kind:
      of ADK_UNION:
        if unique_patterns.len < analyzed_operand_module.data.union.branches.len:
          return err(fmt"{match.location} match expression does not cover all cases, an else block is required")
      else: discard

    ok(new_analyzed_match(analyzed_operand, analyzed_case_blocks,
        match.location))
  of TMK_COMPLETE:
    var analyzed_case_blocks: seq[AnalyzedCase]
    for case_block in match.case_blocks:
      let analyzed_case_block = ? analyze(file_def, scope,
          analyzed_operand_module_ref, case_block)
      analyzed_case_blocks.add(analyzed_case_block)

    let else_block = ? match.else_block
    let analyzed_else_block = ? analyze(file_def, scope, else_block)

    var unique_patterns: Table[AnalyzedCasePattern, AnalyzedCase]
    for case_block in analyzed_case_blocks:
      if case_block.returns != analyzed_else_block.returns:
        return err(fmt"{case_block.location} returns `{case_block.returns.asl}` but expected `{analyzed_else_block.returns.asl}`")

      # NOTE: Detect duplicate patterns
      if case_block.pattern in unique_patterns:
        let prev_case_block = unique_patterns[case_block.pattern]
        return err(fmt"{case_block.location} duplicate case block found at `{prev_case_block.location}`")
      else:
        unique_patterns[case_block.pattern] = case_block

    # NOTE: Make sure all the cases are covered
    case analyzed_operand_module_ref.kind:
    of AMRK_GENERIC:
      return err(fmt"{match.location} match expression does not support generic operands")
    of AMRK_MODULE:
      let module = analyzed_operand_module_ref.module
      let analyzed_operand_module = ? file_def.find_module_def(module)
      case analyzed_operand_module.data.kind:
      of ADK_UNION:
        if unique_patterns.len == analyzed_operand_module.data.union.branches.len:
          return err(fmt"{match.location} match expression already covers all cases, else block is not required")
      else: discard

    ok(new_analyzed_match(analyzed_operand, analyzed_case_blocks,
        analyzed_else_block, match.location))
