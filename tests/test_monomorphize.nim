## Monomorphizer tests — drive the full pipeline (parse + resolve +
## analyze + monomorphize) over small programs that target each
## monomorphizer path: the lowering of every expression / statement
## kind, generic copy selection, recursion, and the remaining `todo`
## arms. MonoApp internals are private, so each test asserts on whether
## the program lowers (isOk) or hits a specific `todo` (isErr + message).

import unittest, results

import tutils

# A minimal prelude: the primitive types and Status a program needs to
# reach the monomorphizer. Defined inline (no std vendor) so each test is
# self-contained and the entry's `public func start(): i32` resolves.
const Prelude = """
public module i32:
  literal: "int32"

public module u8:
  literal: "uint8"

public module u32:
  literal: "uint32"

public module u64:
  literal: "uint64"

public module String:
  literal: "string"

public generic Any:
  func byte_size(): u64

public generic Failure:
  func code(f: Failure): u32

public module Error:
  struct:
    code: u32

  public func code(e: Error): u32
    e.code

public module Status:
  union:
    Ok { value: Any }
    Err { error: Failure }

public module Array:
  struct(Any):
    size: u32

  @extern("array_get")
  public func get(arr: Array[Any], index: u32): Any!

  @extern("array_set")
  public func set(arr: Array[Any], index: u32, item: Any): Array[Any]!
"""

suite "monomorphize — happy paths":

  test "entry returning a literal monomorphizes":
    let (r, dir) = monomorphizeSingle(Prelude & """
public module M:
  public func start(): i32
    i32 0
""")
    cleanupDir(dir)
    check r.isOk

  test "a default module function call monomorphizes":
    let (r, dir) = monomorphizeSingle(Prelude & """
public module M:
  func helper(): i32
    i32 7

  public func start(): i32
    M.helper()
""")
    cleanupDir(dir)
    check r.isOk

  test "self-recursion closes the memo knot (one copy)":
    let (r, dir) = monomorphizeSingle(Prelude & """
public module M:
  func loop(n: i32): i32
    M.loop(n)

  public func start(): i32
    M.loop(i32 0)
""")
    cleanupDir(dir)
    check r.isOk

  test "try, union-match, and field binding monomorphize":
    let (r, dir) = monomorphizeSingle(Prelude & """
public module M:
  func mk(): i32!
    i32!.Ok { value: i32 1 }

  func run(): i32!
    v = try M.mk()
    i32!.Ok { value: v }

  public func start(): i32
    match M.run():
      case Ok { value: x }:
        x
      case _:
        i32 0
""")
    cleanupDir(dir)
    check r.isOk

  test "integer-pattern match monomorphizes":
    let (r, dir) = monomorphizeSingle(Prelude & """
public module M:
  public func start(): i32
    x = i32 0
    match x:
      case 0:
        i32 1
      case _:
        i32 2
""")
    cleanupDir(dir)
    check r.isOk

  test "struct initializer and getter monomorphize":
    let (r, dir) = monomorphizeSingle(Prelude & """
public module Box:
  struct:
    n: i32

  public func make(): Box
    Box { n: i32 5 }

  public func get(b: Box): i32
    b.n

public module M:
  public func start(): i32
    b = Box.make()
    Box.get(b)
""")
    cleanupDir(dir)
    check r.isOk

  test "struct setter (field update) monomorphizes":
    let (r, dir) = monomorphizeSingle(Prelude & """
public module Box:
  struct:
    n: i32

  public func make(): Box
    Box { n: i32 5 }

  public func get(b: Box): i32
    b.n

  public func bump(b: Box): Box
    b.n = i32 9
    b

public module M:
  public func start(): i32
    b = Box.make()
    c = Box.bump(b)
    Box.get(c)
""")
    cleanupDir(dir)
    check r.isOk

  test "extern function call monomorphizes":
    let (r, dir) = monomorphizeSingle(Prelude & """
public module M:
  @extern("m_compute")
  func compute(): i32

  public func start(): i32
    M.compute()
""")
    cleanupDir(dir)
    check r.isOk

suite "monomorphize — todo arms":

  test "a call through a generic parameter is a todo":
    # A drawing domain: a Shape reports how many sides it has, consuming the
    # shape itself. A Polygon stores its vertices (an Array of Points) and its
    # side count is how many it holds; a Square is fixed at four. `start` builds
    # a triangle and asks it via the generic (`Shape.sides(triangle)`) — a call
    # through the generic parameter, which the monomorphizer does not yet
    # resolve to the concrete impl.
    let (r, dir) = monomorphizeSingle(Prelude & """
generic Shape:
  public func sides(s: Shape): u32

module Point:
  struct:
    x: i32
    y: i32

module Square:
  struct:
    origin: Point

  public func sides(s: Square): u32
    u32 4

module Polygon:
  struct:
    points: Array[Point]

  public func sides(p: Polygon): u32
    pts = p.points
    pts.size

public module Driver:
  func makeTriangle(): Polygon!
    points = Array[Point] { size: u32 3 }
    points = try Array.set(points, u32 0, Point { x: i32 0, y: i32 0 })
    points = try Array.set(points, u32 1, Point { x: i32 1, y: i32 0 })
    points = try Array.set(points, u32 2, Point { x: i32 1, y: i32 1 })
    Polygon!.Ok { value: Polygon { points: points } }

  public func start(): i32
    match Driver.makeTriangle():
      case Ok { value: triangle }:
        match Shape.sides(triangle):
          case _:
            i32 0
      case _:
        i32 1
""")
    cleanupDir(dir)
    check r.isErr
    check errorContains(r.error, "generic-target call")
