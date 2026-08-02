## AnalyzedFunctionContext — per-function variable scope
## (Identifier -> AnalyzedArgumentType) for body analysis. Variables
## have no identity beyond their name, so name keying is correct
## here (unlike the type scopes, which key by identity).
##
## Seeded from a pre-analyzed AnalyzedFunctionDefinition's args;
## extended via the `update` overloads — one absorbs a statement's
## introduced binding, one a case pattern's bindings. Case blocks
## copy the scope by plain assignment (Table is a value type), so
## sibling arms never see each other's bindings.

import options, strformat, tables

import ./defanalyzer
import ./statement
import ./casepattern

type AnalyzedFunctionContext* = Table[Identifier, AnalyzedArgumentType]

proc newAnalyzedFunctionContext*(def: AnalyzedFunctionDefinition): AnalyzedFunctionContext =
  var funcCtx: AnalyzedFunctionContext
  for argDef in def.args:
    assert(argDef.name notin funcCtx, fmt"{argDef.loc}: [BUG] duplicate function argument names encountered")
    funcCtx[argDef.name] = argDef.argType
  return funcCtx

proc update*(funcCtx: var AnalyzedFunctionContext, statement: AnalyzedStatement): AnalyzedFunctionContext =
  if statement.arg.isSome:
    let arg = statement.arg.get
    funcCtx[arg.name] = arg.argType
  return funcCtx

proc update*(funcCtx: var AnalyzedFunctionContext, pattern: AnalyzedCasePattern): AnalyzedFunctionContext =
  for binding in pattern.bindings:
    funcCtx[binding.name] = binding.argType
  return funcCtx