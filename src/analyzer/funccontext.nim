## AnalyzedFunctionContext — per-function variable scope
## (Identifier -> AnalyzedArgumentType) for body analysis. Variables
## have no identity beyond their name, so name keying is correct
## here (unlike the type scopes, which key by identity).
##
## Seeded from a pre-analyzed AnalyzedFunctionDef's args;
## extended via the `update` overloads — one absorbs a statement's
## introduced binding, one a case pattern's bindings. Case blocks
## copy the scope by plain assignment (Table is a value type), so
## sibling arms never see each other's bindings.

import options, strformat, tables

import ./defanalyzer
import ./binding
import ./statement
import ./casepattern

# Stores the whole binding (name, argType, impls) per variable, so a
# variable used as a match subject carries the impl map that
# concretizes a pulled variant field. Function args have no inferred
# map (their declared type is what it is) → empty.
type AnalyzedFunctionContext* = Table[Identifier, AnalyzedBinding]

proc newAnalyzedFunctionContext*(def: AnalyzedFunctionDef): AnalyzedFunctionContext =
  var funcCtx: AnalyzedFunctionContext
  for argDef in def.args:
    assert(argDef.name notin funcCtx, fmt"{argDef.loc}: [BUG] duplicate function argument names encountered")
    funcCtx[argDef.name] = (name: argDef.name, argType: argDef.argType, impls: default(GenericImplMap))
  return funcCtx

proc update*(funcCtx: var AnalyzedFunctionContext, statement: AnalyzedStatement): AnalyzedFunctionContext =
  if statement.arg.isSome:
    let arg = statement.arg.get
    funcCtx[arg.name] = arg
  return funcCtx

proc update*(funcCtx: var AnalyzedFunctionContext, pattern: AnalyzedCasePattern): AnalyzedFunctionContext =
  for binding in pattern.bindings:
    funcCtx[binding.name] = binding
  return funcCtx