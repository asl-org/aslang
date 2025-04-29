import sequtils, strutils

import location, line

type Program* = ref object of RootObj
  lines: seq[Line]
  location: Location

proc lines*(program: Program): seq[Line] = program.lines

proc `$`*(program: Program): string =
  program.lines.map(proc(s: Line): string = $(s)).join("\n")

proc new_program*(lines: seq[Line], location: Location): Program =
  Program(lines: lines, location: location)
