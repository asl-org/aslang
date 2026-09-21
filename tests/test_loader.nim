## Tests for the BFS multi-file loader.
##
## Each test writes a small set of files to a temp dir, runs
## `parser.parse(rootPath, ...)`, and asserts on outcomes:
## successful topological order, cycle detection, missing files,
## parent-directory escapes, and large-file rejection.

import unittest, os, strutils, results, tables

import parser/main as parser
import analyzer/main as analyzer
import tutils

suite "loader — successful multi-file BFS":

  test "single file with no imports":
    let (r, dir) = parseFiles([
      ("entry.asl", """
module M:
  func go(): u8
    u8 0
""")
    ])
    cleanupDir(dir)
    check r.isOk
    check r.get.files.len == 1

  test "imports are walked and topologically ordered (leaf first)":
    let (r, dir) = parseFiles([
      ("entry.asl", """
import { Helper } from "./helper.asl"

module Main:
  func go(): u8
    u8 0
"""),
      ("helper.asl", """
public module Helper:
  func go(): u8
    u8 0
""")
    ])
    cleanupDir(dir)
    check r.isOk
    let files = r.get.files
    check files.len == 2
    # Topological order: leaves first, root last.
    check files[0].path.endsWith("helper.asl")
    check files[1].path.endsWith("entry.asl")

  test "diamond import (a -> b, a -> c, b -> d, c -> d) loads each file once":
    let (r, dir) = parseFiles([
      ("a.asl", """
import { B } from "./b.asl"
import { C } from "./c.asl"

module A:
  func go(): u8
    u8 0
"""),
      ("b.asl", """
import { D } from "./d.asl"
public module B:
  func go(): u8
    u8 0
"""),
      ("c.asl", """
import { D } from "./d.asl"
public module C:
  func go(): u8
    u8 0
"""),
      ("d.asl", """
public module D:
  func go(): u8
    u8 0
""")
    ])
    cleanupDir(dir)
    check r.isOk
    check r.get.files.len == 4
    # d should come first (deepest leaf), a last (root).
    check r.get.files[0].path.endsWith("d.asl")
    check r.get.files[^1].path.endsWith("a.asl")

suite "loader — error paths":

  test "missing imported file is reported":
    let (r, dir) = parseFiles([
      ("entry.asl", """
import { Foo } from "./does_not_exist.asl"

module M:
  func go(): u8
    u8 0
""")
    ])
    cleanupDir(dir)
    check r.isErr
    check errorContains(r.error, "does_not_exist.asl")

  test "cyclic import is detected":
    let (r, dir) = parseFiles([
      ("a.asl", """
import { B } from "./b.asl"

module A:
  func go(): u8
    u8 0
"""),
      ("b.asl", """
import { A } from "./a.asl"

public module B:
  func go(): u8
    u8 0
""")
    ])
    cleanupDir(dir)
    check r.isErr
    check errorContains(r.error, "cyclic")

  test "import path with unrecognized extension: neither file nor .asl fallback exists":
    # Explicit-form import of `./bar.txt`. Neither `./bar.txt` nor
    # `./bar.txt.asl` exists in the temp dir. `toAbsPath`
    # tries the bare path first, then the `.asl` fallback, and
    # errors when both are missing. The specific error message is
    # currently masked by the parser's `any(importSpec)`
    # backtracking, so the surface error is a downstream "expected
    # module" one — we assert only that the parse fails.
    let (r, dir) = parseFiles([
      ("entry.asl", """
import { Foo } from "./bar.txt"

module M:
  func go(): u8
    u8 0
""")
    ])
    cleanupDir(dir)
    check r.isErr

  test "shorthand import path without extension: fallback also missing errors":
    # Same shape as above but via the shorthand form. Same
    # backtracking caveat — only assert `isErr`.
    let (r, dir) = parseFiles([
      ("entry.asl", """
import "./bar"

module M:
  func go(): u8
    u8 0
""")
    ])
    cleanupDir(dir)
    check r.isErr

  test "extensionless explicit import falls back to `<source>.asl`":
    # User writes `import { Helper } from "./helper"` (no `.asl`
    # suffix). The importer directory holds `helper.asl`. The
    # compiler resolves the bare source to that file via the
    # `.asl` fallback.
    let (r, dir) = parseFiles([
      ("entry.asl", """
import { Helper } from "./helper"

module Caller:
  func go(): u8
    u8 0
"""),
      ("helper.asl", """
public module Helper:
  public func go(): u8
    u8 0
""")
    ])
    cleanupDir(dir)
    check r.isOk

  test "extensionless shorthand import falls back to `<source>.asl`":
    # Same as above but via the shorthand form.
    let (r, dir) = parseFiles([
      ("entry.asl", """
import "./helper"

module Caller:
  func go(): u8
    u8 0
"""),
      ("helper.asl", """
public module Helper:
  public func go(): u8
    u8 0
""")
    ])
    cleanupDir(dir)
    check r.isOk

  test "extensionless import falls back to `<source>.aslr` when no .asl exists":
    # If `<source>.asl` is missing but `<source>.aslr` (runtime
    # interface) is present, the compiler picks that up as the
    # last-chance fallback. Written via the shorthand form since
    # the runtime interface is normally shorthand-imported.
    let (r, dir) = parseFiles([
      ("entry.asl", """
import "./rt"

module Caller:
  func go(): u8
    u8 0
"""),
      ("rt.aslr", """
public module Runtime:
  literal: "runtime_marker"
""")
    ])
    cleanupDir(dir)
    check r.isOk

  test "importing the same file twice (bare + .asl forms) is rejected as duplicate":
    # `./helper` (bare, fallback-resolved) and `./helper.asl` name the
    # SAME absolute path, so importing both is a duplicate import — a file
    # may import each source path at most once. (This also pins that the
    # two path forms normalize to one absPath. True BFS dedup across
    # DIFFERENT importers is covered by the diamond test above.)
    let (r, dir) = parseFiles([
      ("entry.asl", """
import { Helper as First } from "./helper"
import { Helper as Second } from "./helper.asl"

module Caller:
  func go(): u8
    u8 0
"""),
      ("helper.asl", """
public module Helper:
  public func go(): u8
    u8 0
""")
    ])
    cleanupDir(dir)
    check r.isErr
    check errorContains(r.error, "duplicate import")

  test "unknown vendor import is rejected":
    # `toImportPath` accepts the `@`-prefix syntactically, but
    # `toAbsPath` rejects vendor names that aren't in the
    # threaded `VendorRoots` table. Tests pass empty vendorRoots by
    # default, so any `@<name>` reference is "unknown vendor".
    let (r, dir) = parseFiles([
      ("entry.asl", """
import "@std"

module M:
  func go(): u8
    u8 0
""")
    ])
    cleanupDir(dir)
    check r.isErr

  test "parent-directory escape via ../ is rejected":
    # The grammar's importLineSpec calls toAbsPath; on rejection
    # the error is produced but currently swallowed by the parser's
    # `any(importSpec)` backtracking, so the surface error is the
    # generic "expected module" message. We assert only that the parse
    # fails — the constructor invariant is what we care about.
    let (r, dir) = parseFiles([
      ("entry.asl", """
import { Foo } from "../escape.asl"

module M:
  func go(): u8
    u8 0
""")
    ])
    cleanupDir(dir)
    check r.isErr

  test "sneaky parent escape via ./sub/../../escape is rejected":
    let (r, dir) = parseFiles([
      ("entry.asl", """
import { Foo } from "./sub/../../escape.asl"

module M:
  func go(): u8
    u8 0
""")
    ])
    cleanupDir(dir)
    check r.isErr

  test "deep import chain (a -> b -> c -> d) loads each in order":
    let (r, dir) = parseFiles([
      ("a.asl", """
import { B } from "./b.asl"
module A:
  func go(): u8
    u8 0
"""),
      ("b.asl", """
import { C } from "./c.asl"
public module B:
  func go(): u8
    u8 0
"""),
      ("c.asl", """
import { D } from "./d.asl"
public module C:
  func go(): u8
    u8 0
"""),
      ("d.asl", """
public module D:
  func go(): u8
    u8 0
""")
    ])
    cleanupDir(dir)
    check r.isOk
    check r.get.files.len == 4
    check r.get.files[0].path.endsWith("d.asl")
    check r.get.files[^1].path.endsWith("a.asl")

  test "import from a subdirectory is permitted":
    let (r, dir) = parseFiles([
      ("entry.asl", """
import { Sub } from "./sub/sub.asl"
module Main:
  func go(): u8
    u8 0
"""),
      ("sub/sub.asl", """
public module Sub:
  func go(): u8
    u8 0
""")
    ])
    cleanupDir(dir)
    check r.isOk
    check r.get.files.len == 2

  test "self-import is rejected by the parser":
    let (r, dir) = parseFiles([
      ("entry.asl", """
import { M } from "./entry.asl"

module M:
  func go(): u8
    u8 0
""")
    ])
    cleanupDir(dir)
    check r.isErr
    check errorContains(r.error, "importing the source file in itself")

suite "loader — vendor auto-injection":

  test "an .asl file with no explicit imports can reference std vendor types":
    # No user-written import line. `writeStdVendor` registers a
    # `std → base.aslr` vendor, and `newAslFile` auto-injects the
    # shorthand `import "@std"` — bringing `u8` (etc.) into scope.
    let (vendorRoots, vendorDir) = writeStdVendor()
    let (r, userDir) = resolveFiles([
      ("entry.asl", """
public module Caller:
  public func go(): u8
    u8 0
""")
    ], 2, vendorRoots)
    cleanupDir(userDir); cleanupDir(vendorDir)
    check r.isOk

  test "an .asl file with explicit imports also gets the auto-injected std":
    # Both the explicit relative import and the auto-injected
    # shorthand coexist; the typeIndex carries both binding sets.
    let (vendorRoots, vendorDir) = writeStdVendor()
    let (r, userDir) = resolveFiles([
      ("entry.asl", """
import { Helper } from "./helper.asl"

public module Caller:
  public func go(): u8
    u8 0
"""),
      ("helper.asl", """
public module Helper:
  public func go(): u8
    u8 0
""")
    ], 2, vendorRoots)
    cleanupDir(userDir); cleanupDir(vendorDir)
    check r.isOk

  test "auto-injection is not applied to .aslr files":
    # `parseFiles` writes the entry as the first spec; an `.aslr`
    # entry dispatches to `aslrFileSpec` → `newAslrFile`, which does
    # not consume `vendorRoots`. The aslr file therefore does NOT
    # gain an `@std` import — verifying this by referencing `u8`
    # from the std vendor without an explicit import, which must
    # fail to resolve.
    let (vendorRoots, vendorDir) = writeStdVendor()
    let (r, userDir) = resolveFiles([
      ("entry.aslr", """
public module Caller:
  public func go(): u8
    u8 0
""")
    ], 2, vendorRoots)
    cleanupDir(userDir); cleanupDir(vendorDir)
    check r.isErr

  test "vendor pointing at the importing file is a self-import":
    # --vendor std:<entry file> auto-injects `import "@std"` resolving
    # to the entry file itself; the self-import check runs on the
    # post-injection list, so this is rejected like any other
    # self-import.
    let dir = writeFiles([("entry.asl", """
module M:
  func go(): u8
    u8 0
""")])
    let entry = dir / "entry.asl"
    var roots = initTable[string, string]()
    roots["std"] = entry
    let r = parse(entry, 2, false, roots)
    cleanupDir(dir)
    check r.isErr
    check errorContains(r.error, "importing the source file in itself")

suite "loader — source overlays":

  test "an overlay shadows the root file on disk":
    # Disk holds a broken file; the overlay's valid buffer wins.
    let dir = writeFiles([("entry.asl", "module M:\n")])
    let entry = dir / "entry.asl"
    var overlays = initTable[string, string]()
    overlays[entry] = "module M:\n  func go(): u8\n    u8 0\n"
    let r = parse(entry, 2, false, initTable[string, string](), overlays)
    cleanupDir(dir)
    check r.isOk

  test "an overlay shadows an imported file on disk":
    let dir = writeFiles([
      ("entry.asl", """
import { Helper } from "./helper.asl"

module Main:
  func go(): u8
    u8 0
"""),
      ("helper.asl", """
public module Helper:
  func go(): u8
    u8 0
""")
    ])
    let entry = dir / "entry.asl"
    var overlays = initTable[string, string]()
    overlays[dir / "helper.asl"] = "public module Helper:\n"
    let r = parse(entry, 2, false, initTable[string, string](), overlays)
    cleanupDir(dir)
    check r.isErr
    check errorContains(r.error, "helper.asl:1:8 module must have at least 1")

  test "an overlay stands in for a file that is not on disk":
    let dir = writeFiles([("placeholder.asl", "")])
    let entry = dir / "unsaved.asl"
    var overlays = initTable[string, string]()
    overlays[entry] = "module M:\n  func go(): u8\n    u8 0\n"
    let r = parse(entry, 2, false, initTable[string, string](), overlays)
    cleanupDir(dir)
    check r.isOk
    check r.get.files.len == 1

  test "an overlay with invalid UTF-8 is rejected":
    let dir = writeFiles([("placeholder.asl", "")])
    let entry = dir / "unsaved.asl"
    var overlays = initTable[string, string]()
    overlays[entry] = "module M:\n  func go(): u8\n    u8 0 \xff\n"
    let r = parse(entry, 2, false, initTable[string, string](), overlays)
    cleanupDir(dir)
    check r.isErr
    check errorContains(r.error, "invalid UTF-8")
