# Lifetime scope for automatic memory management.
#
# Each statement block forms a scope node in the tree. Allocations within
# a scope are freed at scope exit, except:
#   - The exit variable (returned or assigned to the outer scope)
#   - Variables consumed by ownership-taking calls (consumes_args metadata)
#
# All allocation/consumption decisions are driven by FunctionMetadata
# lookups — no string-based pattern matching on C function names.
#
# optimize_stmts recurses into nested bodies (if/switch/block), creating
# a child LifetimeScope for each — mirroring the C IR statement tree.

import tables, sets

import ../ir/types
import ../ir/constructors

# --- Types ---

type
  Allocation = object
    name: string
    kind: AllocKind

  LifetimeScope* = ref object of RootObj
    allocations: seq[Allocation]
    alloc_names: HashSet[string]
    owned_children: Table[string, seq[string]]
    exit_var: string
    consumed: HashSet[string]

# --- Allocation classification (metadata-driven) ---

proc classify_alloc(expr: CExpr,
    metadata: Table[string, FunctionMetadata]): AllocKind =
  if expr != nil and expr.kind == CEK_CALL:
    let name = expr.call_name
    if name in metadata:
      return metadata[name].alloc_kind
  return AK_PLAIN

proc is_allocation(expr: CExpr,
    metadata: Table[string, FunctionMetadata]): bool =
  if expr == nil or expr.kind != CEK_CALL: return false
  let name = expr.call_name
  if name in metadata: return metadata[name].returns_allocated
  return false

# --- Exit variable detection ---

proc find_exit_var(stmts: seq[CStmt]): string =
  ## The variable escaping this scope: either the return value or the
  ## RHS of the final assignment (match result propagation).
  if stmts.len == 0: return ""
  let last = stmts[^1]
  if last.kind == CSK_RETURN and last.return_expr != nil and
      last.return_expr.kind == CEK_IDENT:
    return last.return_expr.ident_name
  if last.kind == CSK_ASSIGN and last.assign_expr != nil and
      last.assign_expr.kind == CEK_IDENT:
    return last.assign_expr.ident_name
  return ""

# --- Consumed variable tracking ---
# A variable is "consumed" when its ownership transfers away:
#   - Direct aliasing (y = x) — x is consumed
#   - Passed to a consumes_args call (y = Foo_init(x)) — x is consumed
# Borrowing calls (print, compare, get) do NOT consume.

proc collect_consumed_expr(expr: CExpr, consumed: var HashSet[string],
    metadata: Table[string, FunctionMetadata]) =
  if expr == nil: return
  case expr.kind:
  of CEK_IDENT:
    consumed.incl(expr.ident_name)
  of CEK_CALL:
    # Only ownership-taking calls consume their arguments
    let name = expr.call_name
    if name in metadata and metadata[name].consumes_args:
      for arg in expr.call_args:
        collect_consumed_expr(arg, consumed, metadata)
  of CEK_BINARY:
    collect_consumed_expr(expr.lhs, consumed, metadata)
    collect_consumed_expr(expr.rhs, consumed, metadata)
  of CEK_CAST:
    collect_consumed_expr(expr.cast_expr, consumed, metadata)
  of CEK_LITERAL: discard

proc collect_consumed(stmts: seq[CStmt],
    metadata: Table[string, FunctionMetadata]): HashSet[string] =
  var consumed: HashSet[string]
  for stmt in stmts:
    case stmt.kind:
    of CSK_DECL:
      if stmt.decl_init != nil:
        collect_consumed_expr(stmt.decl_init, consumed, metadata)
    of CSK_ASSIGN:
      collect_consumed_expr(stmt.assign_expr, consumed, metadata)
    of CSK_EXPR:
      collect_consumed_expr(stmt.expr, consumed, metadata)
    of CSK_RETURN:
      collect_consumed_expr(stmt.return_expr, consumed, metadata)
    of CSK_IF:
      for (cond, body) in stmt.branches:
        collect_consumed_expr(cond, consumed, metadata)
        consumed.incl(collect_consumed(body, metadata))
      consumed.incl(collect_consumed(stmt.else_body, metadata))
    of CSK_SWITCH:
      collect_consumed_expr(stmt.switch_expr, consumed, metadata)
      for (case_val, body) in stmt.cases:
        consumed.incl(collect_consumed(body, metadata))
      consumed.incl(collect_consumed(stmt.switch_default, metadata))
    of CSK_BLOCK:
      consumed.incl(collect_consumed(stmt.block_stmts, metadata))
    of CSK_COMMENT, CSK_RAW: discard
  return consumed

# --- Constructor ---

proc new_scope*(stmts: seq[CStmt],
    metadata: Table[string, FunctionMetadata]): LifetimeScope =
  var scope = LifetimeScope()

  # 1. Track heap allocations in this scope
  for stmt in stmts:
    if stmt.kind == CSK_DECL and stmt.decl_init.is_allocation(metadata):
      scope.allocations.add(Allocation(name: stmt.decl_name,
          kind: classify_alloc(stmt.decl_init, metadata)))
      scope.alloc_names.incl(stmt.decl_name)

  # 2. Build ownership graph: parent consumes_args call -> its allocated arguments
  for stmt in stmts:
    if stmt.kind == CSK_DECL and stmt.decl_init != nil and
        stmt.decl_init.kind == CEK_CALL:
      let name = stmt.decl_init.call_name
      if name in metadata and metadata[name].consumes_args:
        var allocated_args: seq[string]
        for arg in stmt.decl_init.call_args:
          if arg.kind == CEK_IDENT and arg.ident_name in scope.alloc_names:
            allocated_args.add(arg.ident_name)
        if allocated_args.len > 0:
          scope.owned_children[stmt.decl_name] = allocated_args

  # 3. Find the variable escaping this scope
  scope.exit_var = find_exit_var(stmts)

  # 4. Find variables whose ownership has transferred away
  scope.consumed = collect_consumed(stmts, metadata)
  return scope

# --- Free generation ---

const STATUS_VALUE_OFFSET = "8" ## Union layout: id (U64, 8 bytes) at offset 0, value at offset 8

proc free_call(name: string): CStmt =
  c_expr_stmt(c_call("System_free", @[c_ident(name)]))

proc free_with_children(name: string,
    owned_children: Table[string, seq[string]]): seq[CStmt] =
  ## Free children first (depth-first), then the parent.
  var stmts: seq[CStmt]
  if name in owned_children:
    for child in owned_children[name]:
      stmts.add(free_with_children(child, owned_children))
  stmts.add(free_call(name))
  return stmts

proc free_status_deep(name: string): seq[CStmt] =
  ## Free inner pointer (boxed value or Error), then the Status.
  @[c_expr_stmt(c_call("System_free",
      @[c_call("Pointer_read", @[c_ident(name), c_lit(STATUS_VALUE_OFFSET)])])),
    free_call(name)]

proc generate_frees*(scope: LifetimeScope): seq[CStmt] =
  var stmts: seq[CStmt]
  for alloc in scope.allocations:
    if alloc.name == scope.exit_var or alloc.name in scope.consumed:
      continue
    case alloc.kind:
    of AK_STATUS_OWNED:
      stmts.add(free_status_deep(alloc.name))
    of AK_PLAIN, AK_STATUS_BORROWED:
      stmts.add(free_with_children(alloc.name, scope.owned_children))
  return stmts
