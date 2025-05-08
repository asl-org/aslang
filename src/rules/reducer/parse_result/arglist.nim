import strutils

import location
import identifier

type ArgumentList* = ref object of RootObj
  args: seq[Identifier]
  location: Location

proc new_arglist*(args: seq[Identifier], location: Location): ArgumentList =
  ArgumentList(args: args, location: location)

proc `$`*(arglist: ArgumentList): string =
  "(" & arglist.args.join(", ") & ")"
