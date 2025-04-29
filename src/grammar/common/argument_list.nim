import strformat, sequtils, strutils

import "../location"
import native_argument

# TODO: Support struct literals as the argument
type ArgumentList* = ref object of RootObj
  arguments: seq[NativeArgument]
  location: Location

proc arguments*(arglist: ArgumentList): seq[NativeArgument] = arglist.arguments

proc `$`*(arglist: ArgumentList): string =
  let args = arglist.arguments.map(proc(a: NativeArgument): string = $(a)).join(", ")
  fmt"({args})"

proc new_argument_list*(args: seq[NativeArgument],
    location: Location): ArgumentList =
  ArgumentList(arguments: args, location: location)
