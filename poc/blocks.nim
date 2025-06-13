import results, strformat, strutils, sequtils, hashes, tables, options

import parser
export parser

type Else* = ref object of RootObj
  else_def*: ElseDefinition
  statements*: seq[Statement]
  scope*: Table[string, ArgumentDefinition]

proc location*(else_block: Else): Location =
  else_block.else_def.location

proc `$`*(else_block: Else): string =
  let prefix = " ".repeat(else_block.else_def.location.column - 1)
  let child_prefix = " ".repeat(else_block.else_def.location.column + 1)
  var lines = @[prefix & $(else_block.else_def)]
  for statement in else_block.statements:
    lines.add(child_prefix & $(statement))
  return lines.join("\n")

proc c*(else_block: Else, result_var: Token): string =
  var lines = @["default: {"]
  for statement in else_block.statements:
    let arg_type = else_block.scope[$(statement.destination)].arg_type
    lines.add(fmt"{arg_type} {statement.destination} = {statement.function_call};")

  let return_arg = else_block.statements[^1].destination
  lines.add(fmt"{result_var} = {return_arg};")
  lines.add("break;")
  lines.add("}")
  return lines.join("\n")

proc add_statement*(else_block: Else, statement: Statement): void =
  else_block.statements.add(statement)

proc new_else*(else_def: ElseDefinition): Else =
  Else(else_def: else_def)

type Case* = ref object of RootObj
  case_def: CaseDefinition
  statements*: seq[Statement]
  scope*: Table[string, ArgumentDefinition]

proc location*(case_block: Case): Location =
  case_block.case_def.location

proc value*(case_block: Case): Token =
  case_block.case_def.value

proc `$`*(case_block: Case): string =
  let prefix = " ".repeat(case_block.case_def.location.column - 1)
  let child_prefix = " ".repeat(case_block.case_def.location.column + 1)
  var lines = @[prefix & $(case_block.case_def)]
  for statement in case_block.statements:
    lines.add(child_prefix & $(statement))
  return lines.join("\n")

proc c*(case_block: Case, result_var: Token): string =
  var lines = @[fmt"case {case_block.value}: " & "{"]
  for statement in case_block.statements:
    let arg_type = case_block.scope[$(statement.destination)].arg_type
    lines.add(fmt"{arg_type} {statement.destination} = {statement.function_call};")

  let return_arg = case_block.statements[^1].destination
  lines.add(fmt"{result_var} = {return_arg};")
  lines.add("break;")
  lines.add("}")
  return lines.join("\n")

proc add_statement*(case_block: Case, statement: Statement): void =
  case_block.statements.add(statement)

proc new_case*(case_def: CaseDefinition): Case =
  Case(case_def: case_def)

type Match* = ref object of RootObj
  match_def*: MatchDefinition
  case_blocks*: seq[Case]
  else_blocks*: seq[Else]
  return_type*: Option[Token]

proc location*(match: Match): Location =
  match.match_def.location

proc destination*(match: Match): Token =
  match.match_def.destination

proc operand*(match: Match): Token =
  match.match_def.operand

proc `$`*(match: Match): string =
  let prefix = " ".repeat(match.match_def.location.column - 1)
  let child_prefix = " ".repeat(match.match_def.location.column + 1)
  var lines = @[prefix & $(match.match_def)]
  for case_block in match.case_blocks:
    lines.add(child_prefix & $(case_block))
  lines.add(child_prefix & $(match.else_blocks[0]))
  return lines.join("\n")

proc c*(match: Match): string =
  var lines = @[
    fmt"{match.return_type.get} {match.destination};",
    fmt"switch({match.operand}) " & "{",
  ]
  for case_block in match.case_blocks:
    lines.add(case_block.c(match.destination))
  for else_block in match.else_blocks:
    lines.add(else_block.c(match.destination))
  lines.add("}")
  return lines.join("\n")

proc add_case*(match: Match, case_block: Case): void =
  match.case_blocks.add(case_block)

proc add_else*(match: Match, else_block: Else): void =
  match.else_blocks.add(else_block)

proc new_match*(match_def: MatchDefinition): Match =
  Match(match_def: match_def)

type Function* = ref object of RootObj
  steps*: uint = 0
  definition*: FunctionDefinition
  statements*: seq[(uint, Statement)]
  matches*: seq[(uint, Match)]
  scope*: Table[string, ArgumentDefinition]

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

proc hash*(function: Function): Hash = function.definition.hash

proc `$`*(function: Function): string =
  let prefix = " ".repeat(function.definition.location.column - 1)
  let child_prefix = " ".repeat(function.definition.location.column + 1)
  var lines = @[prefix & $(function.definition)]

  var sindex = 0
  var mindex = 0
  for step in 0..<function.steps:
    if sindex < function.statements.len and function.statements[sindex][0] == step:
      let (_, statement) = function.statements[sindex]
      lines.add(child_prefix & $(statement))
      sindex += 1
    else:
      let (_, match) = function.matches[mindex]
      lines.add(child_prefix & $(match))
      mindex += 1
  lines.join("\n")

proc c*(function: Function): string =
  let args_def_str = function.definition.arg_def_list.map_it(
      fmt"{it.arg_type} {it.arg_name}").join(", ")
  let signature = fmt"{function.return_type} {function.name}({args_def_str})"
  var body: seq[string]
  # TODO: consider match blocks as well
  var sindex = 0
  var mindex = 0
  for step in 0..<function.steps:
    if sindex < function.statements.len and function.statements[sindex][0] == step:
      let (_, statement) = function.statements[sindex]
      let arg_type = function.scope[$(statement.destination)].arg_type
      body.add(fmt"{arg_type} {statement.destination} = {statement.function_call};")
      sindex += 1
    else:
      let (_, match) = function.matches[mindex]
      body.add(match.c)
      mindex += 1

  # TODO: consider match blocks as well
  if function.statements.len == 0:
    let (_, match) = function.matches[^1]
    body.add(fmt"return {match.destination};")
  elif function.matches.len == 0:
    let (_, statement) = function.statements[^1]
    body.add(fmt"return {statement.destination};")
  else:
    if function.matches[^1][0] > function.statements[^1][0]:
      let (_, match) = function.matches[^1]
      body.add(fmt"return {match.destination};")
    elif function.matches.len == 0:
      let (_, statement) = function.statements[^1]
      body.add(fmt"return {statement.destination};")

  @[signature, "{", body.join("\n"), "}"].join("\n")

proc is_start*(function: Function): bool =
  let name = $(function.definition.name)
  let return_type = $(function.definition.return_type)
  let arity = function.definition.arg_def_list.len
  let first_arg_type = $(function.definition.arg_def_list[0].arg_type)
  return name == "start" and return_type == "U8" and arity == 1 and
      first_arg_type == "U8"

proc new_function*(definition: FunctionDefinition): Function =
  Function(definition: definition)

proc add_statement*(function: Function, statement: Statement): void =
  function.statements.add((function.steps, statement))
  function.steps += 1

proc add_match*(function: Function, match: Match): void =
  function.matches.add((function.steps, match))
  function.steps += 1

type Module* = ref object of RootObj
  name: string

proc `$`*(module: Module): string = module.name

type File* = ref object of RootObj
  location*: Location
  modules: seq[Module]
  functions*: seq[Function]
  builtins*: seq[FunctionDefinition]

proc name*(file: File): string =
  file.location.filename

proc new_file*(filename: string): File =
  let modules = @["U8", "U16", "U32", "U64", "S8", "S16", "S32", "S64", "S64",
      "F32", "F64", "Pointer"].map_it(Module(name: it))
  let builtins = @[
    new_function_definition("U8_init", @[("U8", "a")], "U8"),
    new_function_definition("U8_from_Pointer", @[("Pointer", "p")], "U8"),
    new_function_definition("U8_lshift", @[("U8", "a"), ("U64", "b")], "U8"),
    new_function_definition("U8_rshift", @[("U8", "a"), ("U64", "b")], "U8"),
    new_function_definition("U8_and", @[("U8", "a"), ("U8", "b")], "U8"),
    new_function_definition("U8_or", @[("U8", "a"), ("U8", "b")], "U8"),
    new_function_definition("U16_init", @[("U16", "a")], "U16"),
    new_function_definition("U32_init", @[("U32", "a")], "U32"),
    # U64
    new_function_definition("U64_init", @[("U64", "a")], "U64"),
    new_function_definition("U64_compare", @[("U64", "a"), ("U64", "b")],
        "U64"),
    new_function_definition("U64_add", @[("U64", "a"), ("U64", "b")], "U64"),
    new_function_definition("U64_subtract", @[("U64", "a"), ("U64", "b")],
        "U64"),
    new_function_definition("U64_multiply", @[("U64", "a"), ("U64", "b")],
        "U64"),
    new_function_definition("U64_quotient", @[("U64", "a"), ("U64", "b")],
        "U64"),
    new_function_definition("U64_remainder", @[("U64", "a"), ("U64", "b")],
        "U64"),
    new_function_definition("System_print_U64", @[("U64", "a")], "U64"),
    new_function_definition("S8_init", @[("S8", "a")], "S8"),
    new_function_definition("S16_init", @[("S16", "a")], "S16"),
    new_function_definition("S32_init", @[("S32", "a")], "S32"),
    # S64
    new_function_definition("S64_init", @[("S64", "a")], "S64"),
    new_function_definition("S64_from_U8", @[("U8", "a")], "S64"),
    new_function_definition("S64_add", @[("S64", "a"), ("S64", "b")], "S64"),
    new_function_definition("S64_subtract", @[("S64", "a"), ("S64", "b")],
        "S64"),
    new_function_definition("S64_multiply", @[("S64", "a"), ("S64", "b")],
        "S64"),
    new_function_definition("S64_quotient", @[("S64", "a"), ("S64", "b")],
        "S64"),
    new_function_definition("S64_remainder", @[("S64", "a"), ("S64", "b")],
        "S64"),
    new_function_definition("S64_compare", @[("S64", "a"), ("S64", "b")],
        "S64"),
    new_function_definition("System_print_S64", @[("S64", "a")], "U64"),
    new_function_definition("F32_init", @[("F32", "a")], "F32"),
    new_function_definition("F64_init", @[("F64", "a")], "F64"),
    new_function_definition("Pointer_init", @[("Pointer", "a")], "Pointer"),
    new_function_definition("Pointer_shift", @[("Pointer", "a"), ("U64", "b")],
        "Pointer"),
    new_function_definition("Pointer_write_U8", @[("Pointer", "a"), ("U8",
        "b")], "Pointer"),
    new_function_definition("System_allocate", @[("U64", "size")], "Pointer"),
    new_function_definition("System_free", @[("Pointer", "ptr")], "U64"),
  ]
  File(modules: modules, builtins: builtins, location: new_file_location(filename))

proc `$`*(file: File): string =
  file.functions.map_it($(it)).join("\n\n")

proc find_module*(file: File, module_name: Token): Result[Module, string] =
  for module in file.modules:
    if $(module) == $(module_name):
      return ok(module)
  err(fmt"{module_name} does not exist in the scope")

proc find_start_function*(file: File): Result[Function, string] =
  for function in file.functions:
    if function.is_start():
      return ok(function)
  err(fmt"{file.name} failed to find start function")

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
    BK_FILE, BK_FUNCTION, BK_STATEMENT, BK_MATCH, BK_CASE, BK_ELSE
  Block* = ref object of RootObj
    case kind*: BlockKind
    of BK_FILE: file*: File
    of BK_FUNCTION: function*: Function
    of BK_STATEMENT: statement*: Statement
    of BK_MATCH: match_block*: Match
    of BK_CASE: case_block*: Case
    of BK_ELSE: else_block*: Else

proc location*(asl_block: Block): Location =
  case asl_block.kind:
  of BK_FILE: asl_block.file.location
  of BK_FUNCTION: asl_block.function.location
  of BK_STATEMENT: asl_block.statement.location
  of BK_MATCH: asl_block.match_block.location
  of BK_CASE: asl_block.case_block.location
  of BK_ELSE: asl_block.else_block.location

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
  ok()

proc add_child*(parent: Block, child: Block): Result[void, string] =
  case parent.kind:
  of BK_FILE:
    case child.kind:
    of BK_FUNCTION:
      ? parent.file.add_function(child.function)
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

proc new_block*(filename: string): Block =
  Block(kind: BK_FILE, file: new_file(filename))

proc new_block*(line: Line): Result[Block, string] =
  let prefix = line.location.column - 1
  case line.kind:
  of LK_FUNCTION_DEFINITION:
    if prefix != 0:
      return err(fmt"{line.location} indentation error expected 0 spaces but found {prefix}")
    return ok(Block(kind: BK_FUNCTION, function: new_function(line.func_def)))
  of LK_STATEMENT:
    if prefix notin {2, 6}: # handle case/else blocks as well
      return err(fmt"{line.location} indentation error expected 2/6 spaces but found {prefix}")
    return ok(Block(kind: BK_STATEMENT, statement: line.statement))
  of LK_MATCH_DEFINITION:
    if prefix != 2:
      return err(fmt"{line.location} indentation error expected 2 spaces but found {prefix}")
    return ok(Block(kind: BK_MATCH, match_block: new_match(line.match_def)))
  of LK_CASE_DEFINITION:
    if prefix != 4:
      return err(fmt"{line.location} indentation error expected 4 spaces but found {prefix}")
    return ok(Block(kind: BK_CASE, case_block: new_case(line.case_def)))
  of LK_ELSE_DEFINITION:
    if prefix != 4:
      return err(fmt"{line.location} indentation error expected 4 spaces but found {prefix}")
    return ok(Block(kind: BK_ELSE, else_block: new_else(line.else_def)))

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
