## AnalyzedFunctionScope — per-function variable scope
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

type AnalyzedFunctionScope* = Table[Identifier, AnalyzedArgumentType]

proc newAnalyzedFunctionScope*(def: AnalyzedFunctionDefinition): AnalyzedFunctionScope =
  var funcScope: AnalyzedFunctionScope
  for argDef in def.args:
    assert(argDef.name notin funcScope, fmt"{argDef.loc}: [BUG] duplicate function argument names encountered")
    funcScope[argDef.name] = argDef.argType
  return funcScope

proc update*(funcScope: var AnalyzedFunctionScope, statement: AnalyzedStatement): AnalyzedFunctionScope =
  if statement.arg.isSome:
    let arg = statement.arg.get
    funcScope[arg.name] = arg.argType
  return funcScope

proc update*(funcScope: var AnalyzedFunctionScope, pattern: AnalyzedCasePattern): AnalyzedFunctionScope =
  for binding in pattern.bindings:
    funcScope[binding.name] = binding.argType
  return funcScope