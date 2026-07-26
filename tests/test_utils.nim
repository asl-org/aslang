## Tests for the generic graph utilities in
## `src/resolver/parser/utils.nim`: `bfs` (breadth-first walk with
## per-node processing) and `topoSort` (DFS topological sort with
## cycle detection). Both are exercised indirectly through the
## parser's file loader in `test_loader.nim`, but these tests target
## their algorithmic corners directly.

import unittest, results, strutils, tables

import analyzer/defanalyzer/resolver/parser/utils

# --- bfs helpers ----------------------------------------------------
# `bfs[T, V]` needs a `process(node): Result[V, string]` and a
# `neighbors(value): seq[T]`. The tests below use T=string ("node
# label") with V=string (echo the node back as its own value) so
# neighbors can look up edges from a static case-block over the node.

proc echoProcess(n: string): Result[string, string] = ok(n)

suite "utils.bfs":

  test "single-node graph visits just the root":
    let neighbors = proc(v: string): seq[string] = @[]
    let r = bfs("root", echoProcess, neighbors)
    check r.isOk
    check r.get.len == 1
    check "root" in r.get

  test "linear chain visits every node exactly once":
    # A -> B -> C.
    let neighbors = proc(v: string): seq[string] =
      case v:
      of "A": @["B"]
      of "B": @["C"]
      else: @[]
    let r = bfs("A", echoProcess, neighbors)
    check r.isOk
    check r.get.len == 3
    check "A" in r.get and "B" in r.get and "C" in r.get

  test "cycle in the graph is not an error for bfs (visited set dedupes)":
    # A -> B -> A. BFS visits A once, then B, then tries to enqueue A
    # again but the visited set catches it.
    let neighbors = proc(v: string): seq[string] =
      case v:
      of "A": @["B"]
      of "B": @["A"]
      else: @[]
    let r = bfs("A", echoProcess, neighbors)
    check r.isOk
    check r.get.len == 2

  test "diamond graph collapses the shared descendant to one visit":
    # A -> B, A -> C; both B and C -> D. D is visited once.
    let neighbors = proc(v: string): seq[string] =
      case v:
      of "A": @["B", "C"]
      of "B": @["D"]
      of "C": @["D"]
      else: @[]
    let r = bfs("A", echoProcess, neighbors)
    check r.isOk
    check r.get.len == 4

  test "process error aborts the walk and propagates":
    let process = proc(n: string): Result[string, string] =
      if n == "boom": err("processing failed")
      else: ok(n)
    let neighbors = proc(v: string): seq[string] =
      if v == "start": @["boom"] else: @[]
    let r = bfs("start", process, neighbors)
    check r.isErr
    check r.error == "processing failed"

suite "utils.topoSort":

  test "single-node graph returns just the root":
    let neighbors = proc(n: string): seq[string] = @[]
    let r = topoSort("only", neighbors)
    check r.isOk
    check r.get == @["only"]

  test "linear chain returns leaves first, root last":
    # A -> B -> C. Post-order: C, B, A.
    let neighbors = proc(n: string): seq[string] =
      case n:
      of "A": @["B"]
      of "B": @["C"]
      else: @[]
    let r = topoSort("A", neighbors)
    check r.isOk
    check r.get == @["C", "B", "A"]

  test "diamond graph orders both parents before the shared child":
    # A depends on B and C; both -> D. Post-order: D first, A last.
    let neighbors = proc(n: string): seq[string] =
      case n:
      of "A": @["B", "C"]
      of "B": @["D"]
      of "C": @["D"]
      else: @[]
    let r = topoSort("A", neighbors)
    check r.isOk
    let order = r.get
    check order.len == 4
    check order.find("D") < order.find("B")
    check order.find("D") < order.find("C")
    check order[order.high] == "A"

  test "two-node cycle is rejected with both node names in the error":
    let neighbors = proc(n: string): seq[string] =
      case n:
      of "A": @["B"]
      of "B": @["A"]
      else: @[]
    let r = topoSort("A", neighbors)
    check r.isErr
    check r.error.contains("cyclic")
    check r.error.contains("A")
    check r.error.contains("B")

  test "self-loop is rejected":
    let neighbors = proc(n: string): seq[string] =
      if n == "solo": @["solo"] else: @[]
    let r = topoSort("solo", neighbors)
    check r.isErr
    check r.error.contains("cyclic")
    check r.error.contains("solo")

  test "three-node cycle shows the full cycle path":
    # A -> B -> C -> A.
    let neighbors = proc(n: string): seq[string] =
      case n:
      of "A": @["B"]
      of "B": @["C"]
      of "C": @["A"]
      else: @[]
    let r = topoSort("A", neighbors)
    check r.isErr
    check r.error.contains("A -> B -> C -> A")

  test "unreachable nodes are not in the output":
    # Only A -> B is reachable from A; C is defined but never linked.
    let neighbors = proc(n: string): seq[string] =
      case n:
      of "A": @["B"]
      else: @[]
    let r = topoSort("A", neighbors)
    check r.isOk
    check r.get.len == 2
    check "C" notin r.get
