import strformat, sequtils, strutils

import "../location"
import argument

# TODO: Support struct literals as the argument
type ArgumentList* = ref object of RootObj
  arguments: seq[Argument]
  location: Location

proc arguments*(arglist: ArgumentList): seq[Argument] = arglist.arguments

proc `$`*(arglist: ArgumentList): string =
  let args = arglist.arguments.map(proc(a: Argument): string = $(a)).join(", ")
  fmt"({args})"

proc new_argument_list*(args: seq[Argument],
    location: Location): ArgumentList =
  ArgumentList(arguments: args, location: location)
