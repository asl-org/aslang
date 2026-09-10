## Resolver tests — exercise the full pipeline (tokenize + parse +
## resolve) over crafted programs covering: shape resolution, import
## name lookup + visibility, the generic-signature rule, body-level
## name resolution (variable scope, function-call ref by (name, arity),
## case patterns), and the most common error paths.

import unittest, strutils, results

import tutils

const Base = """
public module u8:
  literal: "uint8"

  @extern("u8_add")
  public func add(a: u8, b: u8): u8

  @extern("u8_byte_size")
  public func byte_size(items: u32): u64

public module u32:
  literal: "uint32"

  @extern("u32_byte_size")
  public func byte_size(items: u32): u64

public module u64:
  literal: "uint64"

  @extern("u64_compare")
  public func compare(a: u64, b: u64): u8

  @extern("u64_byte_size")
  public func byte_size(items: u32): u64

public module String:
  literal: "string"

  @extern("string_byte_size")
  public func byte_size(items: u32): u64

public module Error:
  struct:
    code: u32
    message: String

  @extern("error_byte_size")
  public func byte_size(items: u32): u64

public generic Any:
  func byte_size(items: u32): u64

public module Status:
  union:
    Ok { value: Any }
    Err { error: Error }

public module Array:
  struct(Any):
    size: u32

  public func init(size: u32): Array[Any]
    Array[Any] { size: size }
"""

suite "resolver — happy paths":

  test "literal-data module resolves":
    let (r, dir) = resolveSingle("""
public module u8:
  literal: "uint8"

public module u64:
  literal: "uint64"
""")
    cleanupDir(dir)
    check r.isOk

  test "struct + literal type field resolves":
    let (r, dir) = resolveFiles([
      ("entry.asl", """
import { u8, u64 } from "./base.aslr"

module Pair:
  struct:
    a: u8
    b: u8
"""),
      ("base.aslr", Base)
    ])
    cleanupDir(dir)
    check r.isOk

  test "explicit struct(...) header generic module resolves":
    # Base is the runtime-interface stdlib (extern functions, no
    # imports), so it is parsed as .aslr.
    let (r, dir) = resolveSingleAslr(Base)
    cleanupDir(dir)
    check r.isOk

  test "function body with assignments and call chain resolves":
    let (r, dir) = resolveFiles([
      ("entry.asl", """
import { u8 } from "./base.aslr"

public module Calc:
  public func go(x: u8): u8
    y = u8.add(x, x)
    z = u8.add(y, x)
    z
"""),
      ("base.aslr", Base)
    ])
    cleanupDir(dir)
    check r.isOk

  test "nested function call as an argument resolves":
    # The first argument to the outer u8.add is itself a call, so this
    # drives resolveFunctionCall -> resolveInlineExpression(iekFnCall)
    # -> back into resolveFunctionCall. That arg path was split out of
    # resolveExpression when call arguments were narrowed to
    # InlineExpression, so it needs its own coverage.
    let (r, dir) = resolveFiles([
      ("entry.asl", """
import { u8 } from "./base.aslr"

public module Calc:
  public func go(x: u8): u8
    u8.add(u8.add(x, x), x)
"""),
      ("base.aslr", Base)
    ])
    cleanupDir(dir)
    check r.isOk

  test "match expression with integer + variable patterns resolves":
    let (r, dir) = resolveFiles([
      ("entry.asl", """
import { u64, u8 } from "./base.aslr"

public module M:
  public func go(x: u64): u8
    _ = match u64.compare(x, x):
      case 0:
        u8 1
      case other:
        u8 0
    u8 0
"""),
      ("base.aslr", Base)
    ])
    cleanupDir(dir)
    check r.isOk

  test "variant case pattern bindings flow into case body scope":
    let (r, dir) = resolveFiles([
      ("entry.asl", """
import { u8, Status, Any, Error } from "./base.aslr"

public module M:
  public func go(s: Status[u8]): u8
    _ = match s:
      case Ok { value: v }:
        v
      case Err { error: e }:
        e.code
    u8 0
"""),
      ("base.aslr", Base)
    ])
    cleanupDir(dir)
    check r.isOk

  test "union initializer happy path":
    let (r, dir) = resolveFiles([
      ("entry.asl", """
import { u8, Status, Any, Error } from "./base.aslr"

public module M:
  public func ok_one(): Status[u8]
    Status.Ok { value: u8 1 }
"""),
      ("base.aslr", Base)
    ])
    cleanupDir(dir)
    check r.isOk

  test "initializer field value can be a nested call":
    # The kwarg value is itself a function call, driving
    # resolveKeywordArguments -> resolveInlineExpression(iekFnCall).
    # That path was split out when initializer field values were
    # narrowed to InlineExpression, so it needs its own coverage.
    let (r, dir) = resolveFiles([
      ("entry.asl", """
import { u8, Status, Any, Error } from "./base.aslr"

public module M:
  public func ok_sum(x: u8): Status[u8]
    Status.Ok { value: u8.add(x, x) }
"""),
      ("base.aslr", Base)
    ])
    cleanupDir(dir)
    check r.isOk

  test "setter statement resolves":
    let (r, dir) = resolveSingle("""
module Pair:
  struct:
    a: u8
    b: u8

  func setA(p: Pair, v: u8): Pair
    p.a = v
    p

public module u8:
  literal: "uint8"

public module u64:
  literal: "uint64"
""")
    cleanupDir(dir)
    check r.isOk

  test "module with implicit (inferred) generic field resolves":
    # Status has no `struct(Any):` header but uses Any as a variant field;
    # the resolver must infer Any as a type parameter so Status[u8]
    # is well-formed at use sites.
    # byte_size must be public: Status[u8] is written in module M, so
    # u8 satisfies Any only through functions M can access.
    let (r, dir) = resolveSingle("""
public module u8:
  literal: "uint8"

  public func byte_size(items: u32): u64
    u64 1

public module u32:
  literal: "uint32"

public module String:
  literal: "string"

  func byte_size(items: u32): u64
    u64 1

public module Error:
  struct:
    code: u32
    message: String

  func byte_size(items: u32): u64
    u64 1

public generic Any:
  func byte_size(items: u32): u64

public module u64:
  literal: "uint64"

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

  test "struct fields can share the same generic type":
    # Two fields typed as the same generic `K` resolve fine — K
    # claims one position in the struct's param list, and any
    # conflict between value types at init surfaces via the
    # analyzer's AnalyzedImplMap merge, not here.
    let (r, dir) = resolveSingle("""
public module u8:
  literal: "uint8"

public module u64:
  literal: "uint64"

public generic K:
  func foo(): u8

public module Pair:
  struct:
    first: K
    second: K
""")
    cleanupDir(dir)
    check r.isOk

  test "repeated generic fields claim one require slot at use sites":
    # first/second share K, so Pair takes ONE impl — the parser-level
    # inferGenerics dedups first-seen, matching the resolved side
    # (ResolvedStructDef.generics).
    let (r, dir) = resolveSingle("""
public module u8:
  literal: "uint8"

public module u64:
  literal: "uint64"

  public func foo(): u8
    u8 0

public generic K:
  func foo(): u8

public module Pair:
  struct:
    first: K
    second: K

module M:
  struct:
    p: Pair[u8]
""")
    cleanupDir(dir)
    check r.isOk

  test "struct with two distinct generics in fields resolves":
    let (r, dir) = resolveSingle("""
public module u8:
  literal: "uint8"

public module u64:
  literal: "uint64"

public generic K:
  func foo(): u8

public generic V:
  func bar(): u8

public module Pair:
  struct:
    first: K
    second: V
""")
    cleanupDir(dir)
    check r.isOk

  test "union with the same generic across variants resolves":
    # Repeating `K` across variants is fine — K claims one position
    # in the union's param list (first-seen wins), and any conflict
    # between value types at a single construction surfaces at init
    # via the analyzer's AnalyzedImplMap merge, not here.
    let (r, dir) = resolveSingle("""
public module u8:
  literal: "uint8"

public module u64:
  literal: "uint64"

public generic K:
  func foo(): u8

public module Status:
  union:
    Ok { value: K }
    Err { error: K }
""")
    cleanupDir(dir)
    check r.isOk

  test "union with distinct generics across variants resolves":
    let (r, dir) = resolveSingle("""
public module u8:
  literal: "uint8"

public module u64:
  literal: "uint64"

public generic K:
  func foo(): u8

public generic V:
  func bar(): u8

public module Either:
  union:
    Left { x: K }
    Right { y: V }
""")
    cleanupDir(dir)
    check r.isOk

  test "Array[u8] argument-type resolves through explicit requires":
    let (r, dir) = resolveFiles([
      ("entry.asl", """
import { u8, u32, Array, Any } from "./base.aslr"

public module M:
  public func mk(): Array[Any]
    Array.init(u32 10)
"""),
      ("base.aslr", Base)
    ])
    cleanupDir(dir)
    check r.isOk

  test "imported container's contract generic need not be imported":
    # The require slot (Any) derives in base.aslr — the DEFINING
    # file — so the importer names only what it writes: Array and u8.
    let (r, dir) = resolveFiles([
      ("entry.asl", """
import { u8, Array } from "./base.aslr"

public module M:
  public func first(items: Array[u8]): u8
    u8 0
"""),
      ("base.aslr", Base)
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
import { u8 } from "./base.aslr"

public module M:
  public func go(x: u8): u8
    u8.add(x, missing)
"""),
      ("base.aslr", Base)
    ])
    cleanupDir(dir)
    check r.isErr
    check errorContains(r.error, "missing")
    check errorContains(r.error, "not present in scope")

  test "calling a non-existent function on a module is rejected":
    let (r, dir) = resolveFiles([
      ("entry.asl", """
import { u8 } from "./base.aslr"

public module M:
  public func go(x: u8): u8
    u8.no_such_function(x, x)
"""),
      ("base.aslr", Base)
    ])
    cleanupDir(dir)
    check r.isErr
    check errorContains(r.error, "no_such_function")

  test "calling a function with the wrong arity is rejected":
    let (r, dir) = resolveFiles([
      ("entry.asl", """
import { u8 } from "./base.aslr"

public module M:
  public func go(x: u8): u8
    u8.add(x)
"""),
      ("base.aslr", Base)
    ])
    cleanupDir(dir)
    check r.isErr
    check errorContains(r.error, "arity")

  test "struct initializer with wrong kwarg count is rejected":
    let (r, dir) = resolveFiles([
      ("entry.asl", """
import { u8, u32, Error, String } from "./base.aslr"

public module M:
  public func mk(): Error
    Error { code: u32 0 }
"""),
      ("base.aslr", Base)
    ])
    cleanupDir(dir)
    check r.isErr
    check errorContains(r.error, "expected")

suite "resolver — struct/union initializer field mapping":
  # Domain invariant (from grammar.md): a struct/union initializer's
  # kwargs must map one-to-one onto the struct fields / variant fields.
  # No extras, no missing, no duplicates. This suite pins the four cells
  # per initializer × per case so the invariant stays visible to future
  # readers. Some tests fail at parse time (parser AST constructors —
  # `newKeywordArgumentList` catches empty + duplicate kwargs). Extras
  # are rejected per-field by the kwarg walk's findFieldId; undersupply
  # falls to the count check ("expected N fields but M were given").
  # Either way the domain rule holds.

  test "struct initializer with extra fields is rejected":
    # `Error` has 2 fields (code, message). The extra kwarg is
    # rejected per-field — `extra` is not a field of `Error`, so
    # findFieldId fires before any count check.
    let (r, dir) = resolveFiles([
      ("entry.asl", """
import { u8, u32, Error, String } from "./base.aslr"

public module M:
  public func mk(): Error
    Error { code: u32 0, message: String "hi", extra: u8 3 }
"""),
      ("base.aslr", Base)
    ])
    cleanupDir(dir)
    check r.isErr
    check errorContains(r.error, "is not present")

  test "union initializer with exact fields resolves":
    # `Status.Ok` has 1 field (`value: Any`). Passing 1 kwarg with
    # the correct name resolves.
    let (r, dir) = resolveFiles([
      ("entry.asl", """
import { u8, Status, Any, Error } from "./base.aslr"

public module M:
  public func mk(): Status[u8]
    Status.Ok { value: u8 1 }
"""),
      ("base.aslr", Base)
    ])
    cleanupDir(dir)
    check r.isOk

  test "union initializer with extra fields is rejected":
    # `Status.Ok` has 1 field (`value: Any`). The extra kwarg is
    # rejected per-field — `extra` is not a field of `Ok`, so the
    # kwarg walk's findFieldId fires before any count check.
    let (r, dir) = resolveFiles([
      ("entry.asl", """
import { u8, Status, Any, Error } from "./base.aslr"

public module M:
  public func mk(): Status[u8]
    Status.Ok { value: u8 1, extra: u8 2 }
"""),
      ("base.aslr", Base)
    ])
    cleanupDir(dir)
    check r.isErr
    check errorContains(r.error, "does not exist")

  test "union initializer with missing fields is rejected":
    # `Status.Ok` has 1 field. Passing 0 kwargs (`{}`) must fail.
    # Today this is caught at parse time by `newKeywordArgumentList`
    # (empty list rejection). After allowing empty kwarg lists at
    # parse, this will be caught by the resolver's count check.
    # Either origin surfaces as isErr — no message assertion.
    let (r, dir) = resolveFiles([
      ("entry.asl", """
import { u8, Status, Any, Error } from "./base.aslr"

public module M:
  public func mk(): Status[u8]
    Status.Ok {}
"""),
      ("base.aslr", Base)
    ])
    cleanupDir(dir)
    check r.isErr

  test "union initializer with duplicate fields is rejected":
    # `newKeywordArgumentList` catches duplicate kwarg names at parse
    # time, so the failure surfaces regardless of what struct/union
    # the initializer targets.
    let (r, dir) = resolveFiles([
      ("entry.asl", """
import { u8, Status, Any, Error } from "./base.aslr"

public module M:
  public func mk(): Status[u8]
    Status.Ok { value: u8 1, value: u8 2 }
"""),
      ("base.aslr", Base)
    ])
    cleanupDir(dir)
    check r.isErr

  test "union initializer with no fields resolves against a zero-field variant":
    # A union variant declared with zero fields (parser AST accepts
    # this today — see `newVariantDef accepts an empty fields list`)
    # must be initializable with `Variant {}` (empty kwargs). The
    # domain rule is count equality: 0 fields require 0 kwargs.
    #
    # Currently FAILS at parse time because `newKeywordArgumentList`
    # rejects empty lists — a StructInitializer-side rule ("struct
    # needs ≥ 1 field") that leaked onto the shared list constructor
    # and blocks the union side too. Fixing this test requires
    # moving that check off the shared KeywordArgumentList and onto
    # each initializer: struct rejects empty; union delegates to the
    # resolver's `kwargs.len != variant.fields.len` count check,
    # which naturally handles zero for empty variants.
    let (r, dir) = resolveFiles([
      ("entry.asl", """
import { u8, u64 } from "./base.aslr"

public module Signal:
  union:
    Timeout { }
    Value { data: u8 }

public module M:
  public func timeout(): Signal
    Signal.Timeout {}
"""),
      ("base.aslr", Base)
    ])
    cleanupDir(dir)
    check r.isOk

  test "struct initializer with fully empty fields is rejected":
    # Edge of the "missing fields" case: 0 kwargs against a struct
    # with 2 fields. Since the parser now accepts `{}` (empty kwarg
    # list) the failure surfaces at the resolver's count check
    # (0 != 2), not at parse time.
    let (r, dir) = resolveFiles([
      ("entry.asl", """
import { u32, Error, String } from "./base.aslr"

public module M:
  public func mk(): Error
    Error {}
"""),
      ("base.aslr", Base)
    ])
    cleanupDir(dir)
    check r.isErr
    check errorContains(r.error, "expected")

  test "struct initializer with a wrong field name is rejected":
    # Right count but wrong name. `Error` has (code, message);
    # the initializer passes (wrong_name, message). The count check
    # passes but `findFieldId` on `wrong_name` fails.
    let (r, dir) = resolveFiles([
      ("entry.asl", """
import { u32, Error, String } from "./base.aslr"

public module M:
  public func mk(): Error
    Error { wrong_name: u32 0, message: String "hi" }
"""),
      ("base.aslr", Base)
    ])
    cleanupDir(dir)
    check r.isErr

  test "union initializer with a non-existent variant is rejected":
    # `Status` has variants Ok / Err; the initializer names a
    # variant `Absent` that isn't in the union. `union.findVariant`
    # returns err after the union has already resolved cleanly.
    let (r, dir) = resolveFiles([
      ("entry.asl", """
import { u8, Status, Any, Error } from "./base.aslr"

public module M:
  public func mk(): Status[u8]
    Status.Absent { value: u8 1 }
"""),
      ("base.aslr", Base)
    ])
    cleanupDir(dir)
    check r.isErr

  test "union initializer with wrong field name is rejected":
    # `Status.Ok` has field `value`. The initializer passes `wrong`
    # with the correct count. `variant.findFieldId` on `wrong` fails.
    let (r, dir) = resolveFiles([
      ("entry.asl", """
import { u8, Status, Any, Error } from "./base.aslr"

public module M:
  public func mk(): Status[u8]
    Status.Ok { wrong: u8 1 }
"""),
      ("base.aslr", Base)
    ])
    cleanupDir(dir)
    check r.isErr

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
  literal: "uint8"

public module u64:
  literal: "uint64"
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
import { u8 as Byte, u64 } from "./base.aslr"

module M:
  struct:
    b: Byte
"""),
      ("base.aslr", Base)
    ])
    cleanupDir(dir)
    check r.isOk

  test "shorthand import brings every public type into scope":
    # `import "./base.aslr"` expands to every public defined type in
    # base.aslr (u8, u32, u64, String, Error, Any, Status, Array) under
    # each type's original name. We exercise this by referencing one
    # of the imported names (u8) without an explicit binding.
    let (r, dir) = resolveFiles([
      ("entry.asl", """
import "./base.aslr"

module M:
  struct:
    b: u8
"""),
      ("base.aslr", Base)
    ])
    cleanupDir(dir)
    check r.isOk

  test "shorthand import skips non-public types":
    # `Hidden` is non-public in other.asl; the shorthand only brings
    # in public types, so referencing Hidden in the importing file
    # must fail at name lookup (not at non-public import).
    let (r, dir) = resolveFiles([
      ("entry.asl", """
import "./other.asl"

module M:
  struct:
    h: Hidden
"""),
      ("other.asl", """
public module u8:
  literal: "uint8"

module Hidden:
  literal: "uint8"

public module u64:
  literal: "uint64"
""")
    ])
    cleanupDir(dir)
    check r.isErr
    check errorContains(r.error, "Hidden")
    check errorContains(r.error, "does not exist in the scope")

  test "shorthand import vs locally-defined type rejects":
    # The shorthand brings `u8` from base.aslr; the entry file also
    # defines `u8` locally. The resolver collision check rejects.
    let (r, dir) = resolveFiles([
      ("entry.asl", """
import "./base.aslr"

module u8:
  literal: "uint8"
"""),
      ("base.aslr", Base)
    ])
    cleanupDir(dir)
    check r.isErr
    check errorContains(r.error, "duplicate type declaration")

  test "shorthand import vs explicit import of same name rejects":
    # Importing the same name explicitly and via shorthand from the
    # same file collides — the explicit `{ u8 }` and the shorthand's
    # `u8` resolve to the same binding.
    let (r, dir) = resolveFiles([
      ("entry.asl", """
import { u8 } from "./base.aslr"
import "./base.aslr"

module M:
  struct:
    b: u8
"""),
      ("base.aslr", Base)
    ])
    cleanupDir(dir)
    check r.isErr
    check errorContains(r.error, "duplicate type declaration")

  test "two shorthand imports with overlapping public sets reject":
    # Two files with overlapping public names imported via shorthand
    # from one entry — the overlapping name (u8) collides.
    let (r, dir) = resolveFiles([
      ("entry.asl", """
import "./a.asl"
import "./b.asl"

module M:
  struct:
    x: u8
"""),
      ("a.asl", """
public module u8:
  literal: "uint8"

public module u64:
  literal: "uint64"
"""),
      ("b.asl", """
public module u8:
  literal: "uint8"

public module u64:
  literal: "uint64"
""")
    ])
    cleanupDir(dir)
    check r.isErr
    check errorContains(r.error, "duplicate type declaration")

suite "resolver — generic signature rule":

  test "self-reference inside generic signature is allowed":
    # All types referenced from inside the generic must be locally
    # defined. We define u8 in the same file.
    let (r, dir) = resolveSingle("""
public module u8:
  literal: "uint8"

public module u64:
  literal: "uint64"

generic Eq:
  func eq(a: Eq, b: Eq): u8
""")
    cleanupDir(dir)
    check r.isOk

  test "module reference inside a generic signature is allowed":
    let (r, dir) = resolveSingle("""
public module u32:
  literal: "uint32"

public module u64:
  literal: "uint64"

generic Sized:
  func size(s: Sized): u32
""")
    cleanupDir(dir)
    check r.isOk

  test "another generic referenced inside a generic block is rejected":
    let (r, dir) = resolveSingle("""
public module u8:
  literal: "uint8"

public module u64:
  literal: "uint64"

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

suite "resolver — struct header constraints":
  # Minimal prelude — a literal module + a one-func generic that can be
  # referenced from a `struct(...)` header.
  const StructHeaderPrelude = """
public module u8:
  literal: "uint8"

public module u64:
  literal: "uint64"

public generic K:
  func foo(): u8

"""

  test "duplicate generic in struct(...) header is rejected":
    let (r, dir) = resolveSingle(StructHeaderPrelude & """
public module Array:
  struct(K, K):
    x: u8
""")
    cleanupDir(dir)
    check r.isErr
    check errorContains(r.error, "duplicate generic")

  test "explicit struct(...) header + generic field is allowed":
    # A `struct(K)` header declares the generic parameter K; a field
    # typed by K composes with it rather than conflicting, so the two
    # may be mixed.
    let (r, dir) = resolveSingle(StructHeaderPrelude & """
public module Array:
  struct(K):
    x: K
""")
    cleanupDir(dir)
    check r.isOk

  test "a generic nested in a field's argtype is collected as a struct param":
    # `Holder.b` is typed `Box[K]` — the generic K is nested inside the
    # Box argtype. The resolver recurses into field argtypes to collect
    # it, so Holder gains K as its own parameter (top-level-only
    # collection would have missed it).
    let (r, dir) = resolveSingle(StructHeaderPrelude & """
public module Box:
  struct(K):
    x: K

public module Holder:
  struct:
    b: Box[K]
""")
    cleanupDir(dir)
    check r.isOk

suite "resolver — extern in .asl":
  # `.asl` files may host `@extern` functions (previously `.aslr`-only).

  test "an extern function in an .asl module resolves":
    let (r, dir) = resolveSingle("""
public module u8:
  literal: "uint8"

public module u64:
  literal: "uint64"

public module Sys:
  @extern("sys_read")
  public func read(): u8
""")
    cleanupDir(dir)
    check r.isOk

  test "an extern and a user function coexist in an .asl module":
    let (r, dir) = resolveSingle("""
public module u8:
  literal: "uint8"

public module u64:
  literal: "uint64"

public module Sys:
  @extern("sys_read")
  public func read(): u8

  public func zero(): u8
    u8 0
""")
    cleanupDir(dir)
    check r.isOk

suite "resolver — union param list":
  # A union's param list is the position-ordered set of distinct
  # generics seen across all variants in declaration order. Repeated
  # names keep their first position; new names take the next slot.
  # Use sites must supply exactly one impl per position.

  const UnionParamsPrelude = """
public module u8:
  literal: "uint8"

public module u32:
  literal: "uint32"

public module u64:
  literal: "uint64"

public generic Any:
  func byte_size(items: u32): u64

public generic Sample:
  func foo(): u8

public module Box:
  union:
    First { a: Any }
    Second { a: Any, b: Sample }

"""

  test "union dedups shared generic and orders by first occurrence":
    # First contributes Any at position 0; Second reuses Any (same
    # position) then contributes Sample at position 1. Box[Any, Sample]
    # is the well-formed use-site shape.
    let (r, dir) = resolveSingle(UnionParamsPrelude & """
public module Use:
  struct:
    b: Box[Any, Sample]
""")
    cleanupDir(dir)
    check r.isOk

suite "resolver — function visibility":

  test "private function satisfies a constraint inside its own module":
    # Pair[u8] is written inside module u8 itself — the context has
    # internal access, so the private compare counts.
    let (r, dir) = resolveSingle("""
public module i32:
  literal: "int32"

public module u64:
  literal: "uint64"

public generic Comparable:
  func compare(a: Comparable, b: Comparable): i32

module Pair:
  struct:
    value: Comparable

public module u8:
  literal: "uint8"

  func compare(a: u8, b: u8): i32
    i32 0

  func pack(p: Pair[u8]): u8
    p.value
""")
    cleanupDir(dir)
    check r.isOk

  test "cross-module call to a private function is rejected":
    let (r, dir) = resolveSingle("""
public module u8:
  literal: "uint8"

public module u64:
  literal: "uint64"

module A:
  func go(x: u8): u8
    x

module B:
  func run(x: u8): u8
    A.go(x)
""")
    cleanupDir(dir)
    check r.isErr
    check errorContains(r.error, "function `go` of module `A` is not public")

  test "same-module call to a private function resolves":
    let (r, dir) = resolveSingle("""
public module u8:
  literal: "uint8"

public module u64:
  literal: "uint64"

module A:
  func go(x: u8): u8
    x

  func run(x: u8): u8
    A.go(x)
""")
    cleanupDir(dir)
    check r.isOk

suite "resolver — input-signature uniqueness":

  test "two functions with identical input signatures are rejected":
    let (r, dir) = resolveSingle("""
public module u8:
  literal: "uint8"

public module u64:
  literal: "uint64"

module A:
  func go(x: u8): u8
    x

  func go(x: u8): u8
    x
""")
    cleanupDir(dir)
    check r.isErr
    check errorContains(r.error, "duplicate function `go` with the same input signature")

  test "same inputs with a different return type is still a duplicate":
    # The return type does not distinguish functions — call sites
    # could never disambiguate by arguments alone.
    let (r, dir) = resolveSingle("""
public module u8:
  literal: "uint8"

public module u32:
  literal: "uint32"

public module u64:
  literal: "uint64"

module A:
  func go(x: u8): u8
    x

  func go(x: u8): u32
    u32 0
""")
    cleanupDir(dir)
    check r.isErr
    check errorContains(r.error, "duplicate function `go` with the same input signature")

  test "duplicate funcDef inside a generic block is rejected":
    let (r, dir) = resolveSingle("""
public module u8:
  literal: "uint8"

public module u64:
  literal: "uint64"

public generic Eq:
  func eq(a: Eq, b: Eq): u8
  func eq(a: Eq, b: Eq): u8
""")
    cleanupDir(dir)
    check r.isErr
    check errorContains(r.error, "duplicate function `eq` with the same input signature")

suite "resolver — public modules require public generics":

  test "public module with an explicit-header private generic is rejected":
    let (r, dir) = resolveSingle("""
public module u32:
  literal: "uint32"

public module u64:
  literal: "uint64"

generic Any:
  func byte_size(items: u32): u32

public module Array:
  struct(Any):
    size: u32
""")
    cleanupDir(dir)
    check r.isErr
    check errorContains(r.error, "public module `Array` requires non-public generic `Any`")

  test "public module with an inferred private generic field is rejected":
    let (r, dir) = resolveSingle("""
public module u8:
  literal: "uint8"

public module u64:
  literal: "uint64"

generic K:
  func foo(): u8

public module Box:
  struct:
    value: K
""")
    cleanupDir(dir)
    check r.isErr
    check errorContains(r.error, "public module `Box` requires non-public generic `K`")

  test "private module may use a private generic":
    let (r, dir) = resolveSingle("""
public module u8:
  literal: "uint8"

public module u64:
  literal: "uint64"

generic K:
  func foo(): u8

module Box:
  struct:
    value: K
""")
    cleanupDir(dir)
    check r.isOk

  test "public module with a public generic is fine":
    let (r, dir) = resolveSingle("""
public module u8:
  literal: "uint8"

public module u64:
  literal: "uint64"

public generic K:
  func foo(): u8

public module Box:
  struct:
    value: K
""")
    cleanupDir(dir)
    check r.isOk
