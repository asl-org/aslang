import strformat, strutils

import ./tokenizer

import ./identifiers
import ./decorator
import ./funcdef
import ./statement

# ============================================================
# UserFunction
# ============================================================

type UserFunction* = ref object
  decorators: seq[Decorator]
  def: FunctionDef
  statementList: StatementList

proc newUserFunction*(decorators: seq[Decorator], def: FunctionDef,
    statementList: StatementList): UserFunction =
  UserFunction(decorators: decorators, def: def, statementList: statementList)

proc loc*(fn: UserFunction): Location = fn.def.loc
proc name*(fn: UserFunction): Identifier = fn.def.name
proc def*(fn: UserFunction): FunctionDef = fn.def
proc statements*(fn: UserFunction): seq[Statement] = fn.statementList.statements
proc decorators*(fn: UserFunction): seq[Decorator] = fn.decorators
proc arity*(fn: UserFunction): int = fn.def.arity

proc asl*(fn: UserFunction, level: int, indentWidth: uint32): seq[string] =
  let indent = " ".repeat(level * indentWidth.int)
  var lines: seq[string]
  for d in fn.decorators:
    lines.add(fmt"{indent}{asl(d)}")
  lines.add(fmt"{indent}{asl(fn.def)}")
  for stmt in fn.statementList.statements:
    for line in asl(stmt, level + 1, indentWidth):
      lines.add(line)
  lines
