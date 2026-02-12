import ../analyzer
import literal
import struct_init

proc c*(init: AnalyzedInitializer, result_arg: string): seq[string] =
  case init.kind:
  of RIK_LITERAL: @[init.literal.c(result_arg)]
  of RIK_STRUCT: init.struct.c(result_arg)
