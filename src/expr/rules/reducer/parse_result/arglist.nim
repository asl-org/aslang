import strutils

import location

type ArgumentList* = ref object of RootObj
  args: seq[string]
  location: Location

proc new_arglist*(args: seq[string], location: Location): ArgumentList =
  ArgumentList(args: args, location: location)

proc `$`*(arglist: ArgumentList): string =
  "(" & arglist.args.join(", ") & ")"
