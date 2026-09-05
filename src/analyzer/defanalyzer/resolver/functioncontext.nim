## FunctionContext — the set of variable names in scope at a body-level
## site, keyed by identifier with the declaration `Location` as value
## so duplicate-declaration errors can point at the prior site.
## Threaded through every statement/expression resolver so name
## lookups can distinguish a bound local from an unresolved reference.
##
## Constructor `newFunctionContext` seeds the scope from a resolved
## function's argument list (rejecting duplicates). `update`
## overloads extend the scope with a statement's introduced variable
## or a case pattern's bindings — used by the body walker as it
## resolves statements sequentially.

import options, results, strformat, tables

import ../parser/index as parser
import argtype
import function
import statement

type FunctionContext* = Table[Identifier, Location]

proc newFunctionContext*(def: ResolvedFunctionDef): Result[FunctionContext, string] =
  var scope: FunctionContext
  for argDef in def.args:
    if argDef.name in scope:
      let loc = scope[argDef.name]
      return err(fmt"{argDef.loc} duplicate function argument declaration encountered, see previous declaration at {loc}")
    scope[argDef.name] = argDef.loc
  ok(scope)

proc update*(scope: var FunctionContext, statement: ResolvedStatement): FunctionContext =
  if statement.variable.isSome:
    let variable = statement.variable.get
    scope[variable] = variable.loc
  return scope

proc update*(scope: var FunctionContext, pattern: ResolvedCasePattern): FunctionContext =
  for binding in pattern.bindings:
    scope[binding] = binding.loc
  return scope