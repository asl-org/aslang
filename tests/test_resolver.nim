## Resolver tests — exercise the full pipeline (tokenize + parse +
## resolve) over crafted programs covering: shape resolution, import
## name lookup + visibility, the generic-signature rule, body-level
## name resolution (variable scope, function-call ref by (name, arity),
## case patterns), and the most common error paths.

import unittest, strutils, results

import tutils

const Base = """
public module u8:
  literal: "u8"

  @extern("u8_add")
  public func add(a: u8, b: u8): u8

public module u32:
  literal: "u32"

public module u64:
  literal: "u64"

  @extern("u64_compare")
  public func compare(a: u64, b: u64): u8

public module String:
  literal: "string"

public module Error:
  struct:
    code: u32
    message: String

public generic Any:
  func byte_size(items: u32): u64

public module Status:
  union:
    Ok { value: Any }
    Err { error: Error }

public module Array:
  requires(Any)

  struct:
    size: u32

  public func init(size: u32): Array[Any]
    Array[Any] { size: size }
"""

suite "resolver — happy paths":

  test "literal-data module resolves":
    let (r, dir) = resolveSingle("""
public module u8:
  literal: "u8"
""")
    cleanupDir(dir)
    check r.isOk

  test "struct + literal type field resolves":
    let (r, dir) = resolveFiles([
      ("entry.asl", """
import { u8 } from "./base.asl"

module Pair:
  struct:
    a: u8
    b: u8
"""),
      ("base.asl", Base)
    ])
    cleanupDir(dir)
    check r.isOk

  test "explicit requires(...) generic module resolves":
    let (r, dir) = resolveSingle(Base)
    cleanupDir(dir)
    check r.isOk

  test "function body with assignments and call chain resolves":
    let (r, dir) = resolveFiles([
      ("entry.asl", """
import { u8 } from "./base.asl"

public module Calc:
  public func go(x: u8): u8
    y = u8.add(x, x)
    z = u8.add(y, x)
    z
"""),
      ("base.asl", Base)
    ])
    cleanupDir(dir)
    check r.isOk

  test "match expression with integer + variable patterns resolves":
    let (r, dir) = resolveFiles([
      ("entry.asl", """
import { u64, u8 } from "./base.asl"

public module M:
  public func go(x: u64): u8
    _ = match u64.compare(x, x):
      case 0:
        u8 1
      case other:
        u8 0
    u8 0
"""),
      ("base.asl", Base)
    ])
    cleanupDir(dir)
    check r.isOk

  test "variant case pattern bindings flow into case body scope":
    let (r, dir) = resolveFiles([
      ("entry.asl", """
import { u8, Status, Any, Error } from "./base.asl"

public module M:
  public func go(s: Status[u8]): u8
    _ = match s:
      case Ok { value: v }:
        v
      case Err { error: e }:
        e.code
    u8 0
"""),
      ("base.asl", Base)
    ])
    cleanupDir(dir)
    check r.isOk

  test "union initializer happy path":
    let (r, dir) = resolveFiles([
      ("entry.asl", """
import { u8, Status, Any, Error } from "./base.asl"

public module M:
  public func ok_one(): Status[u8]
    Status[u8].Ok { value: u8 1 }
"""),
      ("base.asl", Base)
    ])
    cleanupDir(dir)
    check r.isOk

  test "mutation statement resolves":
    let (r, dir) = resolveSingle("""
module Pair:
  struct:
    a: u8
    b: u8

  func setA(p: Pair, v: u8): Pair
    p.a = v
    p

public module u8:
  literal: "u8"
""")
    cleanupDir(dir)
    check r.isOk

  test "module with implicit (inferred) generic field resolves":
    # Status has no `requires(Any)` but uses Any as a variant field;
    # the resolver must infer Any as a type parameter so Status[u8]
    # is well-formed at use sites.
    let (r, dir) = resolveSingle("""
public module u8:
  literal: "u8"

public module u32:
  literal: "u32"

public module String:
  literal: "string"

public module Error:
  struct:
    code: u32
    message: String

public generic Any:
  func byte_size(items: u32): u64

public module u64:
  literal: "u64"

public module Status:
  union:
    Ok { value: Any }
    Err { error: Error }

module M:
  struct:
    s: Status[u8]
""")
    cleanupDir(dir)
    check r.isOk

  test "Array[u8] argument-type resolves through explicit requires":
    let (r, dir) = resolveFiles([
      ("entry.asl", """
import { u8, u32, Array, Any } from "./base.asl"

public module M:
  public func mk(): Array[Any]
    Array.init(u32 10)
"""),
      ("base.asl", Base)
    ])
    cleanupDir(dir)
    check r.isOk

suite "resolver — name resolution errors":

  test "unknown type is reported":
    let (r, dir) = resolveSingle("""
module M:
  struct:
    x: NoSuchType
""")
    cleanupDir(dir)
    check r.isErr
    check errorContains(r.error, "NoSuchType")
    check errorContains(r.error, "does not exist in the scope")

  test "variable not in scope is reported":
    let (r, dir) = resolveFiles([
      ("entry.asl", """
import { u8 } from "./base.asl"

public module M:
  public func go(x: u8): u8
    u8.add(x, missing)
"""),
      ("base.asl", Base)
    ])
    cleanupDir(dir)
    check r.isErr
    check errorContains(r.error, "missing")
    check errorContains(r.error, "not present in scope")

  test "literal-backed type with type parameters is rejected":
    let (r, dir) = resolveFiles([
      ("entry.asl", """
import { u8 } from "./base.asl"

module M:
  struct:
    a: u8[u8]
"""),
      ("base.asl", Base)
    ])
    cleanupDir(dir)
    check r.isErr
    check errorContains(r.error, "does not require impl types")

  test "calling a non-existent function on a module is rejected":
    let (r, dir) = resolveFiles([
      ("entry.asl", """
import { u8 } from "./base.asl"

public module M:
  public func go(x: u8): u8
    u8.no_such_function(x, x)
"""),
      ("base.asl", Base)
    ])
    cleanupDir(dir)
    check r.isErr
    check errorContains(r.error, "no_such_function")

  test "calling a function with the wrong arity is rejected":
    let (r, dir) = resolveFiles([
      ("entry.asl", """
import { u8 } from "./base.asl"

public module M:
  public func go(x: u8): u8
    u8.add(x)
"""),
      ("base.asl", Base)
    ])
    cleanupDir(dir)
    check r.isErr
    check errorContains(r.error, "arity")

  test "struct initializer with wrong kwarg count is rejected":
    let (r, dir) = resolveFiles([
      ("entry.asl", """
import { u8, u32, Error, String } from "./base.asl"

public module M:
  public func mk(): Error
    Error { code: u32 0 }
"""),
      ("base.asl", Base)
    ])
    cleanupDir(dir)
    check r.isErr
    check errorContains(r.error, "expects")

suite "resolver — imports":

  test "importing a non-public type is rejected":
    # `Hidden` is non-public in other.asl. We need it to be a literal-
    # backed module so resolving other.asl itself succeeds (no body
    # references to imported names that would error first).
    let (r, dir) = resolveFiles([
      ("entry.asl", """
import { Hidden } from "./other.asl"

module M:
  struct:
    h: Hidden
"""),
      ("other.asl", """
module Hidden:
  literal: "u8"
""")
    ])
    cleanupDir(dir)
    check r.isErr
    check errorContains(r.error, "non-public")

  test "importing a name that does not exist is rejected":
    let (r, dir) = resolveFiles([
      ("entry.asl", """
import { NotThere } from "./other.asl"

module M:
  struct:
    h: NotThere
"""),
      ("other.asl", """
public module Other:
  func go(): u8
    u8 0
""")
    ])
    cleanupDir(dir)
    check r.isErr

  test "import alias resolves at use sites":
    let (r, dir) = resolveFiles([
      ("entry.asl", """
import { u8 as Byte } from "./base.asl"

module M:
  struct:
    b: Byte
"""),
      ("base.asl", Base)
    ])
    cleanupDir(dir)
    check r.isOk

suite "resolver — generic signature rule":

  test "self-reference inside generic signature is allowed":
    # All types referenced from inside the generic must be locally
    # defined (the generic-context resolveArgumentType still has a
    # tkImported stub today). We define u8 in the same file.
    let (r, dir) = resolveSingle("""
public module u8:
  literal: "u8"

generic Eq:
  func eq(a: Eq, b: Eq): u8
""")
    cleanupDir(dir)
    check r.isOk

  test "module reference inside a generic signature is allowed":
    let (r, dir) = resolveSingle("""
public module u32:
  literal: "u32"

generic Sized:
  func size(s: Sized): u32
""")
    cleanupDir(dir)
    check r.isOk

  test "another generic referenced inside a generic block is rejected":
    let (r, dir) = resolveSingle("""
public module u8:
  literal: "u8"

generic Other:
  func id(x: Other): Other

generic Eq:
  func eq(a: Eq, b: Other): u8
""")
    cleanupDir(dir)
    check r.isErr
    check errorContains(r.error, "generic")
    check errorContains(r.error, "can not be used")

suite "resolver — error message formatting":

  test "error message includes the file path":
    let (r, dir) = resolveSingle("""
module M:
  struct:
    x: NoSuchType
""")
    cleanupDir(dir)
    check r.isErr
    # resolveFiles writes to a temp dir; the path should be embedded.
    check errorContains(r.error, ".asl")

  test "error message includes line:col":
    let (r, dir) = resolveSingle("""
module M:
  struct:
    x: NoSuchType
""")
    cleanupDir(dir)
    check r.isErr
    # Coarse check: contains a digit:digit pair somewhere.
    var hasLineCol = false
    for i in 0..<r.error.len - 2:
      if r.error[i].isDigit and r.error[i+1] == ':' and r.error[i+2].isDigit:
        hasLineCol = true
        break
    check hasLineCol

suite "resolver — requires-block constraints":
  # Minimal prelude — a literal module + a one-func generic that can be
  # referenced from a `requires(...)` block.
  const RequiresPrelude = """
public module u8:
  literal: "u8"

public generic K:
  func foo(): u8

"""

  test "requires is rejected on user-defined modules (only Array / Map allowed)":
    let (r, dir) = resolveSingle(RequiresPrelude & """
public module MyModule:
  requires(K)
  struct:
    x: u8
""")
    cleanupDir(dir)
    check r.isErr
    check errorContains(r.error, "reserved for `Array` and `Map`")

  test "duplicate generic in requires(...) is rejected":
    let (r, dir) = resolveSingle(RequiresPrelude & """
public module Array:
  requires(K, K)
  struct:
    x: u8
""")
    cleanupDir(dir)
    check r.isErr
    check errorContains(r.error, "duplicate generic")

  test "requires without a data block is rejected":
    let (r, dir) = resolveSingle(RequiresPrelude & """
public module Array:
  requires(K)

  public func init(): u8
    u8 0
""")
    cleanupDir(dir)
    check r.isErr
    check errorContains(r.error, "has no data block")

  test "requires with a union data block is rejected":
    let (r, dir) = resolveSingle(RequiresPrelude & """
public module Array:
  requires(K)
  union:
    A
    B
""")
    cleanupDir(dir)
    check r.isErr
    check errorContains(r.error, "data block is not a struct")

  test "phantom struct cannot have generic field (post-resolution)":
    let (r, dir) = resolveSingle(RequiresPrelude & """
public module Array:
  requires(K)
  struct:
    x: K
""")
    cleanupDir(dir)
    check r.isErr
    check errorContains(r.error, "phantom struct cannot have generic fields")
