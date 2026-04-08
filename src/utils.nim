import results, strformat, strutils, sets

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
