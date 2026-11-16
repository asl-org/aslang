## Tests for the grammar layer (single-file `parse`).
##
## The grammar covers identifier rules, literals, types, functions,
## modules, generics, imports, decorators, struct/union/literal data
## blocks, match expressions, and mutations. Tests exercise positive
## paths plus the more interesting parse failures.

import unittest, results, strutils

import parser/main as parser
import analyzer/main as analyzer
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
    # extern functions parse in both .asl and .aslr files; this
    # fixture is written as .aslr.
    let r = parseStrAslr("""
public module u8:
  literal: "uint8"

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

  test "variant definition with empty braces parses":
    # `Timeout { }` — zero-field variant using the explicit-empty
    # form. Braces are required on variant definitions so the shape
    # mirrors the case-pattern side (`case Timeout { }:`).
    let r = parseStr("""
module Signal:
  union:
    Timeout { }
    Value { data: u8 }
""")
    check r.isOk

  test "bare-identifier variant definition is rejected":
    # `Timeout` (no braces) would be visually ambiguous with a
    # variable-binding case pattern. Rejecting bare identifiers on
    # the definition side removes that ambiguity: every variant
    # declaration carries braces, so `case Timeout:` in a match
    # unambiguously means "bind the subject to a variable named
    # Timeout", not "match the Timeout variant".
    let r = parseStr("""
module Signal:
  union:
    Timeout
    Value { data: u8 }
""")
    check r.isErr

  test "module with struct(...) header":
    let r = parseStr("""
public generic Any:
  func byte_size(items: u32): u64

module Box:
  struct(Any):
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
  struct(Any):
    payload: Any

  func get(arr: Array[Any], idx: u32): Status[Any]
    Status.Ok { value: arr.payload }
""")
    check r.isOk

  test "extern function":
    # extern functions are legal in both .asl and .aslr files; this
    # fixture is written as .aslr.
    let r = parseStrAslr("""
public module u8:
  literal: "uint8"

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

  # EXPECTED: the parse fails with `newImport`'s duplicate-name error,
  # pointing at the second `Foo`.
  # TODO(parser-errors): today the parser's `any` backtracking swallows
  # that message, so the parse reports the generic "expected 'module'".
  # This test asserts that. Flip it when the TODO is fixed.
  test "duplicate import names within a single statement are rejected":
    let r = parseStr("""
import { Foo, Foo } from "./bar.asl"

module M:
  func go(): u8
    u8 0
""")
    check r.isErr
    check errorContains(r.error, "expected 'module'")

  # EXPECTED: the parse fails with `newImport`'s alias-collision error,
  # pointing at the second `B`.
  # TODO(parser-errors): today the message is swallowed the same way, so
  # the parse reports "expected 'module'". This test asserts that. Flip it
  # when the TODO is fixed.
  test "duplicate import bindings (alias collision) are rejected":
    let r = parseStr("""
import { Foo as B, Bar as B } from "./bar.asl"

module M:
  func go(): u8
    u8 0
""")
    check r.isErr
    check errorContains(r.error, "expected 'module'")

  test "shorthand import parses":
    # `import "path"` parses to an ikShorthand Import — the names
    # list is materialized later by the resolver once the target
    # file's types are resolved.
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

  test "explicit union pattern field requires a colon":
    # `value v` (no colon) is not a valid explicit `name: binding` field;
    # only `value: v` (explicit) or bare `value` (shorthand) are.
    let r = parseStr("""
public module Status:
  union:
    Ok { value: u8 }

module M:
  func go(s: Status[u8]): u8
    _ = match s:
      case Ok { value v }:
        v
    u8 0
""")
    check r.isErr

  test "case pattern with empty braces parses":
    # Zero-field variants are matched with `case Timeout { }:` —
    # the same braces-required rule that governs variant definitions
    # governs case patterns. `case Timeout:` (no braces) parses too
    # but as a variable binding, not a variant match (see
    # `casePatternSpec` — the `variable` arm is the tail alternative).
    let r = parseStr("""
public module Signal:
  union:
    Timeout { }
    Value { data: u8 }

module M:
  func go(s: Signal): u8
    _ = match s:
      case Timeout { }:
        u8 0
      case Value { data: d }:
        d
    u8 0
""")
    check r.isOk

  test "variant match with a trailing variable (catch-all) pattern is allowed":
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
      case _:
        u8 0
    u8 0
""")
    check r.isOk

  # newMatchExpression's pattern validations (uniqueness, no-mixing,
  # variable-last) return non-fatal ParserErrors, so when a match block
  # fails one the parser backtracks and the surface error is a generic
  # downstream one rather than the validation message (same masking caveat
  # as the import-path tests in test_loader.nim). These tests therefore
  # assert only that the parse fails — the constructor invariant is what we
  # care about. Making these errors fatal (so the message surfaces) belongs
  # to the planned parsing-spec cleanup.
  test "duplicate integer case value is rejected":
    let r = parseStr("""
module M:
  func go(x: u8): u8
    _ = match x:
      case 0:
        u8 1
      case 0:
        u8 2
    u8 0
""")
    check r.isErr

  test "duplicate variant case is rejected":
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
      case Ok { value: w }:
        w
    u8 0
""")
    check r.isErr

  test "mixing integer and variant patterns is rejected":
    let r = parseStr("""
public module Status:
  union:
    Ok { value: u8 }
    Err { error: u8 }

module M:
  func go(s: Status[u8]): u8
    _ = match s:
      case 0:
        u8 1
      case Ok { value: v }:
        v
    u8 0
""")
    check r.isErr

  test "a variable pattern before the last case is rejected":
    let r = parseStr("""
module M:
  func go(x: u8): u8
    _ = match x:
      case _:
        u8 0
      case 1:
        u8 2
    u8 0
""")
    check r.isErr

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
    # extern functions are legal in both .asl and .aslr files; this
    # fixture is written as .aslr.
    let r = parseStrAslr("""
public module u8:
  literal: "uint8"

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

  test "a match result reaches a call by binding it to a temp first":
    # A match is a block expression and cannot be a function-call
    # argument (arguments are InlineExpression). The idiom is to bind
    # the match to a name and pass the name — this parses.
    let r = parseStr("""
module M:
  func go(x: u8): u8
    y = match x:
      case 0:
        u8 1
      case _:
        u8 0
    u8.add(y, y)
""")
    check r.isOk

suite "grammar — setter statement":

  test "setter assigns into a getter target":
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

  test "special float literal: nan parses":
    let r = parseStr("""
module M:
  func go(): f32
    f32 nan
""")
    check r.isOk

  test "special float literal: inf parses":
    let r = parseStr("""
module M:
  func go(): f32
    f32 inf
""")
    check r.isOk

  test "special float literal: -inf parses":
    let r = parseStr("""
module M:
  func go(): f32
    f32 -inf
""")
    check r.isOk

  test "special float literal: +inf parses":
    let r = parseStr("""
module M:
  func go(): f32
    f32 +inf
""")
    check r.isOk

  test "special float literal: bare `nan` / `inf` / `-inf` parse in expression position":
    # No type prefix — the parser recognizes the special-value forms
    # inside `floatLiteralSpec` regardless of surrounding context, so
    # bare assignments and bare-statement expressions work too.
    # (Analyzer-side type resolution via Approach C is verified in
    # test_analyzer.nim.)
    let r = parseStr("""
module M:
  func go(): f32
    x = nan
    y = inf
    z = -inf
    x
""")
    check r.isOk

suite "grammar — file-kind invariants":

  test ".aslr file with an import line is rejected":
    # `aslrFileSpec` parses only modules and generics; the
    # leading `import` line doesn't match any expected token,
    # so the parse fails.
    let r = parseStrAslr("""
import { Foo } from "./bar.asl"

public module M:
  func go(): u8
    u8 0
""")
    check r.isErr

  test ".asl file with an extern function inside a module parses":
    # `.asl` files may now host `@extern` functions — the extern parses
    # like any other module function (previously only `.aslr` files
    # could declare externs).
    let r = parseStr("""
public module Sys:
  @extern("sys_call")
  public func call(): u8
""")
    check r.isOk

suite "grammar — kwarg + pattern shorthand":
  # `Struct { x }` is sugar for `Struct { x: x }` — the parser
  # synthesizes the value expression as a bare Variable of the same
  # name. Same shape for union initializers (`Status.Ok { value }`)
  # and for union-pattern field bindings (`case Ok { value }` = `case
  # Ok { value: value }`). Downstream (resolver / analyzer) sees the
  # explicit form as if the user had typed it out.

  test "struct initializer with kwarg shorthand parses":
    let r = parseStr("""
module Pair:
  struct:
    a: u8
    b: u8

  func mk(): Pair
    a = u8 1
    b = u8 2
    Pair { a, b }
""")
    check r.isOk

  test "struct initializer mixing shorthand and explicit kwargs parses":
    let r = parseStr("""
module Pair:
  struct:
    a: u8
    b: u8

  func mk(): Pair
    a = u8 1
    Pair { a, b: u8 2 }
""")
    check r.isOk

  test "union initializer with kwarg shorthand parses":
    let r = parseStr("""
public module Status:
  union:
    Ok { value: u8 }
    Err { error: u8 }

module M:
  func mk(): Status[u8]
    value = u8 42
    Status.Ok { value }
""")
    check r.isOk

  test "union pattern with field-binding shorthand parses":
    let r = parseStr("""
public module Status:
  union:
    Ok { value: u8 }
    Err { error: u8 }

module M:
  func go(s: Status[u8]): u8
    _ = match s:
      case Ok { value }:
        value
      case Err { error }:
        error
    u8 0
""")
    check r.isOk

  test "union pattern mixing shorthand and explicit field bindings parses":
    let r = parseStr("""
public module Pair:
  union:
    Both { a: u8, b: u8 }

module M:
  func go(p: Pair): u8
    _ = match p:
      case Both { a, b: x }:
        a
    u8 0
""")
    check r.isOk

suite "grammar — argument type shorthand":
  # `T!` is sugar for `Status[T, Error]` (`T!E` for `Status[T, E]`).
  # Parsed at the argument-type spec so every argument-type position —
  # function args, return types, kwarg field types, initializer type
  # prefixes — picks it up uniformly. Nesting binds tight:
  # `Array[u32!]` = `Array[Status[u32, Error]]`; `Array[u32]!` =
  # `Status[Array[u32], Error]`; `Status[u32]!` =
  # `Status[Status[u32], Error]`. Downstream sees a plain `Status[...]`
  # ArgumentType — no separate variant.

  test "banged return type parses":
    let r = parseStr("""
public module Status:
  union:
    Ok { value: u8 }
    Err { error: u8 }

module M:
  func go(): u8!
    u8 0
""")
    check r.isOk

  test "banged argument type parses":
    let r = parseStr("""
public module Status:
  union:
    Ok { value: u8 }
    Err { error: u8 }

module M:
  func go(x: u8!): u8
    u8 0
""")
    check r.isOk

  test "banged struct field type parses":
    let r = parseStr("""
public module Status:
  union:
    Ok { value: u8 }
    Err { error: u8 }

module Holder:
  struct:
    slot: u8!
""")
    check r.isOk

  test "bang after impls parses (Array[u32]!)":
    # `Array[u32]!` — `!` binds to the fully-parsed `Array[u32]`,
    # producing `Status[Array[u32], Error]`.
    let r = parseStr("""
public module Status:
  union:
    Ok { value: u8 }
    Err { error: u8 }

public generic Any:
  func byte_size(x: u32): u32

public module Array:
  struct(Any):
    size: u32

module M:
  func go(): Array[u32]!
    Array[u32] { size: u32 0 }
""")
    check r.isOk

  test "bang inside impls parses (Array[u32!])":
    # `Array[u32!]` — inner `!` binds to `u32`, producing
    # `Array[Status[u32, Error]]`.
    let r = parseStr("""
public module Status:
  union:
    Ok { value: u8 }
    Err { error: u8 }

public generic Any:
  func byte_size(x: u32): u32

public module Array:
  struct(Any):
    size: u32

module M:
  func go(x: Array[u32!]): u32
    u32 0
""")
    check r.isOk

  test "sugar and desugared form both parse (equivalence hint)":
    # Two functions, one written with `!`, one with explicit
    # `Status[...]`. Both should parse cleanly. AST equivalence is
    # verified end-to-end in the analyzer suite.
    let r = parseStr("""
public module Status:
  union:
    Ok { value: u8 }
    Err { error: u8 }

module M:
  func with_bang(): u8!
    u8 0

  func with_status(): Status[u8]
    u8 0
""")
    check r.isOk

suite "grammar — generated functions omitted from asl output":
  # The injected `byte_size` is a `generated` function (fkGenerated).
  # The pretty-printer must omit it, so a data module round-trips
  # through `asl` without gaining a spurious `byte_size` line.

  test "a literal module's asl output omits the injected byte_size":
    let r = parseStr("""
public module u8:
  literal: "uint8"
""")
    check r.isOk
    let printed = r.get.asl(2'u32)
    check "byte_size" notin printed
    check "public module u8:" in printed
    check "literal: \"uint8\"" in printed

  test "a struct module's asl output keeps user functions but omits byte_size":
    let r = parseStr("""
public module u8:
  literal: "uint8"

public module Point:
  struct:
    x: u8
    y: u8

  public func zero(): u8
    u8 0
""")
    check r.isOk
    let printed = r.get.asl(2'u32)
    check "byte_size" notin printed
    check "public func zero(): u8" in printed
