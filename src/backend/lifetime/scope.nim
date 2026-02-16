# Lifetime scope for automatic memory management.
#
# Each statement block forms a scope node in the tree. Allocations within
# a scope are freed at scope exit, except:
#   - The exit variable (returned or assigned to the outer scope)
#   - Variables consumed by ownership transfer (aliasing or consumes_args calls)
#
# All allocation/consumption decisions are driven by FunctionMetadata
# lookups — no string-based pattern matching on C function names.
#
# Status ownership:
#   AK_STATUS_OWNED  — inner pointer is a new allocation (e.g., Array_get)
#                      Extraction from Ok/Err transfers ownership of inner.
#   AK_STATUS_BORROWED — inner pointer is borrowed from arg (e.g., Array_set)
#                        Extraction creates an alias, not an allocation.
#
# optimize_stmts recurses into nested bodies (if/switch/block), creating
# a child LifetimeScope for each — mirroring the C IR statement tree.

import tables, sets, options

import ../../ir/types
import ../../ir/constructors

# --- Types ---

type
  Allocation = object
    name: string
    kind: AllocKind

  LifetimeScope* = ref object of RootObj
    allocations: seq[Allocation]
    alloc_names: HashSet[string]
    alloc_kinds: Table[string, AllocKind]
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

proc find_exit_var*(stmts: seq[CStmt]): string =
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
    let name = expr.call_name
    if name in metadata and metadata[name].consumes_args:
      for arg in expr.call_args:
        collect_consumed_expr(arg, consumed, metadata)
  of CEK_BINARY, CEK_CAST, CEK_LITERAL: discard

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

# --- Status match detection ---

proc detect_status_match*(cond: CExpr,
    alloc_kinds: Table[string, AllocKind]): Option[(string, AllocKind)] =
  ## Detect if an if-condition is a Status match: Status_get_id([impl_id,] X) == N
  ## Returns the Status variable name and its AllocKind.
  if cond.kind == CEK_BINARY and cond.op == "==" and
      cond.lhs.kind == CEK_CALL and cond.lhs.call_args.len > 0:
    let arg = cond.lhs.call_args[^1]
    if arg.kind == CEK_IDENT and arg.ident_name in alloc_kinds:
      let kind = alloc_kinds[arg.ident_name]
      if kind == AK_STATUS_OWNED or kind == AK_STATUS_BORROWED:
        return some((arg.ident_name, kind))
  return none((string, AllocKind))

proc find_extractions*(stmts: seq[CStmt], status_name: string,
    metadata: Table[string, FunctionMetadata]): seq[string] =
  ## Find variable names that are union extraction results from a Status.
  var names: seq[string]
  for stmt in stmts:
    if stmt.kind == CSK_DECL and stmt.decl_init != nil and
        stmt.decl_init.kind == CEK_CALL:
      let fn_name = stmt.decl_init.call_name
      if fn_name in metadata and metadata[fn_name].is_union_extraction:
        if stmt.decl_init.call_args.len > 0 and
            stmt.decl_init.call_args[^1].kind == CEK_IDENT and
            stmt.decl_init.call_args[^1].ident_name == status_name:
          names.add(stmt.decl_name)
  return names

proc inner_free_stmt*(status_name: string): CStmt =
  ## Free the inner pointer at offset 8 of a Status (the union value slot).
  c_expr_stmt(c_call("System_free",
      @[c_call("Pointer_read",
          @[c_ident(status_name), c_lit(UNION_VALUE_OFFSET)])]))

# --- Constructor ---

proc new_scope*(stmts: seq[CStmt],
    metadata: Table[string, FunctionMetadata],
    extra_allocs: seq[string] = @[]): LifetimeScope =
  var scope = LifetimeScope()

  # 1. Track heap allocations in this scope
  for stmt in stmts:
    if stmt.kind == CSK_DECL and stmt.decl_init.is_allocation(metadata):
      let kind = classify_alloc(stmt.decl_init, metadata)
      scope.allocations.add(Allocation(name: stmt.decl_name, kind: kind))
      scope.alloc_names.incl(stmt.decl_name)
      scope.alloc_kinds[stmt.decl_name] = kind

  # 1b. Add parent-provided allocations (extracted from OWNED Status)
  for name in extra_allocs:
    scope.allocations.add(Allocation(name: name, kind: AK_PLAIN))
    scope.alloc_names.incl(name)
    scope.alloc_kinds[name] = AK_PLAIN

  # 2. Build ownership graph: consumes_args call owns its allocated arguments
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

proc generate_frees*(scope: LifetimeScope): seq[CStmt] =
  ## Generate free statements for all allocations that don't escape.
  ## Consumed args are freed via their parent's ownership tree.
  var stmts: seq[CStmt]
  for alloc in scope.allocations:
    if alloc.name == scope.exit_var or alloc.name in scope.consumed:
      continue
    stmts.add(free_with_children(alloc.name, scope.owned_children))
  return stmts

proc alloc_kinds*(scope: LifetimeScope): Table[string, AllocKind] =
  scope.alloc_kinds
