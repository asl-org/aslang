import sequtils, strutils

import location, statement

type Program* = ref object of RootObj
  statements: seq[Statement]
  location: Location

proc statements*(program: Program): seq[Statement] = program.statements

proc `$`*(program: Program): string =
  program.statements.map(proc(s: Statement): string = $(s)).join("\n")

proc new_program*(statements: seq[Statement], location: Location): Program =
  Program(statements: statements, location: location)
