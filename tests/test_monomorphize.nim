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
  func byte_size(items: u32): u64

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
