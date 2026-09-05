## Phase-A function cluster — `AnalyzedFunctionDef` (a resolver function
## definition + its fully-analyzed args/return, the phase-B overload &
## body-typing input) plus the function wrappers: `AnalyzedDefExtern-
## Function` / `AnalyzedDefUserFunction` pair the resolver function with
## its `AnalyzedFunctionDef`, and the tagged `AnalyzedDefFunction`
## (adfkExtern / adfkUser) gives `AnalyzedDefModule.functions` one shape
## with uniform `def` / `name` / `arity` accessors.

import strformat, strutils, sequtils, hashes, sets

import resolver/index as resolver
import argtype
import statement

# ---- AnalyzedFunctionDef ----
# A resolver function definition paired with its fully-analyzed argument
# definitions and return type. Produced by phase-A when walking a
# module's/generic's function list; consumed by phase-B overload
# resolution + body-typing without re-analysis.

type AnalyzedFunctionDef* = ref object
  resolved: ResolvedFunctionDef
  args: seq[AnalyzedArgumentDef]
  returns: AnalyzedArgumentType

proc newAnalyzedFunctionDef*(resolved: ResolvedFunctionDef,
    args: seq[AnalyzedArgumentDef],
    returns: AnalyzedArgumentType): AnalyzedFunctionDef =
  AnalyzedFunctionDef(resolved: resolved, args: args, returns: returns)

proc resolved*(f: AnalyzedFunctionDef): ResolvedFunctionDef = f.resolved
proc public*(f: AnalyzedFunctionDef): bool = f.resolved.public
proc name*(f: AnalyzedFunctionDef): Identifier = f.resolved.name
proc loc*(f: AnalyzedFunctionDef): Location = f.resolved.loc
proc arity*(f: AnalyzedFunctionDef): int = f.args.len
proc args*(f: AnalyzedFunctionDef): seq[AnalyzedArgumentDef] = f.args
proc returns*(f: AnalyzedFunctionDef): AnalyzedArgumentType = f.returns
proc generics*(f: AnalyzedFunctionDef): seq[ResolvedGeneric] =
  var generics: OrderedSet[ResolvedGeneric]
  for arg in f.args:
    for g in arg.generics:
      generics.incl(g)
  return generics.toSeq

proc asl*(f: AnalyzedFunctionDef): string =
  var args: seq[string]
  for arg in f.args:
    args.add(arg.asl)
  "func " & f.name.asl & "(" & args.join(", ") & "): " & f.returns.asl

proc filter*(defs: seq[AnalyzedFunctionDef], access: FunctionAccess): seq[AnalyzedFunctionDef] =
  case access:
  of faAll: defs
  of faPublic: defs.filterIt(it.public)

proc hash*(def: AnalyzedFunctionDef): Hash = def.resolved.hash
proc `==`*(a, b: AnalyzedFunctionDef): bool = a.hash == b.hash

# ---- function wrappers ----

type AnalyzedExternFunction* = ref object
  resolved: ResolvedExternFunction
  def: AnalyzedFunctionDef

proc newAnalyzedExternFunction*(resolved: ResolvedExternFunction, def: AnalyzedFunctionDef): AnalyzedExternFunction =
  AnalyzedExternFunction(resolved: resolved, def: def)

proc loc*(function: AnalyzedExternFunction): Location = function.resolved.loc
proc ffi*(function: AnalyzedExternFunction): string = function.resolved.ffi
proc name*(function: AnalyzedExternFunction): Identifier = function.resolved.name
proc arity*(function: AnalyzedExternFunction): int = function.resolved.arity
proc def*(function: AnalyzedExternFunction): AnalyzedFunctionDef = function.def
proc generics*(function: AnalyzedExternFunction): seq[ResolvedGeneric] = function.def.generics

type AnalyzedDefUserFunction* = ref object
  resolved: ResolvedUserFunction
  def: AnalyzedFunctionDef
  statements: seq[AnalyzedDefStatement]

proc newAnalyzedDefUserFunction*(resolved: ResolvedUserFunction, def: AnalyzedFunctionDef, statements: seq[AnalyzedDefStatement]): AnalyzedDefUserFunction =
  AnalyzedDefUserFunction(resolved: resolved, def: def, statements: statements)

proc entry*(function: AnalyzedDefUserFunction): bool = function.resolved.entry
proc loc*(function: AnalyzedDefUserFunction): Location = function.resolved.loc
proc name*(function: AnalyzedDefUserFunction): Identifier = function.resolved.name
proc arity*(function: AnalyzedDefUserFunction): int = function.resolved.arity
proc def*(function: AnalyzedDefUserFunction): AnalyzedFunctionDef = function.def
proc statements*(function: AnalyzedDefUserFunction): seq[AnalyzedDefStatement] = function.statements

type
  AnalyzedDefFunctionKind* = enum
    adfkExtern, adfkUser, adfkGenerated
  AnalyzedDefFunction* = ref object
    case kind: AnalyzedDefFunctionKind
    of adfkExtern: extern: AnalyzedExternFunction
    of adfkUser: user: AnalyzedDefUserFunction
    of adfkGenerated: generated: AnalyzedFunctionDef

proc newAnalyzedDefFunction*(extern: AnalyzedExternFunction): AnalyzedDefFunction =
  AnalyzedDefFunction(kind: adfkExtern, extern: extern)

proc newAnalyzedDefFunction*(user: AnalyzedDefUserFunction): AnalyzedDefFunction =
  AnalyzedDefFunction(kind: adfkUser, user: user)

proc newAnalyzedDefFunction*(generated: AnalyzedFunctionDef): AnalyzedDefFunction =
  AnalyzedDefFunction(kind: adfkGenerated, generated: generated)

proc kind*(function: AnalyzedDefFunction): AnalyzedDefFunctionKind = function.kind
proc extern*(function: AnalyzedDefFunction): AnalyzedExternFunction =
  assert function.kind == adfkExtern,
    fmt"AnalyzedDefFunction.extern accessed but kind is {function.kind}"
  function.extern
proc user*(function: AnalyzedDefFunction): AnalyzedDefUserFunction =
  assert function.kind == adfkUser,
    fmt"AnalyzedDefFunction.user accessed but kind is {function.kind}"
  function.user
proc generated*(function: AnalyzedDefFunction): AnalyzedFunctionDef =
  assert function.kind == adfkGenerated,
    fmt"AnalyzedDefFunction.generated accessed but kind is {function.kind}"
  function.generated

proc def*(function: AnalyzedDefFunction): AnalyzedFunctionDef =
  case function.kind:
  of adfkExtern: function.extern.def
  of adfkUser: function.user.def
  of adfkGenerated: function.generated

proc name*(function: AnalyzedDefFunction): Identifier =
  case function.kind:
  of adfkExtern: function.extern.name
  of adfkUser: function.user.name
  of adfkGenerated: function.generated.name

proc arity*(function: AnalyzedDefFunction): int =
  case function.kind:
  of adfkExtern: function.extern.arity
  of adfkUser: function.user.arity
  of adfkGenerated: function.def.arity

proc entry*(function: AnalyzedDefFunction): bool =
  case function.kind:
  of adfkUser: function.user.entry
  of adfkExtern, adfkGenerated: false
