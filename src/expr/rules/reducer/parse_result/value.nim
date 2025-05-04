import init, fncall

type
  ValueKind = enum
    VK_INIT, VK_FNCALL
  Value* = ref object of RootObj
    case kind: ValueKind
    of VK_INIT: init: Initializer
    of VK_FNCALL: fncall: FunctionCall

proc new_value*(init: Initializer): Value = Value(kind: VK_INIT, init: init)
proc new_value*(fncall: FunctionCall): Value = Value(kind: VK_FNCALL,
    fncall: fncall)

proc `$`*(value: Value): string =
  case value.kind:
  of VK_INIT: $(value.init)
  of VK_FNCALL: $(value.fncall)
