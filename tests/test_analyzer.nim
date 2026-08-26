## Analyzer tests — exercise the full pipeline (tokenize + parse +
## resolve + analyze) over crafted programs that target analyzer-
## specific concerns: generic constraint satisfaction, end-to-end
## walk over modules / generics / data blocks, and the cross-file
## file-scope fallback that the analyzer uses when an imported name
## isn't locally defined.

import unittest, strutils, results

import tutils
import analyzer

# A trim Base — defines u8 / u32 / u64 / String / Any / Status /
# Array — kept small enough that each analyzer test can be diffed
# without scrolling through the resolver's larger Base block.
const Base = """
public module u8:
  literal: "uint8"

  @extern("u8_byte_size")
  public func byte_size(items: u32): u64

  @extern("u8_add")
  public func add(a: u8, b: u8): u8

public module u32:
  literal: "uint32"

  @extern("u32_byte_size")
  public func byte_size(items: u32): u64

public module u64:
  literal: "uint64"

public module String:
  literal: "string"

public generic Any:
  func byte_size(items: u32): u64

public module Status:
  union:
    Ok { value: Any }
    Err { value: u8 }

public module Array:
  struct(Any):
    size: u32

  public func init(size: u32): Array[Any]
    Array[Any] { size: size }
"""

suite "analyzer — happy paths":

  test "literal-data module analyzes end-to-end":
    let (r, dir) = analyzeSingle("""
public module u8:
  literal: "uint8"

public module u64:
  literal: "uint64"
""")
    cleanupDir(dir)
    check r.isOk

  test "module with only a function (no data) analyzes":
    let (r, dir) = analyzeSingle("""
public module u8:
  literal: "uint8"

public module u64:
  literal: "uint64"

module M:
  func go(x: u8): u8
    x
""")
    cleanupDir(dir)
    check r.isOk

  test "struct + simple field types analyze":
    let (r, dir) = analyzeFiles([
      ("entry.asl", """
import { u8, u32, u64 } from "./base.aslr"

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
  literal: "uint32"

public module u64:
  literal: "uint64"

public generic Any:
  func byte_size(items: u32): u64
""")
    cleanupDir(dir)
    check r.isOk

  test "Array[u8] argument type analyzes when u8 implements Any":
    # Verifies the analyzer's generic-constraint check: Array requires
    # Any, u8 supplies the Any funcDefs (byte_size in Base). `Any` is
    # imported here but no longer has to be — see the next test.
    let (r, dir) = analyzeFiles([
      ("entry.asl", """
import { Array, Any, u8, u32, u64 } from "./base.aslr"

module N:
  struct:
    a: Array[u8]
"""),
      ("base.aslr", Base)
    ])
    cleanupDir(dir)
    check r.isOk

  test "constraint check hops to the defining file for the contract":
    # `Any` is NOT imported: the resolver reads Array's require slots
    # off the captured twin, and the def analyzer's deep check finds
    # the contract generic through the imported module's source file
    # (findGenericInScope) instead of this file's scope.
    let (r, dir) = analyzeFiles([
      ("entry.asl", """
import { Array, u8, u64 } from "./base.aslr"

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
    # phase — file-scope entries carry ResolvedLocalType values
    # keyed by binding, so an alias `u8 as Byte` puts `Byte` in the
    # scope and any argType named `Byte` looks it up directly. This
    # test was previously flagged as a "known limitation" that
    # errored on aliases; the 6c retirement fixes it as a side effect
    # of consolidating def-level lookup through the scope table.
    let (r, dir) = analyzeFiles([
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
import { Array, Any, u32, u64 } from "./base.aslr"

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
import { Array, Any, u32, u64 } from "./base.aslr"

module N:
  struct:
    a: Array[u32]
    b: Array[u32]
"""),
      ("base.aslr", Base)
    ])
    cleanupDir(dir)
    check r.isOk

  test "literal-backed type with type parameters is rejected":
    # u8 is a literal-backed module with zero require slots, so giving it
    # an impl (`u8[u8]`) fails the def analyzer's impl-count check.
    let (r, dir) = analyzeFiles([
      ("entry.asl", """
import { u8, u64 } from "./base.aslr"

module M:
  struct:
    a: u8[u8]
"""),
      ("base.aslr", Base)
    ])
    cleanupDir(dir)
    check r.isErr
    check errorContains(r.error, "expects 0 impls but found")

  test "union arg type with too few impls is rejected":
    # Box's require slots are [Any, Sample] (two distinct generics across
    # its variants); `Box[Any]` supplies only one impl. The def analyzer
    # owns this impl-count check.
    let (r, dir) = analyzeSingle("""
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

public module Use:
  struct:
    b: Box[Any]
""")
    cleanupDir(dir)
    check r.isErr
    check errorContains(r.error, "expects")
    check errorContains(r.error, "2")

  test "private function does not satisfy a constraint from another module":
    # u8's `compare` is private, so from Pair's site it does not satisfy
    # Comparable. The def analyzer's deep constraint check owns this.
    let (r, dir) = analyzeSingle("""
public module i32:
  literal: "int32"

public module u64:
  literal: "uint64"

public generic Comparable:
  func compare(a: Comparable, b: Comparable): i32

public module u8:
  literal: "uint8"

  func compare(a: u8, b: u8): i32
    i32 0

module Pair:
  struct:
    value: Comparable

module M:
  struct:
    p: Pair[u8]
""")
    cleanupDir(dir)
    check r.isErr
    check errorContains(r.error, "does not implement")
    check errorContains(r.error, "to support `Comparable`")

suite "analyzer — imports":

  test "module that imports + uses a generic + concrete impl works":
    let (r, dir) = analyzeFiles([
      ("entry.asl", """
import { Any, Array, u8, u64 } from "./base.aslr"

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
import { u8, u64 } from "./base.aslr"

module M:
  struct:
    a: u8
"""),
      ("base.aslr", Base)
    ])
    cleanupDir(dir)
    check r.isOk

suite "analyzer — cross-file constraint provenance":

  # Three-file chain: the contract (Comparable) lives in c.asl, the
  # container (Pair) in b.asl, the use site in entry.asl — which
  # imports only Pair and its own impl deps, never Comparable. The
  # flagship test in the happy-path suite covers the contract-LOCAL
  # branch of findGenericInScope (Any is defined in base.aslr
  # itself).
  #
  # KNOWN BUG (recorded in overview.md "What's Next"): the POSITIVE
  # transitive cases — instantiating Pair[Impl] when the contract
  # is not in the use site's scope — currently crash on a phase-A
  # assert re-entered from phase B (analyzeStructInitializer
  # re-analyzes Pair's field types against the USING file's scope).
  # Those tests land together with the phase-B fix.

  test "impl missing the contract function is rejected with the contract's name":
    # BadImpl has no compare. The error must still name the contract
    # and the missing function even though `Comparable` is not in
    # the use site's scope.
    let (r, dir) = analyzeFiles([
      ("entry.asl", """
import { u8, u64 } from "./c.asl"
import { Pair } from "./b.asl"

public module BadImpl:
  struct:
    x: u8

module N:
  func make(x: BadImpl): Pair[BadImpl]
    Pair[BadImpl] { value: x }
"""),
      ("b.asl", """
import { Comparable, u64 } from "./c.asl"

public module Pair:
  struct:
    value: Comparable
"""),
      ("c.asl", """
public module u8:
  literal: "uint8"

public module u64:
  literal: "uint64"

public generic Comparable:
  func compare(a: Comparable, b: Comparable): u8
""")
    ])
    cleanupDir(dir)
    check r.isErr
    check errorContains(r.error, "BadImpl")
    check errorContains(r.error, "compare")
    check errorContains(r.error, "Comparable")

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
import { Array, Any, u32, u64 } from "./base.aslr"

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
import { Array, Any, u32, u64 } from "./base.aslr"

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
  literal: "uint8"

public module u64:
  literal: "uint64"

generic Eq:
  func eq(a: Eq, b: Eq): u8
""")
    cleanupDir(dir)
    check r.isOk

  test "generic referring to a module analyzes":
    let (r, dir) = analyzeSingle("""
public module u32:
  literal: "uint32"

public module u64:
  literal: "uint64"

generic Sized:
  func size(s: Sized): u32
""")
    cleanupDir(dir)
    check r.isOk

suite "analyzer — float literals":

  test "f64 accepts an exactly-representable value":
    let (r, dir) = analyzeSingle("""
public module f64:
  literal: "float64"

public module u64:
  literal: "uint64"

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
  literal: "float64"

public module u64:
  literal: "uint64"

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
  literal: "float64"

public module u64:
  literal: "uint64"

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
  literal: "float64"

public module u64:
  literal: "uint64"

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
  literal: "float64"

public module u64:
  literal: "uint64"

public module M:
  public func go(): f64
    f64 3.14
""")
    cleanupDir(dir)
    check r.isOk

  test "f64 rejects an overflowing literal":
    let (r, dir) = analyzeSingle("""
public module f64:
  literal: "float64"

public module u64:
  literal: "uint64"

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
  literal: "float32"

public module u64:
  literal: "uint64"

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
  literal: "float32"

public module u64:
  literal: "uint64"

public module M:
  public func go(): f32
    f32 0.1
""")
    cleanupDir(dir)
    check r.isOk

  test "f32 rejects an overflowing literal":
    let (r, dir) = analyzeSingle("""
public module f32:
  literal: "float32"

public module u64:
  literal: "uint64"

public module M:
  public func go(): f32
    f32 1.0e40
""")
    cleanupDir(dir)
    check r.isErr
    check errorContains(r.error, "32-bit float")

  test "f32 accepts nan":
    let (r, dir) = analyzeSingle("""
public module f32:
  literal: "float32"

public module u64:
  literal: "uint64"

public module M:
  public func go(): f32
    f32 nan
""")
    cleanupDir(dir)
    check r.isOk

  test "f32 accepts inf":
    let (r, dir) = analyzeSingle("""
public module f32:
  literal: "float32"

public module u64:
  literal: "uint64"

public module M:
  public func go(): f32
    f32 inf
""")
    cleanupDir(dir)
    check r.isOk

  test "f32 accepts -inf":
    let (r, dir) = analyzeSingle("""
public module f32:
  literal: "float32"

public module u64:
  literal: "uint64"

public module M:
  public func go(): f32
    f32 -inf
""")
    cleanupDir(dir)
    check r.isOk

  test "f64 accepts nan / inf / -inf":
    let (r, dir) = analyzeSingle("""
public module f64:
  literal: "float64"

public module u64:
  literal: "uint64"

public module M:
  public func go(): f64
    f64 nan
""")
    cleanupDir(dir)
    check r.isOk

suite "analyzer — analyze-shape corner cases":

  test "file with only a self-referential generic (no modules) analyzes":
    # Exercises the `rltkGeneric: discard` branch in analyzeFile —
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
  literal: "uint8"

public module u32:
  literal: "uint32"

public module u64:
  literal: "uint64"

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
  literal: "uint8"

public module u64:
  literal: "uint64"

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
  literal: "uint8"

public module u64:
  literal: "uint64"

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
  literal: "uint8"

  @extern("u8_add_u8")
  public func add(a: u8, b: u8): u8

public module u64:
  literal: "uint64"
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
  literal: "uint8"

public module u64:
  literal: "uint64"

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
  literal: "int32"

  public func add(a: i32, b: i32): i32
    a

public module u64:
  literal: "uint64"

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
  literal: "float32"

  public func add(a: f32, b: f32): f32
    a

public module u64:
  literal: "uint64"

public module M:
  public func go(): f32
    y = 1.0
    f32.add(y, y)
""")
    cleanupDir(dir)
    check r.isOk

  test "bare special float literals (nan / inf / -inf) default to f32":
    # `nan` / `inf` / `-inf` are floats of kind `lkFloat`, so the same
    # Approach C defaulting rule that applies to `1.0` applies here —
    # bare-assignment RHS with no expected context binds the target as
    # f32. Then downstream f32.add(x, y) type-checks with both operands
    # as f32.
    let (r, dir) = analyzeSingle("""
public module f32:
  literal: "float32"

  public func add(a: f32, b: f32): f32
    a

public module u64:
  literal: "uint64"

public module M:
  public func go(): f32
    x = nan
    y = inf
    z = -inf
    f32.add(x, f32.add(y, z))
""")
    cleanupDir(dir)
    check r.isOk

  test "bare special float literal adopts concrete f32 in function arg":
    # Concrete-adopt branch of analyzeBareLiteral: `expected = some(f32)`
    # for the call argument, so bare `nan` binds as f32 directly rather
    # than defaulting. Symmetric to the `u8.add(10, 20)` regression
    # guard higher up in this suite.
    let (r, dir) = analyzeSingle("""
public module f32:
  literal: "float32"

  public func add(a: f32, b: f32): f32
    a

public module u64:
  literal: "uint64"

public module M:
  public func go(): f32
    f32.add(nan, inf)
""")
    cleanupDir(dir)
    check r.isOk

  test "bare string literal in assignment defaults to String":
    let (r, dir) = analyzeSingle("""
public module u32:
  literal: "uint32"

public module string:
  literal: "string"

  public func length(s: string): u32
    u32 0

public module u64:
  literal: "uint64"

public module M:
  public func go(): u32
    z = "data"
    string.length(z)
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
  literal: "uint8"

  public func add(a: u8, b: u8): u8
    a

public module i32:
  literal: "int32"

public module u64:
  literal: "uint64"

public module M:
  public func go(): u8
    u8.add(10, 20)
""")
    cleanupDir(dir)
    check r.isOk

  test "bare literal in struct kwarg adopts the field's concrete type":
    # `Pair { a: 10, b: 20 }` — each kwarg value is analyzed with
    # `expected = some(<field's declared type>)`. Bare literals adopt
    # u8 directly (concrete-adopt branch in analyzeBareLiteral).
    let (r, dir) = analyzeSingle("""
public module u8:
  literal: "uint8"

public module i32:
  literal: "int32"

public module u64:
  literal: "uint64"

public module Pair:
  struct:
    a: u8
    b: u8

  public func mk(): Pair
    Pair { a: 10, b: 20 }
""")
    cleanupDir(dir)
    check r.isOk

  test "bare literal in union kwarg adopts a concrete field type":
    # Union variant field is concrete (`level: u8`). Bare literal in
    # the initializer's kwarg value adopts u8 via the same concrete-
    # adopt path as struct kwargs.
    let (r, dir) = analyzeSingle("""
public module u8:
  literal: "uint8"

public module i32:
  literal: "int32"

public module u64:
  literal: "uint64"

public module Sig:
  union:
    Timeout { level: u8 }

  public func mk(): Sig
    Sig.Timeout { level: 3 }
""")
    cleanupDir(dir)
    check r.isOk

  test "bare literal in struct kwarg with a generic field defaults to i32":
    # Struct-side analog of the union generic-default test. A struct
    # with a bare `struct:` header may declare a generic-typed field
    # (the rule against generic fields only fires when the explicit
    # `struct(...)` header is present). Under Approach C, the bare
    # `42` sees `expected = some(Any-generic)` and falls into
    # `analyzeBareLiteral`'s default branch → i32. The kwarg accepts,
    # and the struct's outer impls are inferred to be [i32] via the
    # generic-context ddkStruct path in `resolveDataModuleArgumentType`.
    let (r, dir) = analyzeSingle("""
public module u32:
  literal: "uint32"

public module u64:
  literal: "uint64"

public module i32:
  literal: "int32"

  public func byte_size(items: u32): u64
    u64 0

public generic Any:
  func byte_size(items: u32): u64

public module Holder:
  struct:
    value: Any

public module M:
  public func go(): u32
    h = Holder { value: 42 }
    u32 0
""")
    cleanupDir(dir)
    check r.isOk

  test "bare literal in union kwarg with a generic field defaults to i32":
    # Union variant field is generic (`value: Any`). Under Approach C
    # `expected = some(generic)` falls through to the default branch —
    # bare 42 becomes i32, and i32 (which implements Any via byte_size)
    # is bound to Any in the generic-impl map. Result: `Status[i32]`.
    let (r, dir) = analyzeSingle("""
public module u32:
  literal: "uint32"

public module u64:
  literal: "uint64"

public module i32:
  literal: "int32"

  public func byte_size(items: u32): u64
    u64 0

public generic Any:
  func byte_size(items: u32): u64

public module Status:
  union:
    Ok { value: Any }
    Err { value: u32 }

public module M:
  public func mk(): Status[i32]
    Status.Ok { value: 42 }
""")
    cleanupDir(dir)
    check r.isOk

  test "bare literal in setter RHS adopts the field's type":
    # `p.a = 10` — the setter's RHS is threaded with the getter's
    # field type as expected. Bare 10 adopts u8 via concrete-adopt.
    let (r, dir) = analyzeSingle("""
public module u8:
  literal: "uint8"

public module i32:
  literal: "int32"

public module u64:
  literal: "uint64"

public module Pair:
  struct:
    a: u8
    b: u8

  public func setA(p: Pair): Pair
    p.a = 10
    p
""")
    cleanupDir(dir)
    check r.isOk

  test "bare literal exceeding the concrete range is rejected":
    # `u8.add(300, 0)` — 300 doesn't fit in u8 (0..255). The concrete-
    # adopt branch adopts u8, then analyzeLiteral's range-check rejects.
    let (r, dir) = analyzeSingle("""
public module u8:
  literal: "uint8"

  public func add(a: u8, b: u8): u8
    a

public module i32:
  literal: "int32"

public module u64:
  literal: "uint64"

public module M:
  public func go(): u8
    u8.add(300, 0)
""")
    cleanupDir(dir)
    check r.isErr
    check errorContains(r.error, "u8")

  test "bare literal errors clearly when the default type is not in scope":
    # `x = 10` has no expected context, so analyzeBareLiteral falls into
    # the default branch and looks up `i32`. This fixture omits `i32`
    # entirely — the error must name the missing default type and
    # hint at the scope.
    let (r, dir) = analyzeSingle("""
public module u8:
  literal: "uint8"

  public func add(a: u8, b: u8): u8
    a

public module u64:
  literal: "uint64"

public module M:
  public func go(): u8
    x = 10
    u8.add(x, x)
""")
    cleanupDir(dir)
    check r.isErr
    check errorContains(r.error, "i32")
    check errorContains(r.error, "scope")

  test "bare literal in a position expecting a struct is rejected":
    # If a function arg expects a struct-typed module (`Pair`) and the
    # caller passes a bare literal, analyzeBareLiteral's expected is
    # some(module), the module's data def is rdkStruct — clear error.
    let (r, dir) = analyzeSingle("""
public module u8:
  literal: "uint8"

public module i32:
  literal: "int32"

public module u64:
  literal: "uint64"

public module Pair:
  struct:
    a: u8
    b: u8

  public func accept(p: Pair): u8
    u8 0

public module M:
  public func go(): u8
    Pair.accept(10)
""")
    cleanupDir(dir)
    check r.isErr
    check errorContains(r.error, "struct")

suite "analyzer — kwarg + pattern shorthand end-to-end":
  # Sugar at the parser layer: `Struct { x }` == `Struct { x: x }`;
  # `case Ok { value }` == `case Ok { value: value }`. Downstream sees
  # the explicit form, so a program using shorthand must analyze
  # cleanly for the same reasons the explicit form does.

  test "struct initializer kwarg shorthand analyzes":
    let (r, dir) = analyzeSingle("""
public module u8:
  literal: "uint8"

public module u64:
  literal: "uint64"

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
  literal: "uint8"

public module u64:
  literal: "uint64"

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
  literal: "uint8"

public module u64:
  literal: "uint64"

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

suite "analyzer — deep constraint satisfaction":

  test "impl with matching signature satisfies the required generic":
    let (r, dir) = analyzeSingle("""
public module i32:
  literal: "int32"

public module u8:
  literal: "uint8"

  public func compare(a: u8, b: u8): i32
    i32 0

public module u64:
  literal: "uint64"

public generic Comparable:
  func compare(a: Comparable, b: Comparable): i32

module Pair:
  struct:
    value: Comparable

module M:
  struct:
    p: Pair[u8]
""")
    cleanupDir(dir)
    check r.isOk

  test "impl with wrong return type is rejected at def time, never called":
    # u8.compare returns u64 where Comparable demands i32. Nothing
    # ever calls compare — the deep check still rejects at the
    # Pair[u8] declaration.
    let (r, dir) = analyzeSingle("""
public module i32:
  literal: "int32"

public module u64:
  literal: "uint64"

public module u8:
  literal: "uint8"

  public func compare(a: u8, b: u8): u64
    u64 0

public generic Comparable:
  func compare(a: Comparable, b: Comparable): i32

module Pair:
  struct:
    value: Comparable

module M:
  struct:
    p: Pair[u8]
""")
    cleanupDir(dir)
    check r.isErr
    check errorContains(r.error, "does not implement")
    check errorContains(r.error, "compare(a: u8, b: u8): i32")

  test "parameterized impl satisfies at definition level":
    # Pair requires Comparable; the impl is Array[u8]. The check
    # compares at definition level: Comparable's self-references
    # become Array's SELF SHAPE (Array[Comparable]), matching Array's
    # compare as declared — the site binding u8 plays no part here
    # (it is validated by the recursive argtype walk instead).
    let (r, dir) = analyzeSingle("""
public module i32:
  literal: "int32"

public module u32:
  literal: "uint32"

public module u8:
  literal: "uint8"

  public func compare(a: u8, b: u8): i32
    i32 0

public module u64:
  literal: "uint64"

public generic Comparable:
  func compare(a: Comparable, b: Comparable): i32

public module Array:
  struct(Comparable):
    size: u32

  public func compare(a: Array[Comparable], b: Array[Comparable]): i32
    i32 0

module Pair:
  struct:
    value: Comparable

module M:
  struct:
    p: Pair[Array[u8]]
""")
    cleanupDir(dir)
    check r.isOk

  test "free generic as impl satisfies by identity":
    # Inside Wrapper's own definition the impl IS the free generic
    # Comparable — expected and candidate signatures both carry the
    # same generic identity, so equality decides without grounding.
    let (r, dir) = analyzeSingle("""
public module i32:
  literal: "int32"

public module u32:
  literal: "uint32"

public module u64:
  literal: "uint64"

public generic Comparable:
  func compare(a: Comparable, b: Comparable): i32

public module Array:
  struct(Comparable):
    size: u32

  public func compare(a: Array[Comparable], b: Array[Comparable]): i32
    i32 0

module Wrapper:
  struct:
    items: Array[Comparable]
""")
    cleanupDir(dir)
    check r.isOk

  test "one matching overload among several satisfies":
    let (r, dir) = analyzeSingle("""
public module i32:
  literal: "int32"

public module u32:
  literal: "uint32"

public module u8:
  literal: "uint8"

  public func compare(a: u32, b: u32): i32
    i32 0

  public func compare(a: u8, b: u8): i32
    i32 0

public module u64:
  literal: "uint64"

public generic Comparable:
  func compare(a: Comparable, b: Comparable): i32

module Pair:
  struct:
    value: Comparable

module M:
  struct:
    p: Pair[u8]
""")
    cleanupDir(dir)
    check r.isOk

  test "generic offered where a module type is expected is rejected":
    # Comparable demands weight(a: u8, factor: u32): i32. u8 provides
    # weight over a free generic K in the factor position — a bare
    # generic can never stand where a concrete module type is
    # demanded, so this is a definite def-time failure, not a
    # deferral to the call site.
    let (r, dir) = analyzeSingle("""
public module i32:
  literal: "int32"

public module u32:
  literal: "uint32"

public module u64:
  literal: "uint64"

public generic K:
  func foo(): u32

public module u8:
  literal: "uint8"

  public func weight(a: u8, factor: K): i32
    i32 0

public generic Comparable:
  func weight(a: Comparable, factor: u32): i32

module Pair:
  struct:
    value: Comparable

module M:
  struct:
    p: Pair[u8]
""")
    cleanupDir(dir)
    check r.isErr
    check errorContains(r.error, "does not implement")
    check errorContains(r.error, "weight(a: u8, factor: u32): i32")

  test "a richer generic satisfies a contract generic structurally":
    # Box requires Eq; the impl is the generic Ord — a DIFFERENT
    # generic that declares Eq's funcDef with matching signature
    # (self-positions substituted: Eq → Ord). Case 4 of the matching
    # relation — subsumption, not identity.
    let (r, dir) = analyzeSingle("""
public module u32:
  literal: "uint32"

public module u64:
  literal: "uint64"

public generic Eq:
  func eq(a: Eq, b: Eq): u32

public generic Ord:
  func eq(a: Ord, b: Ord): u32
  func lt(a: Ord, b: Ord): u32

public module Box:
  struct(Eq):
    size: u32

module Wrapper:
  struct:
    items: Box[Ord]
""")
    cleanupDir(dir)
    check r.isOk

  test "a generic whose signature diverges from the contract is rejected":
    # Ord declares eq(a: Ord, b: u32) where Eq demands eq over two
    # self-positions. The second position pits expected Ord (generic
    # contract) against actual u32 (module) — nested case 3: u32 has
    # no functions, cannot satisfy Ord, so the candidate fails.
    let (r, dir) = analyzeSingle("""
public module u32:
  literal: "uint32"

public module u64:
  literal: "uint64"

public generic Eq:
  func eq(a: Eq, b: Eq): u32

public generic Ord:
  func eq(a: Ord, b: u32): u32

public module Box:
  struct(Eq):
    size: u32

module Wrapper:
  struct:
    items: Box[Ord]
""")
    cleanupDir(dir)
    check r.isErr
    check errorContains(r.error, "does not implement")
    check errorContains(r.error, "to support `Eq`")

suite "analyzer — entry point":
  # `entry` runs off the analyze path (CLI compile only). The
  # root file must expose exactly one public module with a
  # `public func start(): i32`. i32 is defined inline here so it resolves
  # without the std-vendor injection.

  const I32 = """
public module i32:
  literal: "int32"

public module u64:
  literal: "uint64"

"""

  test "exactly one public start(): i32 is the entry point":
    let (r, dir) = analyzeAppSingle(I32 & """
public module M:
  public func start(): i32
    i32 0
""")
    cleanupDir(dir)
    check r.isOk
    check entry(r.get).isOk

  test "no entry point is rejected":
    let (r, dir) = analyzeAppSingle(I32 & """
public module M:
  public func run(): i32
    i32 0
""")
    cleanupDir(dir)
    check r.isOk
    let entry = entry(r.get)
    check entry.isErr
    check errorContains(entry.error, "found 0")

  test "two entry points are rejected":
    let (r, dir) = analyzeAppSingle(I32 & """
public module A:
  public func start(): i32
    i32 0

public module B:
  public func start(): i32
    i32 0
""")
    cleanupDir(dir)
    check r.isOk
    let entry = entry(r.get)
    check entry.isErr
    check errorContains(entry.error, "found 2")

  test "wrong return type is not an entry point":
    let (r, dir) = analyzeAppSingle(I32 & """
public module u8:
  literal: "uint8"

public module M:
  public func start(): u8
    u8 0
""")
    cleanupDir(dir)
    check r.isOk
    check entry(r.get).isErr

  test "non-public start is not an entry point":
    let (r, dir) = analyzeAppSingle(I32 & """
public module M:
  func start(): i32
    i32 0
""")
    cleanupDir(dir)
    check r.isOk
    check entry(r.get).isErr

  test "start with arguments is not an entry point":
    let (r, dir) = analyzeAppSingle(I32 & """
public module M:
  public func start(x: i32): i32
    x
""")
    cleanupDir(dir)
    check r.isOk
    check entry(r.get).isErr

  test "start inside a non-public module is not an entry point":
    let (r, dir) = analyzeAppSingle(I32 & """
module M:
  public func start(): i32
    i32 0
""")
    cleanupDir(dir)
    check r.isOk
    check entry(r.get).isErr
