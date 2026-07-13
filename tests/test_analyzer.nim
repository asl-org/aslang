## Analyzer tests — exercise the full pipeline (tokenize + parse +
## resolve + analyze) over crafted programs that target analyzer-
## specific concerns: generic constraint satisfaction, end-to-end
## walk over modules / generics / data blocks, and the cross-file
## file-scope fallback that the analyzer uses when an imported name
## isn't locally defined.

import unittest, strutils, results

import tutils

# A trim Base — defines u8 / u32 / u64 / String / Any / Status /
# Array — kept small enough that each analyzer test can be diffed
# without scrolling through the resolver's larger Base block.
const Base = """
public module u8:
  literal: "u8"

  @extern("u8_byte_size")
  public func byte_size(items: u32): u64

  @extern("u8_add")
  public func add(a: u8, b: u8): u8

public module u32:
  literal: "u32"

  @extern("u32_byte_size")
  public func byte_size(items: u32): u64

public module u64:
  literal: "u64"

public module String:
  literal: "string"

public generic Any:
  func byte_size(items: u32): u64

public module Status:
  union:
    Ok { value: Any }
    Err { value: u8 }

public module Array:
  requires(Any)

  struct:
    size: u32

  public func init(size: u32): Array[Any]
    Array[Any] { size: size }
"""

suite "analyzer — happy paths":

  test "literal-data module analyzes end-to-end":
    let (r, dir) = analyzeSingle("""
public module u8:
  literal: "u8"
""")
    cleanupDir(dir)
    check r.isOk

  test "module with only a function (no data) analyzes":
    let (r, dir) = analyzeSingle("""
public module u8:
  literal: "u8"

module M:
  func go(x: u8): u8
    x
""")
    cleanupDir(dir)
    check r.isOk

  test "struct + simple field types analyze":
    let (r, dir) = analyzeFiles([
      ("entry.asl", """
import { u8, u32 } from "./base.aslr"

module Point:
  struct:
    x: u32
    y: u32
"""),
      ("base.aslr", Base)
    ])
    cleanupDir(dir)
    check r.isOk

  test "generic block by itself analyzes":
    let (r, dir) = analyzeSingle("""
public module u32:
  literal: "u32"

public module u64:
  literal: "u64"

public generic Any:
  func byte_size(items: u32): u64
""")
    cleanupDir(dir)
    check r.isOk

  test "Array[u8] argument type analyzes when u8 implements Any":
    # Verifies the analyzer's generic-constraint check: Array requires
    # Any, u8 supplies the Any funcDefs (byte_size in Base). `Any`
    # must be in scope so the analyzer can look up the required
    # generic when iterating Array's requires.
    let (r, dir) = analyzeFiles([
      ("entry.asl", """
import { Array, Any, u8, u32 } from "./base.aslr"

module N:
  struct:
    a: Array[u8]
"""),
      ("base.aslr", Base)
    ])
    cleanupDir(dir)
    check r.isOk

  test "import alias resolves to its target type":
    # Post-6c the analyzer no longer walks defined types in a separate
    # phase — file-scope entries carry ResolvedType values
    # keyed by binding, so an alias `u8 as Byte` puts `Byte` in the
    # scope and any argType named `Byte` looks it up directly. This
    # test was previously flagged as a "known limitation" that
    # errored on aliases; the 6c retirement fixes it as a side effect
    # of consolidating def-level lookup through the scope table.
    let (r, dir) = analyzeFiles([
      ("entry.asl", """
import { u8 as Byte } from "./base.aslr"

module M:
  struct:
    b: Byte
"""),
      ("base.aslr", Base)
    ])
    cleanupDir(dir)
    check r.isOk

suite "analyzer — generic constraint satisfaction":

  test "concrete impl missing a required funcDef is rejected":
    # BadImpl is a struct-backed module with no byte_size — it cannot
    # satisfy Any. Post-6c the analyzer walks argTypes lazily at
    # use-sites (initializer / function call / getter), not while
    # declaring struct fields, so an unused `a: Array[BadImpl]` field
    # would slip through. Instantiating a value at Array[BadImpl] in a
    # function body forces the constraint check to fire.
    let (r, dir) = analyzeFiles([
      ("entry.asl", """
import { Array, Any, u32 } from "./base.aslr"

public module BadImpl:
  struct:
    x: u32

module N:
  func make(size: u32): Array[BadImpl]
    Array[BadImpl] { size: size }
"""),
      ("base.aslr", Base)
    ])
    cleanupDir(dir)
    check r.isErr
    check errorContains(r.error, "BadImpl")
    check errorContains(r.error, "does not implement")
    check errorContains(r.error, "byte_size")

  test "two concrete impls both must satisfy their respective generic":
    # Single-generic case repeated twice via two struct fields. Both
    # use u32 (which implements byte_size).
    let (r, dir) = analyzeFiles([
      ("entry.asl", """
import { Array, Any, u32 } from "./base.aslr"

module N:
  struct:
    a: Array[u32]
    b: Array[u32]
"""),
      ("base.aslr", Base)
    ])
    cleanupDir(dir)
    check r.isOk

suite "analyzer — imports":

  test "module that imports + uses a generic + concrete impl works":
    let (r, dir) = analyzeFiles([
      ("entry.asl", """
import { Any, Array, u8 } from "./base.aslr"

module N:
  struct:
    a: Array[u8]
"""),
      ("base.aslr", Base)
    ])
    cleanupDir(dir)
    check r.isOk

  test "module that imports a type but doesn't use it still analyzes":
    let (r, dir) = analyzeFiles([
      ("entry.asl", """
import { u8 } from "./base.aslr"

module M:
  struct:
    a: u8
"""),
      ("base.aslr", Base)
    ])
    cleanupDir(dir)
    check r.isOk

suite "analyzer — error propagation":

  test "resolver errors propagate through analyze*":
    # Resolver fails before the analyzer gets a chance; the wrapper
    # should still report the underlying error.
    let (r, dir) = analyzeSingle("""
module M:
  struct:
    x: NoSuchType
""")
    cleanupDir(dir)
    check r.isErr
    check errorContains(r.error, "NoSuchType")

  test "analyzer error message includes the file path":
    let (r, dir) = analyzeFiles([
      ("entry.asl", """
import { Array, Any, u32 } from "./base.aslr"

public module BadImpl:
  literal: "bad"

module N:
  struct:
    a: Array[BadImpl]
"""),
      ("base.aslr", Base)
    ])
    cleanupDir(dir)
    check r.isErr
    check errorContains(r.error, ".asl")

  test "analyzer error message includes line:col":
    let (r, dir) = analyzeFiles([
      ("entry.asl", """
import { Array, Any, u32 } from "./base.aslr"

public module BadImpl:
  literal: "bad"

module N:
  struct:
    a: Array[BadImpl]
"""),
      ("base.aslr", Base)
    ])
    cleanupDir(dir)
    check r.isErr
    var hasLineCol = false
    for i in 0..<r.error.len - 2:
      if r.error[i].isDigit and r.error[i+1] == ':' and r.error[i+2].isDigit:
        hasLineCol = true
        break
    check hasLineCol

suite "analyzer — generic-context signature":

  test "generic referring to itself analyzes":
    let (r, dir) = analyzeSingle("""
public module u8:
  literal: "u8"

generic Eq:
  func eq(a: Eq, b: Eq): u8
""")
    cleanupDir(dir)
    check r.isOk

  test "generic referring to a module analyzes":
    let (r, dir) = analyzeSingle("""
public module u32:
  literal: "u32"

generic Sized:
  func size(s: Sized): u32
""")
    cleanupDir(dir)
    check r.isOk

suite "analyzer — float literals":

  test "f64 accepts an exactly-representable value":
    let (r, dir) = analyzeSingle("""
public module f64:
  literal: "f64"

public module M:
  public func go(): f64
    f64 0.5
""")
    cleanupDir(dir)
    check r.isOk

  test "f64 accepts a decimal whose denominator has a 5-factor (warning)":
    # `0.1` = 1/10 = 1/(2 * 5); after reduction the denominator has
    # a 5-factor so the value isn't exactly representable in any
    # binary float. The analyzer accepts the literal (using the
    # closest representable f64) and writes a `[WARN]` line to
    # stderr — the analyze result itself is Ok.
    let (r, dir) = analyzeSingle("""
public module f64:
  literal: "f64"

public module M:
  public func go(): f64
    f64 0.1
""")
    cleanupDir(dir)
    check r.isOk

  test "f64 accepts a power-of-two fraction":
    # `0.0625` = 1/16 = 1/2^4 — denominator is a clean power of 2,
    # mantissa fits trivially. Exactly representable.
    let (r, dir) = analyzeSingle("""
public module f64:
  literal: "f64"

public module M:
  public func go(): f64
    f64 0.0625
""")
    cleanupDir(dir)
    check r.isOk

  test "f64 accepts a negative integer-valued literal with exponent":
    # `-1.5e3` = -1500, an integer — exact.
    let (r, dir) = analyzeSingle("""
public module f64:
  literal: "f64"

public module M:
  public func go(): f64
    f64 -1.5e3
""")
    cleanupDir(dir)
    check r.isOk

  test "f64 accepts a decimal that would round into the mantissa (warning)":
    # `3.14` = 314/100 = 157/50; denominator has a 5-factor. Same
    # accept-with-warning shape as the `0.1` case.
    let (r, dir) = analyzeSingle("""
public module f64:
  literal: "f64"

public module M:
  public func go(): f64
    f64 3.14
""")
    cleanupDir(dir)
    check r.isOk

  test "f64 rejects an overflowing literal":
    let (r, dir) = analyzeSingle("""
public module f64:
  literal: "f64"

public module M:
  public func go(): f64
    f64 1.0e400
""")
    cleanupDir(dir)
    check r.isErr
    check errorContains(r.error, "64-bit float")
    check errorContains(r.error, "1.0e400")

  test "f32 accepts an exactly-representable value":
    let (r, dir) = analyzeSingle("""
public module f32:
  literal: "f32"

public module M:
  public func go(): f32
    f32 0.5
""")
    cleanupDir(dir)
    check r.isOk

  test "f32 accepts a value that loses precision when narrowed (warning)":
    # `0.1` cannot be represented exactly in either f64 or f32
    # (denominator has a 5-factor). The analyzer accepts the
    # closest f32 approximation and emits a `[WARN]` line.
    let (r, dir) = analyzeSingle("""
public module f32:
  literal: "f32"

public module M:
  public func go(): f32
    f32 0.1
""")
    cleanupDir(dir)
    check r.isOk

  test "f32 rejects an overflowing literal":
    let (r, dir) = analyzeSingle("""
public module f32:
  literal: "f32"

public module M:
  public func go(): f32
    f32 1.0e40
""")
    cleanupDir(dir)
    check r.isErr
    check errorContains(r.error, "32-bit float")

suite "analyzer — analyze-shape corner cases":

  test "file with only a self-referential generic (no modules) analyzes":
    # Exercises the `rdtkGeneric: discard` branch in analyzeFile —
    # the returned AnalyzedFile has an empty `modules` seq. The
    # generic's function signatures only reference the generic
    # itself (per the generic-signature rule), so no imports are
    # needed even though we're not writing any modules.
    let (r, dir) = analyzeSingle("""
public generic Eq:
  func eq(a: Eq, b: Eq): Eq
""")
    cleanupDir(dir)
    check r.isOk

  test "file with multiple modules analyzes each of them":
    # Every module in the file becomes an entry in analyzeFile's
    # `analyzedModules` seq. This test writes four modules — three
    # literal primitives plus a struct that consumes them — and
    # asserts the whole file analyzes end-to-end.
    let (r, dir) = analyzeSingle("""
public module u8:
  literal: "u8"

public module u32:
  literal: "u32"

public module u64:
  literal: "u64"

module Triple:
  struct:
    a: u8
    b: u32
    c: u64
""")
    cleanupDir(dir)
    check r.isOk

  test "union module with a method that returns a variant analyzes":
    # Data-block-union + methods on the same module — exercises the
    # union initializer analysis path inside a function body, which
    # is a distinct code path from the struct-init tests.
    let (r, dir) = analyzeSingle("""
public module u8:
  literal: "u8"

module Signal:
  union:
    On { level: u8 }
    Off { padding: u8 }

  func off_default(): Signal
    Signal.Off { padding: u8 0 }
""")
    cleanupDir(dir)
    check r.isOk

  test "multi-file program: importer + importee both analyze":
    # analyze walks the topo-sorted ResolvedFile list; both files
    # must analyze successfully. The importer references a public
    # module from the importee — exercises the cross-file lookup
    # path that analyzeFile performs when threading imports into
    # the local defScope.
    let (r, dir) = analyzeFiles([
      ("entry.asl", """
import { Helper, u8 } from "./helper.asl"

module Caller:
  func run(): u8
    u8 0
"""),
      ("helper.asl", """
public module u8:
  literal: "u8"

public module Helper:
  public func value(): u8
    u8 42
""")
    ])
    cleanupDir(dir)
    check r.isOk

  test "extern function in an .aslr file analyzes":
    # Extern functions have no body to walk; the analyzer wraps
    # them as `AnalyzedExternFunction` and skips return-type
    # inference. This test verifies that path via a runtime-
    # interface (.aslr) file with a public extern.
    let (r, dir) = analyzeFiles([
      ("entry.aslr", """
public module u8:
  literal: "u8"

  @extern("u8_add_u8")
  public func add(a: u8, b: u8): u8
""")
    ])
    cleanupDir(dir)
    check r.isOk

  test "file with a public function calling an imported module method analyzes":
    # Cross-module function call resolution: `Helper.value()` in
    # `entry.asl` resolves against the imported `Helper` module's
    # public `value` function. Exercises the overload-selection
    # path with a public-only filter and the funcDef return-type
    # concretization that follows.
    let (r, dir) = analyzeFiles([
      ("entry.asl", """
import { Helper, u8 } from "./helper.asl"

module Caller:
  public func run(): u8
    Helper.value()
"""),
      ("helper.asl", """
public module u8:
  literal: "u8"

public module Helper:
  public func value(): u8
    u8 42
""")
    ])
    cleanupDir(dir)
    check r.isOk

  test "case pattern referencing a non-existent variant is rejected":
    # The analyzer's `analyzeUnionCasePattern` calls
    # `union.findVariant(variantPattern.name)` — if the pattern
    # names `Absent`, which isn't a variant of Status, the lookup
    # fails and the whole analysis errors.
    let (r, dir) = analyzeFiles([
      ("entry.asl", """
import { u8, Status, Any, Error } from "./base.aslr"

module M:
  func go(s: Status[u8]): u8
    _ = match s:
      case Ok { value: v }:
        v
      case Absent { }:
        u8 0
      case Err { error: e }:
        u8 0
    u8 0
"""),
      ("base.aslr", Base)
    ])
    cleanupDir(dir)
    check r.isErr

suite "analyzer — bare literal defaulting":
  # Contextual defaulting for bare literals in expression position.
  # Rule (Approach C): the analyzer threads an `expected` type into
  # every expression analysis; when the expression is a bare literal,
  #   • `expected = some(concrete)` → adopt the concrete type (adapt).
  #   • `expected = some(generic)`  → default to `i32`/`f32`/`String`
  #     so the binding contributes to the generic-impl map.
  #   • `expected = none`           → default to `i32`/`f32`/`String`
  #     (bare-assignment / bare-statement case).
  # Defaults must be in scope; every test fixture defines them
  # inline (the real compiler relies on `@std` auto-injection).

  test "bare integer literal in assignment defaults to i32":
    # `x = 10` has no expected context; x picks up i32 by default.
    # Downstream `i32.add(x, x)` then matches with x as i32.
    # (`add` body just returns `a` — enough to type-check.)
    let (r, dir) = analyzeSingle("""
public module i32:
  literal: "i32"

  public func add(a: i32, b: i32): i32
    a

public module M:
  public func go(): i32
    x = 10
    i32.add(x, x)
""")
    cleanupDir(dir)
    check r.isOk

  test "bare float literal in assignment defaults to f32":
    let (r, dir) = analyzeSingle("""
public module f32:
  literal: "f32"

  public func add(a: f32, b: f32): f32
    a

public module M:
  public func go(): f32
    y = 1.0
    f32.add(y, y)
""")
    cleanupDir(dir)
    check r.isOk

  test "bare string literal in assignment defaults to String":
    let (r, dir) = analyzeSingle("""
public module u32:
  literal: "u32"

public module String:
  literal: "string"

  public func length(s: String): u32
    u32 0

public module M:
  public func go(): u32
    z = "data"
    String.length(z)
""")
    cleanupDir(dir)
    check r.isOk

  test "bare integer literal adapts to concrete u8 function arg (regression guard)":
    # This is the case Approach C must NOT regress. `u8.add(10, 20)`
    # today walks the arg-list bare-literal branch and succeeds; with
    # Approach C the same call has to succeed via the concrete-adopt
    # path (expected = some(u8)) — i.e. no forced i32 default.
    let (r, dir) = analyzeSingle("""
public module u8:
  literal: "u8"

  public func add(a: u8, b: u8): u8
    a

public module M:
  public func go(): u8
    u8.add(10, 20)
""")
    cleanupDir(dir)
    check r.isOk

suite "analyzer — kwarg + pattern shorthand end-to-end":
  # Sugar at the parser layer: `Struct { x }` == `Struct { x: x }`;
  # `case Ok { value }` == `case Ok { value: value }`. Downstream sees
  # the explicit form, so a program using shorthand must analyze
  # cleanly for the same reasons the explicit form does.

  test "struct initializer kwarg shorthand analyzes":
    let (r, dir) = analyzeSingle("""
public module u8:
  literal: "u8"

public module Pair:
  struct:
    a: u8
    b: u8

  public func mk(): Pair
    a = u8 1
    b = u8 2
    Pair { a, b }
""")
    cleanupDir(dir)
    check r.isOk

  test "union initializer kwarg shorthand analyzes":
    let (r, dir) = analyzeSingle("""
public module u8:
  literal: "u8"

public module Status:
  union:
    Ok { value: u8 }
    Err { error: u8 }

module M:
  public func mk(): Status
    value = u8 42
    Status.Ok { value }
""")
    cleanupDir(dir)
    check r.isOk

  test "union pattern field-binding shorthand analyzes":
    let (r, dir) = analyzeSingle("""
public module u8:
  literal: "u8"

public module Status:
  union:
    Ok { value: u8 }
    Err { error: u8 }

module M:
  public func extract(s: Status): u8
    _ = match s:
      case Ok { value }:
        value
      case Err { error }:
        error
    u8 0
""")
    cleanupDir(dir)
    check r.isOk

suite "analyzer — argument type shorthand end-to-end":
  # `T!` is sugar for `Status[T]`. Verified by running programs that
  # would fail if the sugar didn't desugar to `Status[...]` — e.g.,
  # returning a `Status.Ok { value }` from a `func go(): u8!` signature.
  # Uses the parametric-Status shape from `Base` (Ok has `value: Any`,
  # Err has `value: u8`); the `!` sugar targets Base's Status directly.

  test "banged return type analyzes (u8! == Status[u8])":
    let (r, dir) = analyzeFiles([
      ("entry.asl", """
import { u8, Status, Any } from "./base.aslr"

module M:
  public func go(): u8!
    Status.Ok { value: u8 42 }
"""),
      ("base.aslr", Base)
    ])
    cleanupDir(dir)
    check r.isOk

  test "banged argument type analyzes":
    # `u8!` as an argument type. If `!` didn't desugar to `Status[u8]`
    # the analyzer would fail to resolve the arg type; the fact that
    # the function body compiles proves the sugar produced a valid
    # ArgumentType downstream.
    let (r, dir) = analyzeFiles([
      ("entry.asl", """
import { u8, Status, Any } from "./base.aslr"

module M:
  public func consume(s: u8!): u8
    u8 0
"""),
      ("base.aslr", Base)
    ])
    cleanupDir(dir)
    check r.isOk

  test "banged and explicit forms compose cleanly":
    # A function returning `u8!` and another returning `Status[u8]` —
    # if `!` truly desugars to `Status[u8]`, both signatures produce the
    # same AnalyzedArgumentType and can be used interchangeably.
    let (r, dir) = analyzeFiles([
      ("entry.asl", """
import { u8, Status, Any } from "./base.aslr"

module M:
  public func with_bang(): u8!
    Status.Ok { value: u8 1 }

  public func with_explicit(): Status[u8]
    Status.Ok { value: u8 2 }
"""),
      ("base.aslr", Base)
    ])
    cleanupDir(dir)
    check r.isOk
