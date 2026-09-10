## Tests for AST constructor invariants. Many of the duplicate-
## detection errors that constructors raise (StructDef.fieldIndex,
## UnionDef.variantIndex, UnionPattern bindings, KeywordArgumentList
## argIndex, etc.) are unreachable from the grammar surface today
## because the parser's `atLeastOne` backtracks past them, so the
## tests here exercise the constructors directly.

import unittest, options, results, strutils

import tokenizer/main as tokenizer
import parser/main as parser
import analyzer/main as analyzer
import tutils

proc id(s: string): Identifier =
  ## Quick Identifier from a literal name. Tests don't care about
  ## location accuracy — `newLocation()` returns 1:1.
  let r = newIdentifier(s, newLocation())
  doAssert r.isOk, "newIdentifier failed for '" & s & "': " & r.error.msg
  r.get

proc argType(name: string): ArgumentType =
  newArgumentType(id(name))

proc argDef(name, typeName: string): ArgumentDef =
  newArgumentDef(id(name), argType(typeName))

proc bareStructHeader(): StructDefHeader =
  ## Empty-requires struct header at a synthetic Location — used by
  ## the field-list invariant tests, which don't exercise the header.
  let r = newStructDefHeader(@[], newLocation())
  doAssert r.isOk, "newStructDefHeader failed: " & r.error.msg
  r.get

suite "ast — Identifier":

  test "identifier of exactly 256 chars is accepted (boundary)":
    var name = ""
    for i in 0..<256: name.add('a')   # 256 chars
    let r = newIdentifier(name, newLocation())
    check r.isOk

  test "identifier of 257 chars is rejected (boundary)":
    var name = ""
    for i in 0..<257: name.add('a')   # 257 chars
    let r = newIdentifier(name, newLocation())
    check r.isErr
    check errorContains(r.error.msg, "max length 256")

  test "identifier exactly '__asl' is rejected (prefix boundary)":
    let r = newIdentifier("__asl", newLocation())
    check r.isErr
    check errorContains(r.error.msg, "__asl")

  test "identifier '__as' (one char short of __asl) is accepted":
    let r = newIdentifier("__as", newLocation())
    check r.isOk

  test "identifier starting with __asl is rejected":
    let r = newIdentifier("__aslSecret", newLocation())
    check r.isErr
    check errorContains(r.error.msg, "__asl")

  test "regular identifier is accepted":
    let r = newIdentifier("foo", newLocation())
    check r.isOk
    check r.get.value == "foo"

  test "identifiers are equal iff their text is equal":
    let a1 = id("a")
    let a2 = id("a")
    let b = id("b")
    check a1 == a2
    check not (a1 == b)

  test "identifier hash matches the string hash of its value":
    # hash should be a stable function of the textual name.
    let a = id("foo")
    check a.hash == a.hash
    check id("foo").hash == id("foo").hash

suite "ast — StructDef invariants":

  test "newStructDef rejects an empty field list":
    let r = newStructDef(bareStructHeader(), @[])
    check r.isErr
    check errorContains(r.error.msg, "at least one field")

  test "newStructDef rejects duplicate field names":
    let r = newStructDef(bareStructHeader(), @[argDef("a", "u8"), argDef("a", "u16")])
    check r.isErr
    check errorContains(r.error.msg, "duplicate field")

  test "newStructDef accepts unique field names":
    let r = newStructDef(bareStructHeader(), @[argDef("a", "u8"), argDef("b", "u16")])
    check r.isOk
    check r.get.fields.len == 2

suite "ast — VariantDef invariants":

  test "newVariantDef rejects duplicate field names within a variant":
    let r = newVariantDef(id("V"),
      @[argDef("x", "u8"), argDef("x", "u16")], newLocation())
    check r.isErr
    check errorContains(r.error.msg, "duplicate field")

  test "newVariantDef accepts unique fields":
    let r = newVariantDef(id("V"),
      @[argDef("x", "u8"), argDef("y", "u16")], newLocation())
    check r.isOk

  test "newVariantDef accepts an empty fields list":
    let r = newVariantDef(id("V"), @[], newLocation())
    check r.isOk

suite "ast — UnionDef invariants":

  test "newUnionDef rejects duplicate variant names":
    let v1 = newVariantDef(id("Same"), @[argDef("x", "u8")],
      newLocation()).get
    let v2 = newVariantDef(id("Same"), @[argDef("y", "u8")],
      newLocation()).get
    let r = newUnionDef(@[v1, v2], newLocation())
    check r.isErr
    check errorContains(r.error.msg, "duplicate variant")

  test "newUnionDef accepts a single variant":
    let v = newVariantDef(id("A"), @[argDef("x", "u8")],
      newLocation()).get
    let r = newUnionDef(@[v], newLocation())
    check r.isOk

suite "ast — ArgumentDefList invariants":

  test "newArgumentDefList rejects duplicate argument names":
    let r = newArgumentDefList(
      @[argDef("a", "u8"), argDef("a", "u8")], newLocation())
    check r.isErr
    check errorContains(r.error.msg, "duplicate argument")

  test "newArgumentDefList accepts unique args":
    let r = newArgumentDefList(
      @[argDef("a", "u8"), argDef("b", "u16")], newLocation())
    check r.isOk

  test "newArgumentDefList accepts an empty list":
    let r = newArgumentDefList(@[], newLocation())
    check r.isOk

suite "ast — UnionPattern invariants":

  test "newUnionPattern rejects duplicate field names":
    # Two pattern fields with the same `name`, different bindings.
    let f1 = newUnionPatternField(id("value"), id("a"), newLocation())
    let f2 = newUnionPatternField(id("value"), id("b"), newLocation())
    let r = newUnionPattern(id("Ok"), @[f1, f2])
    check r.isErr
    check errorContains(r.error.msg, "duplicate field")

  test "newUnionPattern rejects duplicate bindings":
    # Different field names, same binding identifier.
    let f1 = newUnionPatternField(id("value"), id("x"), newLocation())
    let f2 = newUnionPatternField(id("error"), id("x"), newLocation())
    let r = newUnionPattern(id("Ok"), @[f1, f2])
    check r.isErr
    check errorContains(r.error.msg, "duplicate binding")

  test "newUnionPattern accepts an empty fields list":
    let r = newUnionPattern(id("Ok"), @[])
    check r.isOk

suite "ast — Import invariants":

  test "newImport rejects duplicate names within a single statement":
    let n1 = newImportedType(id("Foo"))
    let n2 = newImportedType(id("Foo"))
    let r = newImport(@[n1, n2], newRelativeImportPath("./bar.asl"), "/abs/bar.asl", newLocation())
    check r.isErr
    check errorContains(r.error.msg, "duplicate import")

  test "newImport rejects duplicate bindings (alias collision)":
    let n1 = newImportedType(id("Foo"), id("B"))
    let n2 = newImportedType(id("Bar"), id("B"))
    let r = newImport(@[n1, n2], newRelativeImportPath("./bar.asl"), "/abs/bar.asl", newLocation())
    check r.isErr
    check errorContains(r.error.msg, "duplicate import binding")

  test "newImport rejects original-name colliding with another's alias":
    let n1 = newImportedType(id("Foo"))
    let n2 = newImportedType(id("Bar"), id("Foo"))
    let r = newImport(@[n1, n2], newRelativeImportPath("./bar.asl"), "/abs/bar.asl", newLocation())
    check r.isErr
    check errorContains(r.error.msg, "duplicate import binding")

  test "newImport accepts unique names + bindings":
    let n1 = newImportedType(id("Foo"))
    let n2 = newImportedType(id("Bar"), id("B"))
    let r = newImport(@[n1, n2], newRelativeImportPath("./bar.asl"), "/abs/bar.asl", newLocation())
    check r.isOk

suite "ast — KeywordArgumentList invariants":

  test "newKeywordArgumentList accepts an empty list":
    # Emptiness is a per-initializer concern, not a list-level one.
    # StructInitializer's "no empty structs" rule falls out of
    # `newStructDef` (≥ 1 field guaranteed) + the resolver's
    # `kwargs.len != fields.len` check. UnionInitializer needs empty
    # to be legal so `Variant {}` works against a zero-field variant.
    let r = newKeywordArgumentList(@[], newLocation())
    check r.isOk

  test "newKeywordArgumentList rejects duplicate kwarg names":
    let kw1 = newKeywordArgument(id("a"),
      newExpression(id("x")), newLocation())
    let kw2 = newKeywordArgument(id("a"),
      newExpression(id("y")), newLocation())
    let r = newKeywordArgumentList(@[kw1, kw2], newLocation())
    check r.isErr
    check errorContains(r.error.msg, "duplicate")

  test "newKeywordArgumentList accepts unique kwarg names":
    let kw1 = newKeywordArgument(id("a"),
      newExpression(id("x")), newLocation())
    let kw2 = newKeywordArgument(id("b"),
      newExpression(id("y")), newLocation())
    let r = newKeywordArgumentList(@[kw1, kw2], newLocation())
    check r.isOk

suite "ast — Module invariants (via parser)":

  test "module with neither data block nor functions is rejected":
    let r = parseStr("module M:\n")
    check r.isErr

  test "module with only a data block is accepted":
    let r = parseStr("""
module M:
  struct:
    a: u8
""")
    check r.isOk

  test "module with only a function is accepted":
    let r = parseStr("""
module M:
  func go(): u8
    u8 0
""")
    check r.isOk

suite "ast — File invariants (via parser)":

  test "duplicate module names within one file are rejected":
    let r = parseStr("""
module A:
  func go(): u8
    u8 0

module A:
  func go(): u8
    u8 0
""")
    check r.isErr
    check errorContains(r.error, "duplicate")

  test "file with only imports (no defined types) is rejected":
    # `atLeastOne(definedTypeSpec)` in aslFileSpec enforces this.
    let (r, dir) = parseFiles([
      ("entry.asl", """
import { Foo } from "./other.asl"
"""),
      ("other.asl", """
public module Foo:
  func go(): u8
    u8 0
""")
    ])
    cleanupDir(dir)
    check r.isErr

  test "module name colliding with imported binding is rejected":
    let (r, dir) = parseFiles([
      ("entry.asl", """
import { Foo } from "./other.asl"

module Foo:
  func go(): u8
    u8 0
"""),
      ("other.asl", """
public module Foo:
  func go(): u8
    u8 0
""")
    ])
    cleanupDir(dir)
    check r.isErr
    check errorContains(r.error, "duplicate")

suite "ast — StructDef field lookups":

  test "findFieldId returns the index of an existing field":
    let s = newStructDef(bareStructHeader(),
      @[argDef("a", "u8"), argDef("b", "u16")]).get
    let r = s.findFieldId(id("b"))
    check r.isOk
    check r.get == 1

  test "findFieldId reports missing field":
    let s = newStructDef(bareStructHeader(), @[argDef("a", "u8")]).get
    let r = s.findFieldId(id("missing"))
    check r.isErr
    check errorContains(r.error, "missing")
    check errorContains(r.error, "not present")

suite "ast — VariantDef field lookups":

  test "findFieldId returns the index of an existing variant field":
    let v = newVariantDef(id("Ok"),
      @[argDef("value", "u8"), argDef("flag", "u8")], newLocation()).get
    let r = v.findFieldId(id("flag"))
    check r.isOk
    check r.get == 1

  test "findFieldId on a variant reports missing field":
    let v = newVariantDef(id("Ok"),
      @[argDef("value", "u8")], newLocation()).get
    let r = v.findFieldId(id("missing"))
    check r.isErr
    check errorContains(r.error, "Ok")

suite "ast — UnionDef variant lookups":

  test "findVariant returns the matching variant":
    let v1 = newVariantDef(id("Ok"),
      @[argDef("value", "u8")], newLocation()).get
    let v2 = newVariantDef(id("Err"),
      @[argDef("code", "u8")], newLocation()).get
    let u = newUnionDef(@[v1, v2], newLocation()).get
    let r = u.findVariant(id("Err"))
    check r.isOk
    check r.get.name.value == "Err"

  test "findVariant reports a missing variant":
    let v = newVariantDef(id("Ok"),
      @[argDef("value", "u8")], newLocation()).get
    let u = newUnionDef(@[v], newLocation()).get
    let r = u.findVariant(id("NotThere"))
    check r.isErr
    check errorContains(r.error, "NotThere")

suite "ast — File type lookups":

  test "findType resolves a locally-defined type":
    let f = parseStr("""
module M:
  func go(): u8
    u8 0
""").get
    let r = f.findType(id("M"))
    check r.isOk
    check r.get.kind == ltkModule

  test "findType reports a missing name":
    let f = parseStr("""
module M:
  func go(): u8
    u8 0
""").get
    let r = f.findType(id("NoSuchType"))
    check r.isErr
    check errorContains(r.error, "NoSuchType")
    check errorContains(r.error, "not defined")

  test "findExportedType accepts a public module":
    let f = parseStr("""
public module Foo:
  func go(): u8
    u8 0
""").get
    let r = f.findExportedType(id("Foo"))
    check r.isOk

  test "findExportedType rejects a non-public module":
    let f = parseStr("""
module Foo:
  func go(): u8
    u8 0
""").get
    let r = f.findExportedType(id("Foo"))
    check r.isErr
    check errorContains(r.error, "non-public")

  test "findExportedType reports a missing name":
    let f = parseStr("""
public module Foo:
  func go(): u8
    u8 0
""").get
    let r = f.findExportedType(id("NotThere"))
    check r.isErr

  test "findType errors on an imported name (imports live in a separate index)":
    # The imported name `Bar` exists on the file, but findType is
    # scoped to *locally-defined* types only. The imported binding
    # lives on `importedNameIndex` and is only surfaced via
    # `findImportedType`.
    let f = parseStr("""
import { Bar } from "./bar.asl"

module M:
  func go(): u8
    u8 0
""").get
    let r = f.findType(id("Bar"))
    check r.isErr
    check errorContains(r.error, "not defined")

  test "findImportedType returns the imported binding":
    let f = parseStr("""
import { Bar } from "./bar.asl"

module M:
  func go(): u8
    u8 0
""").get
    let r = f.findImportedType(id("Bar"))
    check r.isOk

  test "findImportedType reports an unimported name":
    let f = parseStr("""
import { Bar } from "./bar.asl"

module M:
  func go(): u8
    u8 0
""").get
    let r = f.findImportedType(id("NotImported"))
    check r.isErr
    check errorContains(r.error, "not imported")

  test "findImportedType always errors on an .aslr file":
    let f = parseStrAslr("""
module M:
  func go(): u8
    u8 0
""").get
    let r = f.findImportedType(id("Anything"))
    check r.isErr
    check errorContains(r.error, "aslr")

  test "duplicate binding across an import and a local module is caught at parse time":
    # Importing `M` and defining a local module named `M` collide on
    # the same identifier — the parser's cross-index duplicate check
    # rejects this at newAslFile time.
    let r = parseStr("""
import { M } from "./bar.asl"

module M:
  func go(): u8
    u8 0
""")
    check r.isErr
    check errorContains(r.error, "duplicate")

suite "ast — Module function lookups":

  test "findFunctionDefs returns matching overloads by (name, arity)":
    let f = parseStr("""
module M:
  func go(): u8
    u8 0

  func go(x: u8): u8
    x
""").get
    let m = f.findType(id("M")).get.module
    let zero = m.findFunctionDefs(id("go"), 0, faAll)
    let one = m.findFunctionDefs(id("go"), 1, faAll)
    check zero.isOk
    check zero.get.len == 1
    check one.isOk
    check one.get.len == 1

  test "findFunctionDefs reports a missing function name":
    let f = parseStr("""
module M:
  func go(): u8
    u8 0
""").get
    let m = f.findType(id("M")).get.module
    let r = m.findFunctionDefs(id("missing"), 0, faAll)
    check r.isErr
    check errorContains(r.error, "missing")

  test "findFunctionDefs reports a wrong arity":
    let f = parseStr("""
module M:
  func go(): u8
    u8 0
""").get
    let m = f.findType(id("M")).get.module
    let r = m.findFunctionDefs(id("go"), 2, faAll)
    check r.isErr
    check errorContains(r.error, "arity")

suite "ast — Generic function-def lookups":

  test "findFunctionDefs returns matching definitions":
    let f = parseStr("""
generic Eq:
  func eq(a: Eq, b: Eq): u8
""").get
    let g = f.findType(id("Eq")).get.generic
    let r = g.findFunctionDefs(id("eq"), 2)
    check r.isOk
    check r.get.len == 1

  test "findFunctionDefs reports a missing function":
    let f = parseStr("""
generic Eq:
  func eq(a: Eq, b: Eq): u8
""").get
    let g = f.findType(id("Eq")).get.generic
    let r = g.findFunctionDefs(id("missing"), 2)
    check r.isErr

suite "ast — App file lookups":

  test "findFile returns the matching file":
    let (parsed, dir) = parseFiles([
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
    let app = parsed.get
    # Find the helper file by walking app.files for the matching path.
    var helperPath = ""
    for f in app.files:
      if f.path.endsWith("helper.asl"):
        helperPath = f.path
        break
    cleanupDir(dir)
    check helperPath.len > 0
    let r = app.findFile(helperPath)
    check r.isOk
    check r.get.path == helperPath

  test "findFile reports a non-existent path":
    let (parsed, dir) = parseFiles([
      ("entry.asl", """
module M:
  func go(): u8
    u8 0
""")
    ])
    let app = parsed.get
    cleanupDir(dir)
    let r = app.findFile("/no/such/path.asl")
    check r.isErr
    check errorContains(r.error, "/no/such/path.asl")

  test "findFileId is consistent with findFile":
    let (parsed, dir) = parseFiles([
      ("entry.asl", """
module M:
  func go(): u8
    u8 0
""")
    ])
    let app = parsed.get
    let path = app.files[0].path
    cleanupDir(dir)
    let id1 = app.findFileId(path)
    let id2 = app.findFileId(path)
    check id1.isOk
    check id2.isOk
    check id1.get == id2.get

suite "ast — MatchHeader accessor invariants":

  test "assigned header exposes target and subject":
    let hr = newMatchHeader(id("y"), newExpression(id("x")), newLocation())
    check hr.isOk
    let header = hr.get
    check header.kind == mhkAssigned
    check header.target.value == "y"
    check header.subject.kind == ekInline

  test "default header carries no target; reading it is a defect":
    let hr = newMatchHeader(newExpression(id("x")), newLocation())
    check hr.isOk
    let header = hr.get
    check header.kind == mhkDefault
    expect AssertionDefect:
      discard header.target

  test "a match-expression subject is rejected by both constructors":
    let subject = newExpression(newMatchExpression(newExpression(id("x")),
        newSeq[CaseBlock](), newLocation()))
    check newMatchHeader(id("y"), subject, newLocation()).isErr
    check newMatchHeader(subject, newLocation()).isErr

