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

  test "import alias is rejected at analyzer level (known limitation)":
    # The resolver maps the alias `Byte` -> u8's DefinedType and the
    # program resolves cleanly, but the analyzer's lookup of the
    # imported module uses its intrinsic name (`u8`) which is not in
    # the alias-keyed file scope, so the analyze pass currently
    # errors. Recorded as a regression guard until the analyzer
    # learns to look up imports by binding rather than intrinsic
    # name.
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
    check r.isErr
    check errorContains(r.error, "u8")
    check errorContains(r.error, "neither defined nor imported")

suite "analyzer — generic constraint satisfaction":

  test "concrete impl missing a required funcDef is rejected":
    # BadImpl is a struct-backed module with no byte_size — it cannot
    # satisfy Any. The analyzer should detect this when Array[BadImpl]
    # is used.
    let (r, dir) = analyzeFiles([
      ("entry.asl", """
import { Array, Any, u32 } from "./base.aslr"

public module BadImpl:
  struct:
    x: u32

module N:
  struct:
    a: Array[BadImpl]
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
    # Exercises the `adtkGeneric: discard` branch in analyzeFile —
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
