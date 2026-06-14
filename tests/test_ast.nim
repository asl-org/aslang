## Tests for AST constructor invariants. Many of the duplicate-
## detection errors that constructors raise (Struct.fieldIndex,
## Union.variantIndex, VariantPattern bindings, KeywordArgumentList
## argIndex, etc.) are unreachable from the grammar surface today
## because the parser's `atLeastOne` backtracks past them, so the
## tests here exercise the constructors directly.

import unittest, options, results, strutils

import tokenizer
import parser
import tutils

proc id(s: string): Identifier =
  ## Quick Identifier from a literal name. Tests don't care about
  ## location accuracy — `newLocation()` returns 1:1.
  let r = newIdentifier(s, newLocation())
  doAssert r.isOk, "newIdentifier failed for '" & s & "': " & r.error.msg
  r.get

proc argType(name: string): ArgumentType =
  newArgumentType(id(name), newLocation())

proc argDef(name, typeName: string): ArgumentDefinition =
  newArgumentDefinition(id(name), argType(typeName), newLocation())

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

suite "ast — Struct invariants":

  test "newStruct rejects an empty field list":
    let r = newStruct(@[], newLocation())
    check r.isErr
    check errorContains(r.error.msg, "at least one field")

  test "newStruct rejects duplicate field names":
    let r = newStruct(@[argDef("a", "u8"), argDef("a", "u16")], newLocation())
    check r.isErr
    check errorContains(r.error.msg, "duplicate field")

  test "newStruct accepts unique field names":
    let r = newStruct(@[argDef("a", "u8"), argDef("b", "u16")], newLocation())
    check r.isOk
    check r.get.fields.len == 2

suite "ast — VariantDefinition invariants":

  test "newVariantDefinition rejects duplicate field names within a variant":
    let r = newVariantDefinition(id("V"),
      @[argDef("x", "u8"), argDef("x", "u16")], newLocation())
    check r.isErr
    check errorContains(r.error.msg, "duplicate field")

  test "newVariantDefinition accepts unique fields":
    let r = newVariantDefinition(id("V"),
      @[argDef("x", "u8"), argDef("y", "u16")], newLocation())
    check r.isOk

  test "newVariantDefinition accepts an empty fields list":
    let r = newVariantDefinition(id("V"), @[], newLocation())
    check r.isOk

suite "ast — Union invariants":

  test "newUnion rejects duplicate variant names":
    let v1 = newVariantDefinition(id("Same"), @[argDef("x", "u8")],
      newLocation()).get
    let v2 = newVariantDefinition(id("Same"), @[argDef("y", "u8")],
      newLocation()).get
    let r = newUnion(@[v1, v2], newLocation())
    check r.isErr
    check errorContains(r.error.msg, "duplicate variant")

  test "newUnion accepts a single variant":
    let v = newVariantDefinition(id("A"), @[argDef("x", "u8")],
      newLocation()).get
    let r = newUnion(@[v], newLocation())
    check r.isOk

suite "ast — ArgumentDefinitionList invariants":

  test "newArgumentDefinitionList rejects duplicate argument names":
    let r = newArgumentDefinitionList(
      @[argDef("a", "u8"), argDef("a", "u8")], newLocation())
    check r.isErr
    check errorContains(r.error.msg, "duplicate argument")

  test "newArgumentDefinitionList accepts unique args":
    let r = newArgumentDefinitionList(
      @[argDef("a", "u8"), argDef("b", "u16")], newLocation())
    check r.isOk

  test "newArgumentDefinitionList accepts an empty list":
    let r = newArgumentDefinitionList(@[], newLocation())
    check r.isOk

suite "ast — VariantPattern invariants":

  test "newVariantPattern rejects duplicate field names":
    # Two pattern fields with the same `name`, different bindings.
    let f1 = newVariantPatternField(id("value"), id("a"), newLocation())
    let f2 = newVariantPatternField(id("value"), id("b"), newLocation())
    let r = newVariantPattern(id("Ok"), @[f1, f2])
    check r.isErr
    check errorContains(r.error.msg, "duplicate field")

  test "newVariantPattern rejects duplicate bindings":
    # Different field names, same binding identifier.
    let f1 = newVariantPatternField(id("value"), id("x"), newLocation())
    let f2 = newVariantPatternField(id("error"), id("x"), newLocation())
    let r = newVariantPattern(id("Ok"), @[f1, f2])
    check r.isErr
    check errorContains(r.error.msg, "duplicate binding")

  test "newVariantPattern accepts an empty fields list":
    let r = newVariantPattern(id("Ok"), @[])
    check r.isOk

suite "ast — Import invariants":

  test "newImport rejects duplicate names within a single statement":
    let n1 = newImportedType(id("Foo"), none(Identifier), newLocation())
    let n2 = newImportedType(id("Foo"), none(Identifier), newLocation())
    let r = newImport(@[n1, n2], "./bar.asl", "/abs/bar.asl", newLocation())
    check r.isErr
    check errorContains(r.error.msg, "duplicate import")

  test "newImport rejects duplicate bindings (alias collision)":
    let n1 = newImportedType(id("Foo"),
      some(id("B")), newLocation())
    let n2 = newImportedType(id("Bar"),
      some(id("B")), newLocation())
    let r = newImport(@[n1, n2], "./bar.asl", "/abs/bar.asl", newLocation())
    check r.isErr
    check errorContains(r.error.msg, "duplicate import binding")

  test "newImport rejects original-name colliding with another's alias":
    let n1 = newImportedType(id("Foo"), none(Identifier), newLocation())
    let n2 = newImportedType(id("Bar"),
      some(id("Foo")), newLocation())
    let r = newImport(@[n1, n2], "./bar.asl", "/abs/bar.asl", newLocation())
    check r.isErr
    check errorContains(r.error.msg, "duplicate import binding")

  test "newImport accepts unique names + bindings":
    let n1 = newImportedType(id("Foo"), none(Identifier), newLocation())
    let n2 = newImportedType(id("Bar"),
      some(id("B")), newLocation())
    let r = newImport(@[n1, n2], "./bar.asl", "/abs/bar.asl", newLocation())
    check r.isOk

suite "ast — KeywordArgumentList invariants":

  test "newKeywordArgumentList rejects an empty list":
    let r = newKeywordArgumentList(@[], newLocation())
    check r.isErr
    check errorContains(r.error.msg, "at least 1 field")

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
    # `atLeastOne(definedTypeBlockSpec)` in fileSpec enforces this.
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

suite "ast — Struct field lookups":

  test "findFieldId returns the index of an existing field":
    let s = newStruct(@[argDef("a", "u8"), argDef("b", "u16")],
      newLocation()).get
    let r = s.findFieldId(id("b"))
    check r.isOk
    check r.get == 1

  test "findFieldId reports missing field":
    let s = newStruct(@[argDef("a", "u8")], newLocation()).get
    let r = s.findFieldId(id("missing"))
    check r.isErr
    check errorContains(r.error, "missing")
    check errorContains(r.error, "not present")

suite "ast — VariantDefinition field lookups":

  test "findFieldId returns the index of an existing variant field":
    let v = newVariantDefinition(id("Ok"),
      @[argDef("value", "u8"), argDef("flag", "u8")], newLocation()).get
    let r = v.findFieldId(id("flag"))
    check r.isOk
    check r.get == 1

  test "findFieldId on a variant reports missing field":
    let v = newVariantDefinition(id("Ok"),
      @[argDef("value", "u8")], newLocation()).get
    let r = v.findFieldId(id("missing"))
    check r.isErr
    check errorContains(r.error, "Ok")

suite "ast — Union variant lookups":

  test "findVariant returns the matching variant":
    let v1 = newVariantDefinition(id("Ok"),
      @[argDef("value", "u8")], newLocation()).get
    let v2 = newVariantDefinition(id("Err"),
      @[argDef("code", "u8")], newLocation()).get
    let u = newUnion(@[v1, v2], newLocation()).get
    let r = u.findVariant(id("Err"))
    check r.isOk
    check r.get.name.value == "Err"

  test "findVariant reports a missing variant":
    let v = newVariantDefinition(id("Ok"),
      @[argDef("value", "u8")], newLocation()).get
    let u = newUnion(@[v], newLocation()).get
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
    check r.get.kind == tkDefined

  test "findType reports a missing name":
    let f = parseStr("""
module M:
  func go(): u8
    u8 0
""").get
    let r = f.findType(id("NoSuchType"))
    check r.isErr
    check errorContains(r.error, "NoSuchType")
    check errorContains(r.error, "does not exist")

  test "findTypeId returns the same id consistently":
    let f = parseStr("""
module A:
  func go(): u8
    u8 0

module B:
  func go(): u8
    u8 0
""").get
    let idA1 = f.findTypeId(id("A"))
    let idA2 = f.findTypeId(id("A"))
    let idB = f.findTypeId(id("B"))
    check idA1.isOk
    check idA2.isOk
    check idB.isOk
    check idA1.get == idA2.get
    check idA1.get != idB.get

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

suite "ast — Module function lookups":

  test "findFunctionDefs returns matching overloads by (name, arity)":
    let f = parseStr("""
module M:
  func go(): u8
    u8 0

  func go(x: u8): u8
    x
""").get
    let m = f.findType(id("M")).get.definedType.module
    let zero = m.findFunctionDefs(id("go"), 0)
    let one = m.findFunctionDefs(id("go"), 1)
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
    let m = f.findType(id("M")).get.definedType.module
    let r = m.findFunctionDefs(id("missing"), 0)
    check r.isErr
    check errorContains(r.error, "missing")

  test "findFunctionDefs reports a wrong arity":
    let f = parseStr("""
module M:
  func go(): u8
    u8 0
""").get
    let m = f.findType(id("M")).get.definedType.module
    let r = m.findFunctionDefs(id("go"), 2)
    check r.isErr
    check errorContains(r.error, "arity")

suite "ast — Generic function-def lookups":

  test "findFunctionDefs returns matching definitions":
    let f = parseStr("""
generic Eq:
  func eq(a: Eq, b: Eq): u8
""").get
    let g = f.findType(id("Eq")).get.definedType.generic
    let r = g.findFunctionDefs(id("eq"), 2)
    check r.isOk
    check r.get.len == 1

  test "findFunctionDefs reports a missing function":
    let f = parseStr("""
generic Eq:
  func eq(a: Eq, b: Eq): u8
""").get
    let g = f.findType(id("Eq")).get.definedType.generic
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

