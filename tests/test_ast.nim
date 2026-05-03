## Tests for AST constructor invariants. Many of the duplicate-
## detection errors that constructors raise (Struct.fieldIndex,
## Union.variantIndex, VariantPattern bindings, KeywordArgumentList
## argIndex, etc.) are unreachable from the grammar surface today
## because the parser's `atLeastOne` backtracks past them, so the
## tests here exercise the constructors directly.

import unittest, options, results

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

  test "identifier longer than 256 chars is rejected at construction":
    var name = ""
    for i in 0..256: name.add('a')
    let r = newIdentifier(name, newLocation())
    check r.isErr
    check errorContains(r.error.msg, "max length 256")

  test "identifier starting with __asl is rejected at construction":
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
    let r = newVariantPattern(id("Ok"), @[f1, f2], newLocation())
    check r.isErr
    check errorContains(r.error.msg, "duplicate field")

  test "newVariantPattern rejects duplicate bindings":
    # Different field names, same binding identifier.
    let f1 = newVariantPatternField(id("value"), id("x"), newLocation())
    let f2 = newVariantPatternField(id("error"), id("x"), newLocation())
    let r = newVariantPattern(id("Ok"), @[f1, f2], newLocation())
    check r.isErr
    check errorContains(r.error.msg, "duplicate binding")

  test "newVariantPattern accepts an empty fields list":
    let r = newVariantPattern(id("Ok"), @[], newLocation())
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

  test "self-import is rejected":
    let (r, dir) = parseFiles([
      ("entry.asl", """
import { Foo } from "./entry.asl"

module Bar:
  func go(): u8
    u8 0
""")
    ])
    cleanupDir(dir)
    check r.isErr
    check errorContains(r.error, "importing the source file in itself")
