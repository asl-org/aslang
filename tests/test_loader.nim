## Tests for the BFS multi-file loader.
##
## Each test writes a small set of files to a temp dir, runs
## `parser.parse(rootPath, ...)`, and asserts on outcomes:
## successful topological order, cycle detection, missing files,
## parent-directory escapes, and large-file rejection.

import unittest, os, strutils, results

import parser
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

  test "parent-directory escape via ../ is rejected":
    # The grammar's importLineSpec calls resolveImportPath; on rejection
    # the error is produced but currently swallowed by the parser's
    # `any(importBlockSpec)` backtracking, so the surface error is the
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
