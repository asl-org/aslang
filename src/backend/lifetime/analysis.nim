import tables, options

import ../ir/types
import ../ir/constructors
import scope

# --- Tree traversal: recurse into nested scopes ---

proc optimize_stmts(stmts: seq[CStmt],
    metadata: Table[string, FunctionMetadata],
    parent_alloc_kinds: Table[string, AllocKind],
    extra_allocs: seq[string] = @[]): seq[CStmt]

proc optimize_if(stmt: CStmt,
    metadata: Table[string, FunctionMetadata],
    parent_alloc_kinds: Table[string, AllocKind]): CStmt =
  ## Optimize an if-statement, detecting Status match patterns.
  ## For OWNED Status matches: track extracted inner values as allocations.
  ## For else branches of OWNED matches: inject inner-pointer free.
  var match_info: Option[(string, AllocKind)]
  if stmt.branches.len > 0:
    match_info = detect_status_match(stmt.branches[0][0], parent_alloc_kinds)

  var new_branches: seq[(CExpr, seq[CStmt])]
  for (cond, body) in stmt.branches:
    if match_info.is_some and match_info.get[1] == AK_STATUS_OWNED:
      let status_name = match_info.get[0]
      let extractions = find_extractions(body, status_name, metadata)
      new_branches.add((cond, optimize_stmts(body, metadata,
          parent_alloc_kinds, extractions)))
    else:
      new_branches.add((cond, optimize_stmts(body, metadata,
          parent_alloc_kinds)))

  var new_else: seq[CStmt]
  if stmt.else_body.len > 0:
    if match_info.is_some and match_info.get[1] == AK_STATUS_OWNED:
      let status_name = match_info.get[0]
      # Only free inner if the Status is not being returned in the else branch
      let else_exit = find_exit_var(stmt.else_body)
      if else_exit != status_name:
        new_else.add(inner_free_stmt(status_name))
    new_else.add(optimize_stmts(stmt.else_body, metadata, parent_alloc_kinds))
  c_if(new_branches, new_else)

proc optimize_stmts(stmts: seq[CStmt],
    metadata: Table[string, FunctionMetadata],
    parent_alloc_kinds: Table[string, AllocKind],
    extra_allocs: seq[string] = @[]): seq[CStmt] =
  let scope = new_scope(stmts, metadata, extra_allocs)
  let frees = scope.generate_frees()
  # Merge parent's alloc kinds with this scope's for child processing
  var combined_kinds = parent_alloc_kinds
  for name, kind in scope.alloc_kinds.pairs:
    combined_kinds[name] = kind

  let reassign_frees = scope.reassign_frees
  var optimized: seq[CStmt]
  for i, stmt in stmts:
    # Free old value before reassignment of allocated variable
    if i in reassign_frees:
      optimized.add(reassign_frees[i])
    let is_scope_exit = (stmt.kind == CSK_RETURN) or
        (stmt.kind == CSK_ASSIGN and i == stmts.len - 1)
    if is_scope_exit:
      optimized.add(frees)
      optimized.add(stmt)
    else:
      case stmt.kind:
      of CSK_IF:
        optimized.add(optimize_if(stmt, metadata, combined_kinds))
      of CSK_SWITCH:
        var new_cases: seq[(CExpr, seq[CStmt])]
        for (case_val, body) in stmt.cases:
          new_cases.add((case_val, optimize_stmts(body, metadata,
              combined_kinds)))
        let new_default = if stmt.switch_default.len > 0: optimize_stmts(
            stmt.switch_default, metadata, combined_kinds) else: @[]
        optimized.add(c_switch(stmt.switch_expr, new_cases, new_default))
      of CSK_BLOCK:
        optimized.add(c_block(optimize_stmts(stmt.block_stmts, metadata,
            combined_kinds)))
      else:
        optimized.add(stmt)

  return optimized

# --- Pass 1: infer function metadata from call sites ---

proc analyze_call(meta: var FunctionMetadata, name: string,
    metadata: Table[string, FunctionMetadata]) =
  if name in metadata:
    let called = metadata[name]
    if called.allocates:
      meta.allocates = true
    if called.mutates_args:
      meta.mutates_args = true
      meta.reads_only = false

proc collect_metadata(body: seq[CStmt],
    metadata: Table[string, FunctionMetadata]): FunctionMetadata =
  var meta = new_function_metadata()

  for stmt in body:
    case stmt.kind:
    of CSK_DECL:
      if stmt.decl_init != nil and stmt.decl_init.kind == CEK_CALL:
        analyze_call(meta, stmt.decl_init.call_name, metadata)
    of CSK_ASSIGN:
      if stmt.assign_expr != nil and stmt.assign_expr.kind == CEK_CALL:
        analyze_call(meta, stmt.assign_expr.call_name, metadata)
    of CSK_EXPR:
      if stmt.expr != nil and stmt.expr.kind == CEK_CALL:
        analyze_call(meta, stmt.expr.call_name, metadata)
    of CSK_RETURN:
      if stmt.return_expr != nil and stmt.return_expr.kind == CEK_IDENT:
        for s in body:
          if s.kind == CSK_DECL and
              s.decl_name == stmt.return_expr.ident_name and
              s.decl_init != nil and s.decl_init.kind == CEK_CALL:
            let call_name = s.decl_init.call_name
            if call_name in metadata and metadata[call_name].returns_allocated:
              meta.returns_allocated = true
    else: discard

  return meta

# --- Entry point ---

proc optimize*(program: CProgram): CProgram =
  # Pass 1: start with analyzer-provided metadata, infer gaps from C IR
  var metadata = program.metadata
  for decl in program.definitions:
    if decl.kind == CDK_FUNC_DEF and decl.func_name notin metadata:
      metadata[decl.func_name] = collect_metadata(decl.func_body, metadata)

  # Pass 2: inject frees using scope-based lifetime analysis
  let empty_kinds = initTable[string, AllocKind]()
  var new_defs: seq[CDecl]
  for decl in program.definitions:
    if decl.kind == CDK_FUNC_DEF:
      let optimized_body = optimize_stmts(decl.func_body, metadata,
          empty_kinds)
      new_defs.add(c_func_def(decl.func_return, decl.func_name,
          decl.func_params, optimized_body))
    else:
      new_defs.add(decl)

  CProgram(includes: program.includes, typedefs: program.typedefs,
      forward_decls: program.forward_decls, definitions: new_defs,
      main: program.main, metadata: metadata)
