import function_def, statement

type Function* = ref object of RootObj
  def: FunctionDef
  impl: seq[Statement]

proc new_function*(def: FunctionDef, impl: seq[Statement]): Function =
  Function(def: def, impl: impl)

proc def*(fn: Function): FunctionDef = fn.def

proc `$`*(fn: Function): string =
  var acc: seq[string]
  for statement in fn.impl:
    acc.add("  " & $(statement) & "\n")
  $(fn.def) & ":\n" & $(acc)
