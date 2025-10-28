import results, strformat, tables, strutils, sets, algorithm, options

import deps_analyzer/parser
export parser

const DEBUG = false

proc deps(file: ast.File, module: UserModule, generic: Generic,
    argtype: ArgumentType, depth: int): Result[HashSet[UserModule], string] =
  let indent = "  ".repeat(depth)
  var module_set: HashSet[UserModule]
  case argtype.kind:
  of ATK_SIMPLE:
    let maybe_arg_module = file.find_module(argtype.module)
    if maybe_arg_module.is_ok:
      let arg_module = maybe_arg_module.get
      if arg_module.generics.len != 0:
        return err(fmt"{argtype.location} module `{arg_module.name.asl}` expects {arg_module.generics.len} generic types but found 0")
      case arg_module.kind:
      of MK_NATIVE:
        let native_module = ? arg_module.native_module
        if DEBUG: echo fmt"{indent}NATIVE MODULE: {native_module.name.asl}"
      of MK_USER:
        let user_module = ? arg_module.user_module
        if user_module == module:
          return err(fmt"{argtype.location} module `{module.name.asl}` can not be passed as an argument to generic constraint")
        if DEBUG: echo fmt"{indent}USER MODULE: {user_module.name.asl}"
        if user_module != module:
          module_set.incl(user_module)
    else:
      let arg_generic = ? module.find_generic(argtype.module)
      if arg_generic.name != generic.name:
        return err(fmt"{argtype.location} expected `{generic.name.asl}` but found `{argtype.module.asl}`")
      if DEBUG: echo fmt"{indent}GENERIC: {arg_generic.name.asl}"
  of ATK_NESTED:
    let arg_module = ? file.find_module(argtype.module)
    let user_module = ? arg_module.user_module
    if user_module.generics.len != argtype.children.len:
      return err(fmt"{argtype.location} module `{user_module.name.asl}` expects {user_module.generics.len} generic types but found {argtype.children.len}")
    if user_module.hash == module.hash:
      return err(fmt"{argtype.location} module `{module.name.asl}` can not be passed as an argument to generic constraint")

    if DEBUG: echo fmt"{indent} USER MODULE: {user_module.name.asl}"
    if user_module != module:
      module_set.incl(user_module)
    for child in argtype.children:
      let child_module_set = ? deps(file, module, generic, child, depth + 1)
      module_set.incl(child_module_set)
  ok(module_set)

proc deps(file: ast.File, module: UserModule, argtype: ArgumentType,
    depth: int): Result[HashSet[UserModule], string] =
  let indent = "  ".repeat(depth)
  var module_set: HashSet[UserModule]
  case argtype.kind:
  of ATK_SIMPLE:
    let maybe_arg_module = file.find_module(argtype.module)
    if maybe_arg_module.is_ok:
      let arg_module = maybe_arg_module.get
      if arg_module.generics.len != 0:
        return err(fmt"{argtype.location} module `{arg_module.name.asl}` expects {arg_module.generics.len} generic types but found 0")
      case arg_module.kind:
      of MK_NATIVE:
        let native_module = ? arg_module.native_module
        if DEBUG: echo fmt"{indent}NATIVE MODULE: {native_module.name.asl}"
      of MK_USER:
        let user_module = ? arg_module.user_module
        if DEBUG: echo fmt"{indent}USER MODULE: {user_module.name.asl}"
        if user_module != module:
          module_set.incl(user_module)
    else:
      let arg_generic = ? module.find_generic(argtype.module)
      if DEBUG: echo fmt"{indent}GENERIC: {arg_generic.name.asl}"
  of ATK_NESTED:
    let arg_module = ? file.find_module(argtype.module)
    let user_module = ? arg_module.user_module
    if user_module.generics.len != argtype.children.len:
      return err(fmt"{argtype.location} module `{user_module.name.asl}` expects {user_module.generics.len} generic types but found {argtype.children.len}")

    if DEBUG: echo fmt"{indent}USER MODULE: {user_module.name.asl}"
    if user_module != module:
      module_set.incl(user_module)
    for child in argtype.children:
      let child_module_set = ? deps(file, module, child, depth + 1)
      module_set.incl(child_module_set)
  ok(module_set)

proc deps(file: ast.File, argtype: ArgumentType,
    depth: int): Result[HashSet[UserModule], string] =
  let indent = "  ".repeat(depth)
  var module_set: HashSet[UserModule]
  case argtype.kind:
  of ATK_SIMPLE:
    let arg_module = ? file.find_module(argtype.module)
    if arg_module.generics.len != 0:
      return err(fmt"{argtype.location} module `{arg_module.name.asl}` expects {arg_module.generics.len} generic types but found 0")
    case arg_module.kind:
    of MK_NATIVE:
      let native_module = ? arg_module.native_module
      if DEBUG: echo fmt"{indent}NATIVE MODULE: {native_module.name.asl}"
    of MK_USER:
      let user_module = ? arg_module.user_module
      if DEBUG: echo fmt"{indent}USER MODULE: {user_module.name.asl}"
      module_set.incl(user_module)
  of ATK_NESTED:
    let arg_module = ? file.find_module(argtype.module)
    let user_module = ? arg_module.user_module
    if user_module.generics.len != argtype.children.len:
      return err(fmt"{argtype.location} module `{user_module.name.asl}` expects {user_module.generics.len} generic types but found {argtype.children.len}")

    if DEBUG: echo fmt"{indent}USER MODULE: {user_module.name.asl}"
    module_set.incl(user_module)
    for child in argtype.children:
      let child_module_set = ? deps(file, child, depth + 1)
      module_set.incl(child_module_set)
  ok(module_set)

proc deps(file: ast.File, module: UserModule, generic: Generic,
    depth: int): Result[HashSet[UserModule], string] =
  let indent = "  ".repeat(depth)
  var module_set: HashSet[UserModule]
  if DEBUG: echo fmt"{indent}GENERIC: {generic.name.asl}"
  for def in generic.defs:
    for arg in def.args:
      let arg_module_set = ? deps(file, module, generic, arg.argtype, depth + 1)
      module_set.incl(arg_module_set)
    let return_module_set = ? deps(file, module, generic, def.returns, depth + 1)
    module_set.incl(return_module_set)
  ok(module_set)

proc deps(file: ast.File, module: UserModule, struct: Struct,
    depth: int): Result[HashSet[UserModule], string] =
  let indent = "  ".repeat(depth)
  var module_set: HashSet[UserModule]

  if DEBUG:
    let maybe_named_struct = struct.name
    if maybe_named_struct.is_ok:
      let struct_name = maybe_named_struct.get
      echo fmt"{indent}STRUCT: {struct_name.asl}"
    else: echo fmt"{indent}STRUCT:"

  for field in struct.fields:
    let field_module_set = ? deps(file, module, field.argtype, depth + 1)
    module_set.incl(field_module_set)
  ok(module_set)

proc deps(file: ast.File, module: UserModule, def: FunctionDefinition,
    depth: int): Result[HashSet[UserModule], string] =
  let indent = "  ".repeat(depth)
  if DEBUG: echo fmt"{indent}FUNCTION DEF: {def.name.asl}"

  var module_set: HashSet[UserModule]
  for arg in def.args:
    let arg_module_set = ? deps(file, module, arg.argtype, depth + 1)
    module_set.incl(arg_module_set)
  let return_module_set = ? deps(file, module, def.returns, depth + 1)
  module_set.incl(return_module_set)
  ok(module_set)

proc deps(file: ast.File, module: UserModule, init: Initializer,
    depth: int): Result[HashSet[UserModule], string] =
  let indent = "  ".repeat(depth)
  if DEBUG: echo fmt"{indent}INIT: {init.location}"

  var module_set: HashSet[UserModule]
  case init.kind:
  of IK_LITERAL: discard
  of IK_STRUCT:
    let struct_init = ? init.struct
    let argtype = struct_init.struct_ref.module
    let argtype_module_set = ? deps(file, module, argtype, depth + 1)
    module_set.incl(argtype_module_set)
  ok(module_set)

proc deps(file: ast.File, module: UserModule, fnref: FunctionRef,
    depth: int): Result[HashSet[UserModule], string] =
  let indent = "  ".repeat(depth)
  if DEBUG: echo fmt"{indent}FUNCTION REF: {fnref.location}"

  var module_set: HashSet[UserModule]
  case fnref.kind:
  of FRK_LOCAL: discard
  of FRK_MODULE:
    let argtype = ? fnref.module
    let argtype_module_set = ? deps(file, module, argtype, depth + 1)
    module_set.incl(argtype_module_set)
  ok(module_set)

proc deps(file: ast.File, module: UserModule, expression: Expression,
    depth: int): Result[HashSet[UserModule], string] =
  let indent = "  ".repeat(depth)
  if DEBUG: echo fmt"{indent}EXPR: {expression.location}"

  var module_set: HashSet[UserModule]
  case expression.kind:
  of EK_FNCALL:
    let fncall = ? expression.fncall
    let fncall_module_set = ? deps(file, module, fncall.fnref, depth + 1)
    module_set.incl(fncall_module_set)
  of EK_INIT:
    let init = ? expression.init
    let init_module_set = ? deps(file, module, init, depth + 1)
    module_set.incl(init_module_set)
  of EK_STRUCT_GET: discard
  of EK_VARIABLE: discard
  ok(module_set)

proc deps(file: ast.File, module: UserModule, case_block: Case,
    depth: int): Result[HashSet[UserModule], string] =
  let indent = "  ".repeat(depth)
  if DEBUG: echo fmt"{indent}CASE: {case_block.location}"

  var module_set: HashSet[UserModule]
  for statement in case_block.statements:
    let statement_module_set = ? deps(file, module, statement.expression,
        depth + 1)
    module_set.incl(statement_module_set)
  ok(module_set)

proc deps(file: ast.File, module: UserModule, else_block: Else,
    depth: int): Result[HashSet[UserModule], string] =
  let indent = "  ".repeat(depth)
  if DEBUG: echo fmt"{indent}ELSE: {else_block.location}"

  var module_set: HashSet[UserModule]
  for statement in else_block.statements:
    let statement_module_set = ? deps(file, module, statement.expression,
        depth + 1)
    module_set.incl(statement_module_set)
  ok(module_set)

proc deps(file: ast.File, module: UserModule, match: Match, depth: int): Result[
    HashSet[UserModule], string] =
  let indent = "  ".repeat(depth)
  if DEBUG: echo fmt"{indent}MATCH: {match.location}"

  var module_set: HashSet[UserModule]
  for case_block in match.case_blocks:
    let case_block_module_set = ? deps(file, module, case_block, depth + 1)
    module_set.incl(case_block_module_set)

  case match.kind:
  of MK_CASE_ONLY: discard
  of MK_COMPLETE:
    let else_block = ? match.else_block
    let else_block_module_set = ? deps(file, module, else_block, depth + 1)
    module_set.incl(else_block_module_set)
  ok(module_set)

proc deps(file: ast.File, module: UserModule, step: FunctionStep,
    depth: int): Result[HashSet[UserModule], string] =
  let indent = "  ".repeat(depth)
  if DEBUG: echo fmt"{indent}FUNCTION STEP: {step.location}"

  var module_set: HashSet[UserModule]
  case step.kind:
  of FSK_STATEMENT:
    let statement = ? step.statement
    let statement_module_set = ? deps(file, module, statement.expression,
        depth + 1)
    module_set.incl(statement_module_set)
  of FSK_MATCH:
    let match = ? step.match
    let match_module_set = ? deps(file, module, match, depth + 1)
    module_set.incl(match_module_set)
  ok(module_set)

proc deps(file: ast.File, module: UserModule, function: Function,
    depth: int): Result[HashSet[UserModule], string] =
  let indent = "  ".repeat(depth)
  if DEBUG: echo fmt"{indent}FUNCTION: {function.name.asl}"

  var module_set: HashSet[UserModule]
  let function_module_set = ? deps(file, module, function.def, depth + 1)
  module_set.incl(function_module_set)

  for step in function.steps:
    let step_module_set = ? deps(file, module, step, depth + 1)
    module_set.incl(step_module_set)
  ok(module_set)

proc deps(file: ast.File, module: UserModule, depth: int = 0): Result[HashSet[
    UserModule], string] =
  if DEBUG: echo fmt"MODULE: {module.name.asl}"
  var module_set: HashSet[UserModule]
  for generic in module.generics:
    let generic_module_set = ? deps(file, module, generic, depth + 1)
    module_set.incl(generic_module_set)
  for struct in module.structs:
    let struct_module_set = ? deps(file, module, struct, depth + 1)
    module_set.incl(struct_module_set)
  for function in module.functions:
    let function_module_set = ? deps(file, module, function, depth + 1)
    module_set.incl(function_module_set)
  ok(module_set)

proc detect_cycle[T](graph: Table[T, HashSet[T]],
    node: T, visited: var Table[T, int],
    ancestors: var seq[T]): bool =
  if node in ancestors:
    return true

  if node in visited:
    return false

  visited[node] = visited.len
  ancestors.add(node)

  for child in graph[node]:
    if detect_cycle(graph, child, visited, ancestors):
      return true

  discard ancestors.pop()
  return false

proc deps*(file: ast.File): Result[seq[UserModule], string] =
  var module_graph: Table[UserModule, HashSet[UserModule]]
  for module in file.user_modules:
    module_graph[module] = ? deps(file, module)

  var visited: Table[UserModule, int]
  for module, deps in module_graph:
    if module notin visited:
      var ancestors: seq[UserModule]
      if detect_cycle(module_graph, module, visited, ancestors):
        for module in ancestors:
          echo fmt"{module.location} {module.name.asl}"

  var module_order = new_seq[UserModule](visited.len)
  for (module, index) in visited.pairs:
    module_order[index] = module
  module_order.reverse()
  if DEBUG:
    for module in module_order:
      echo fmt"{module.location} {module.name.asl}"
  ok(module_order)
