## Monomorphizer tests — drive the full pipeline (parse + resolve +
## analyze + monomorphize) over small programs that target each
## monomorphizer path: the lowering of every expression / statement
## kind, generic copy selection, recursion, and the remaining `todo`
## arms. MonoApp internals are private, so each test asserts on whether
## the program lowers (isOk) or hits a specific `todo` (isErr + message).

import unittest, results, tables, sequtils

import tutils
import monomorphize

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

suite "monomorphize — generic dispatch":

  test "a call through a generic parameter resolves to the concrete impl":
    # A drawing domain: a Shape reports how many sides it has, consuming the
    # shape itself. A Polygon stores its vertices (an Array of Points) and its
    # side count is how many it holds; a Square is fixed at four. `start` builds
    # a triangle and asks it via the generic (`Shape.sides(triangle)`) — a call
    # through the generic parameter, which the monomorphizer resolves through
    # the copy's impls to the concrete impl (here Polygon.sides).
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
    check r.isOk

suite "monomorphize — occurs check":

  test "type-growing recursion is rejected (does not loop forever)":
    # `grow` is generic over Any and recurses with its argument wrapped one
    # Array deeper, so each instantiation is a strictly larger type:
    # grow[i32] -> grow[Array[i32]] -> grow[Array[Array[i32]]] -> ...
    # Every level still satisfies Any, so analysis accepts it; only
    # monomorphization would loop. The occurs-check must make this a hard error.
    let (r, dir) = monomorphizeSingle(Prelude & """
public module M:
  public func grow(x: Any): u32!
    box = Array[Any] { size: u32 1 }
    filled = try Array.set(box, u32 0, x)
    _ = try M.grow(filled)
    u32!.Ok { value: u32 0 }

  public func start(): i32
    match M.grow(i32 0):
      case _:
        i32 0
""")
    cleanupDir(dir)
    check r.isErr

suite "monomorphize — extern instances":

  test "an extern call produces an extern instance":
    let (r, dir) = monomorphizeAppSingle(Prelude & """
public module M:
  @extern("m_compute")
  func compute(): i32

  public func start(): i32
    M.compute()
""")
    cleanupDir(dir)
    check r.isOk
    # start (a user copy) plus compute (an extern copy) -> exactly one extern.
    var externInstances = 0
    for instance in r.get.instances.values:
      if instance.kind == mikExtern:
        externInstances += 1
    check externInstances == 1

suite "monomorphize — value ids":

  test "match arms and the match itself get distinct value ids":
    let (r, dir) = monomorphizeAppSingle(Prelude & """
public module M:
  public func start(): i32
    x = i32 0
    y = match x:
      case 0:
        i32 1
      case _:
        match x:
          case 1:
            i32 2
          case _:
            i32 3
    y
""")
    cleanupDir(dir)
    check r.isOk
    # Every value in one copy (params, body nodes, nested arm bodies, and
    # each match's own result) must have its own id.
    for instance in r.get.instances.values:
      let ids = instance.valueIds
      check ids.deduplicate.len == ids.len

suite "monomorphize — open TODOs":

  # EXPECTED: calling the generated `byte_size` directly monomorphizes; its
  # copy is a generated instance whose body codegen emits.
  # TODO(generated-functions): today the generated arm asserts, so this test
  # asserts the crash. Flip it when the TODO is fixed.
  test "a direct byte_size call crashes the monomorphizer":
    let (app, dir) = analyzeAppSingle(Prelude & """
public module M:
  public func start(): i32
    n = u32.byte_size()
    i32 0
""")
    check app.isOk
    var crash = ""
    try:
      discard monomorphize(app.get)
    except AssertionDefect:
      crash = getCurrentExceptionMsg()
    cleanupDir(dir)
    check errorContains(crash, "generated functions are not reachable")

  # EXPECTED: calling `byte_size` through the generic `Any` monomorphizes to
  # the concrete type's generated `byte_size` (here `i32`'s).
  # TODO(generated-functions): today that call reaches the same assert, so
  # this test asserts the crash. Flip it when the TODO is fixed.
  test "a byte_size call through Any crashes the monomorphizer":
    let (app, dir) = analyzeAppSingle(Prelude & """
public module Box:
  struct:
    item: Any

  public func size(b: Box[Any]): u64
    Any.byte_size()

public module M:
  public func start(): i32
    b = Box[i32] { item: i32 0 }
    n = Box.size(b)
    i32 0
""")
    check app.isOk
    var crash = ""
    try:
      discard monomorphize(app.get)
    except AssertionDefect:
      crash = getCurrentExceptionMsg()
    cleanupDir(dir)
    check errorContains(crash, "generated functions are not reachable")
