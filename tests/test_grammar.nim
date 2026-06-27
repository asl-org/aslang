## Tests for the grammar layer (single-file `parse`).
##
## The grammar covers identifier rules, literals, types, functions,
## modules, generics, imports, decorators, struct/union/literal data
## blocks, match expressions, and mutations. Tests exercise positive
## paths plus the more interesting parse failures.

import unittest, results

import parser
import tutils

suite "grammar — modules":

  test "minimal module with single function":
    let r = parseStr("""
module M:
  func go(): u8
    u8 0
""")
    check r.isOk

  test "public module is accepted":
    let r = parseStr("""
public module M:
  func go(): u8
    u8 0
""")
    check r.isOk

  test "module with literal data block":
    # extern functions only parse in .aslb files (the runtime
    # interface); newAslFile rejects them otherwise.
    let r = parseStrAslb("""
public module u8:
  literal: "u8"

  @extern("u8_read")
  public func read(p: u8): u8
""")
    check r.isOk

  test "module with struct data block":
    let r = parseStr("""
module Pair:
  struct:
    a: u8
    b: u8
""")
    check r.isOk

  test "module with union data block":
    let r = parseStr("""
module Either:
  union:
    A { x: u8 }
    B { y: u8 }
""")
    check r.isOk

  test "module with requires(...) clause":
    let r = parseStr("""
public generic Any:
  func byte_size(items: u32): u64

module Box:
  requires(Any)

  struct:
    payload: Any
""")
    check r.isOk

suite "grammar — generics":

  test "generic block with single signature":
    let r = parseStr("""
generic Eq:
  func eq(a: Eq, b: Eq): u8
""")
    check r.isOk

  test "public generic":
    let r = parseStr("""
public generic Any:
  func byte_size(items: u32): u64
  func read(ptr: Pointer, offset: u64): Any
""")
    check r.isOk

suite "grammar — functions":

  test "function with multiple arguments and generic return":
    let r = parseStr("""
public module Array:
  requires(Any)

  struct:
    payload: Any

  func get(arr: Array[Any], idx: u32): Status[Any]
    Status.Ok { value: arr.payload }
""")
    check r.isOk

  test "extern function":
    # extern functions are only legal in .aslb files.
    let r = parseStrAslb("""
public module u8:
  literal: "u8"

  @extern("u8_add")
  public func add(a: u8, b: u8): u8
""")
    check r.isOk

  test "function overloading by arity is allowed":
    let r = parseStr("""
module M:
  func go(): u8
    u8 0

  func go(x: u8): u8
    x
""")
    check r.isOk

suite "grammar — imports":

  test "import without alias":
    let r = parseStr("""
import { Foo } from "./bar.asl"

module M:
  func go(): u8
    u8 0
""")
    check r.isOk

  test "import with alias":
    let r = parseStr("""
import { Foo as Bar } from "./bar.asl"

module M:
  func go(): u8
    u8 0
""")
    check r.isOk

  test "import with multiple names":
    let r = parseStr("""
import { Foo, Bar as B, Baz } from "./bar.asl"

module M:
  func go(): u8
    u8 0
""")
    check r.isOk

  test "duplicate import names within a single statement are rejected":
    # The `newImport` constructor catches this, but its specific error
    # message is currently swallowed by the parser's `any` backtracking.
    # We verify only that the parse fails.
    let r = parseStr("""
import { Foo, Foo } from "./bar.asl"

module M:
  func go(): u8
    u8 0
""")
    check r.isErr

  test "duplicate import bindings (alias collision) are rejected":
    # Same backtracking caveat as above.
    let r = parseStr("""
import { Foo as B, Bar as B } from "./bar.asl"

module M:
  func go(): u8
    u8 0
""")
    check r.isErr

  test "shorthand import parses":
    # `import "path"` parses to an ikShorthand Import — the names
    # list is materialized later by the resolver via publicTypes().
    let r = parseStr("""
import "./bar.asl"

module M:
  func go(): u8
    u8 0
""")
    check r.isOk

suite "grammar — match expressions":

  test "match with integer literal cases":
    let r = parseStr("""
module M:
  func go(x: u8): u8
    _ = match x:
      case 0:
        u8 1
      case 1:
        u8 2
      case _:
        u8 0
    u8 0
""")
    check r.isOk

  test "match with variant pattern (field bindings)":
    let r = parseStr("""
public module Status:
  union:
    Ok { value: u8 }
    Err { error: u8 }

module M:
  func go(s: Status[u8]): u8
    _ = match s:
      case Ok { value: v }:
        v
      case Err { error: e }:
        e
    u8 0
""")
    check r.isOk

suite "grammar — expressions":

  test "function call expression":
    let r = parseStr("""
module M:
  func go(): u8
    u8.add(u8 1, u8 2)
""")
    check r.isOk

  test "getter expression":
    let r = parseStr("""
module Pair:
  struct:
    a: u8
    b: u8

  func first(p: Pair): u8
    p.a
""")
    check r.isOk

  test "struct initializer expression":
    let r = parseStr("""
module Pair:
  struct:
    a: u8
    b: u8

  func mk(): Pair
    Pair { a: u8 1, b: u8 2 }
""")
    check r.isOk

  test "union initializer expression with type parameter":
    let r = parseStr("""
public module Status:
  union:
    Ok { value: u8 }

module M:
  func go(): Status[u8]
    Status.Ok { value: u8 1 }
""")
    check r.isOk

  test "primitive literal initializer with named type":
    let r = parseStr("""
module M:
  func go(): u8
    u8 42
""")
    check r.isOk

  test "signed integer literal":
    let r = parseStr("""
module M:
  func go(): i64
    i64 -1
""")
    check r.isOk

  test "float literal":
    let r = parseStr("""
module M:
  func go(): f64
    f64 3.14
""")
    check r.isOk

suite "grammar — file structure":

  test "file with neither modules nor generics is rejected":
    let r = parseStr("\n# just a comment\n")
    check r.isErr

  test "blank lines and comments between top-level items are tolerated":
    let r = parseStr("""

# top comment

module A:
  func go(): u8
    u8 0


# divider

module B:
  func go(): u8
    u8 0
""")
    check r.isOk

suite "grammar — decorators":

  test "single decorator on a module is parsed":
    let r = parseStr("""
@deprecated
module M:
  func go(): u8
    u8 0
""")
    check r.isOk

  test "decorator on an extern function":
    # extern functions are only legal in .aslb files.
    let r = parseStrAslb("""
public module u8:
  literal: "u8"

  @extern("u8_add")
  public func add(a: u8, b: u8): u8
""")
    check r.isOk

suite "grammar — match-as-expression":

  test "match assigned to a variable":
    let r = parseStr("""
module M:
  func go(x: u8): u8
    y = match x:
      case 0:
        u8 1
      case _:
        u8 0
    y
""")
    check r.isOk

suite "grammar — mutation statement":

  test "mutation assigns into a getter target":
    let r = parseStr("""
module Pair:
  struct:
    a: u8
    b: u8

  func setA(p: Pair, v: u8): Pair
    p.a = v
    p
""")
    check r.isOk

suite "grammar — nested generic types":

  test "two-parameter generic type instantiation":
    let r = parseStr("""
module M:
  struct:
    m: Map[String, User]
""")
    check r.isOk

  test "generic nested inside another generic":
    let r = parseStr("""
module M:
  struct:
    a: Array[Status[u8]]
""")
    check r.isOk

suite "grammar — float literals":

  test "float with exponent":
    let r = parseStr("""
module M:
  func go(): f64
    f64 1.5e3
""")
    check r.isOk

  test "negative float":
    let r = parseStr("""
module M:
  func go(): f64
    f64 -0.5
""")
    check r.isOk

suite "grammar — file-kind invariants":

  test ".aslb file with an import line is rejected":
    # `aslbFileSpec` parses only modules and generics; the
    # leading `import` line doesn't match any expected token,
    # so the parse fails.
    let r = parseStrAslb("""
import { Foo } from "./bar.asl"

public module M:
  func go(): u8
    u8 0
""")
    check r.isErr

  test ".asl file with extern function inside a module is rejected":
    # `newAslFile` walks every module's function list and rejects
    # any extern, with a diagnostic that points the user at .aslb
    # files as the right home for externs.
    let r = parseStr("""
public module Sys:
  @extern("sys_call")
  public func call(): u8
""")
    check r.isErr
    check errorContains(r.error, "extern functions")
    check errorContains(r.error, ".aslb")
