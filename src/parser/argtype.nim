import strformat, sequtils, strutils, tables, results, options

import ../tokenizer/main as tokenizer

import parser
import error

import identifiers

# ============================================================
# ArgumentType (self-recursive: List[Map[String, Int]])
# ============================================================

type ArgumentType* = ref object
  root: Identifier
  impls: seq[ArgumentType]

proc newArgumentType*(root: Identifier): ArgumentType =
  ArgumentType(root: root)

proc newArgumentType*(root: Identifier, impls: seq[ArgumentType]): ArgumentType =
  ArgumentType(root: root, impls: impls)

proc loc*(a: ArgumentType): Location = a.root.loc
proc root*(a: ArgumentType): Identifier = a.root
proc impls*(a: ArgumentType): seq[ArgumentType] = a.impls

proc asl*(argType: ArgumentType): string =
  var content = argType.root.asl
  let impls = argType.impls.mapIt(asl(it)).join(", ")
  if impls != "": content.add(fmt"[{impls}]")
  return content

# Argument-type sugar: a trailing `!` on an argument type expands to
# `Status[<argType>]`. Parsed uniformly here so every argument-type
# position picks it up — function args, return types, kwarg field
# types, and the initializer type prefix all route through this parser.
#
# Nesting binds tight: `!` attaches to the type it immediately follows.
#   T!            -> Status[T]
#   Array[u32]!   -> Status[Array[u32]]
#   Array[u32!]   -> Array[Status[u32]]
#   Status[u32]!  -> Status[Status[u32]]     (syntactically legal)
#
# The sugar collapses at parse time. Downstream (resolver, analyzer)
# sees a plain `Status[...]` ArgumentType — no distinct AST variant,
# no separate handling.
#
# When updating this sugar (different suffix, different wrapper type,
# arity checks, additional post-fix operators, etc.), touch:
#   - The `maybeBanged` block below.
#   - grammar.md — the ArgumentType production.
#   - validations.md — §4.8 (argument-type shorthand).
#   - tests/test_grammar.nim — the "argument type shorthand" suite.
#   - tests/test_analyzer.nim — end-to-end sugar tests.
#
# `argumentTypeConsumer` is self-referential: type params like
# `Map[String, List[Int]]` contain nested argument types. Nim's
# `proc` declarations handle recursion natively (a proc body can call
# the enclosing proc by name).

proc argumentTypeConsumer(parser: Parser): Result[ArgumentType, ParserError]
let argumentTypeSpec* = newSpec[ArgumentType]("argument type", argumentTypeConsumer)

proc argumentTypeConsumer(parser: Parser): Result[ArgumentType, ParserError] =
  let rootIdent = ? parser.expect(identifierSpec)
  # Optional `[T, U, ...]` type params — argumentTypeConsumer recurses
  # into itself for each element. A leading `[` commits to the bracketed
  # list; absence of `[` means no type params.
  let maybeImpls = ? parser.expect(argumentTypeSpec.squareBracketList(allowEmpty = false).optional())
  let maybeBanged = ? parser.expect(bangSpec.optional())

  let argType =
    if maybeImpls.isSome:
      newArgumentType(rootIdent, maybeImpls.get[0])
    else:
      newArgumentType(rootIdent)

  if maybeBanged.isSome:
    let statusIdent = ? newIdentifier("Status", maybeBanged.get.loc)
    ok(newArgumentType(statusIdent, @[argType]))
  else:
    ok(argType)

# ============================================================
# ArgumentDef (name: ArgumentType)
# ============================================================

type ArgumentDef* = ref object
  name: Identifier
  argType: ArgumentType
  loc: Location

proc newArgumentDef*(name: Identifier, argType: ArgumentType): ArgumentDef =
  ArgumentDef(name: name, argType: argType)

proc loc*(argDef: ArgumentDef): Location = argDef.name.loc
proc name*(argDef: ArgumentDef): Identifier = argDef.name
proc argType*(argDef: ArgumentDef): ArgumentType = argDef.argType

proc asl*(argDef: ArgumentDef): string =
  fmt"{argDef.name.asl}: {argDef.argType.asl}"

proc argumentDefConsumer(parser: Parser): Result[ArgumentDef, ParserError] =
  let name = ? parser.expect(identifierSpec)
  discard ? parser.expect(spaceSpec.optional())
  discard ? parser.expect(":")
  discard ? parser.expect(spaceSpec.optional())
  let argType = ? parser.expect(argumentTypeSpec)
  ok(newArgumentDef(name, argType))

let argumentDefSpec* = newSpec[ArgumentDef]("argument_definition", argumentDefConsumer)

# ============================================================
# ArgumentDefList ((name: T, name: T, ...))
# ============================================================

type ArgumentDefList* = ref object
  argDefs: seq[ArgumentDef]
  argNameIndex: Table[Identifier, int]
  loc: Location

proc buildArgumentNameIndex(argDefs: seq[ArgumentDef]): Result[Table[Identifier, int], ParserError] =
  var argNameIndex: Table[Identifier, int]
  for index, argDef in argDefs:
    if argDef.name in argNameIndex:
      let prev = argDefs[argNameIndex[argDef.name]]
      let msg = fmt"duplicate argument encountered, see previous declaration at {prev.loc}"
      return err(newParserError(msg, argDef.loc))
    argNameIndex[argDef.name] = index
  ok(argNameIndex)

proc newArgumentDefList*(argDefs: seq[ArgumentDef], loc: Location): Result[ArgumentDefList, ParserError] =
  let argNameIndex = ? buildArgumentNameIndex(argDefs)
  ok(ArgumentDefList(argDefs: argDefs, argNameIndex: argNameIndex, loc: loc))

proc newArgumentDefList*(items: (seq[ArgumentDef], Location)): Result[ArgumentDefList, ParserError] =
  newArgumentDefList(items[0], items[1])

proc argDefs*(argDefList: ArgumentDefList): seq[ArgumentDef] = argDefList.argDefs
proc arity*(argDefList: ArgumentDefList): int = argDefList.argDefs.len

proc asl*(argDefList: ArgumentDefList): string =
  let content = argDefList.argDefs.mapIt(asl(it)).join(", ")
  return fmt"({content})"

let argumentDefListSpec* = argumentDefSpec.parenthesisList().map(newArgumentDefList)