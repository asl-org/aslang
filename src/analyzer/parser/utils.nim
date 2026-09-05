import results, strformat, strutils, sets, tables, deques, hashes

proc bfs*[T, V](
    root: T,
    process: proc(node: T): Result[V, string],
    neighbors: proc(value: V): seq[T]): Result[Table[T, V], string] =
  ## Breadth-first walk starting at `root`. For each un-visited node
  ## `n`, calls `process(n)` to derive a value `v`, records `n -> v`
  ## in the returned table, then enqueues every entry in
  ## `neighbors(v)` that hasn't been seen yet. Any `process` error
  ## aborts the walk and propagates.
  ##
  ## `T` must be hashable (usable as a Table key). `V` is the
  ## per-node computed value — for the parser's file loader, T is
  ## a filepath and V is the parsed File.
  var visited: Table[T, V]
  var queued: HashSet[T]
  var queue: Deque[T]

  queue.addLast(root)
  queued.incl(root)

  while queue.len > 0:
    let current = queue.popFirst()
    let value = ? process(current)
    visited[current] = value
    for next in neighbors(value):
      if next notin queued:
        queue.addLast(next)
        queued.incl(next)

  ok(visited)

proc topoSort*(
    node: string,
    getNeighbors: proc(node: string): seq[string],
    visiting: var seq[string],
    visited: var HashSet[string],
    order: var seq[string]): Result[void, string] =
  ## DFS topological sort with cycle detection.
  ## Nodes are appended to `order` in post-order (leaves first, root last).
  ## Returns err with the cycle path if a cycle is found.
  if node in visited: return ok()
  if node in visiting:
    let idx = visiting.find(node)
    let cycle = visiting[idx .. ^1] & @[node]
    let cycleStr = cycle.join(" -> ")
    return err(fmt"cyclic dependency detected: {cycleStr}")

  visiting.add(node)

  for neighbor in getNeighbors(node):
    ? topoSort(neighbor, getNeighbors, visiting, visited, order)

  discard visiting.pop()
  visited.incl(node)
  order.add(node)
  ok()

proc topoSort*(root: string,
    getNeighbors: proc(node: string): seq[string]): Result[seq[string], string] =
  ## Topological sort with cycle detection starting from root.
  ## Returns nodes in dependency order: leaves first, root last.
  var visiting: seq[string]
  var visited: HashSet[string]
  var order: seq[string]
  ? topoSort(root, getNeighbors, visiting, visited, order)
  ok(order)
