import strformat

import ../analyzer
import module_ref

proc byte_size*(arg: AnalyzedArgumentDefinition): uint64 = arg.module_ref.byte_size
proc c*(arg: AnalyzedArgumentDefinition): string =
  fmt"{arg.module_ref.c} {arg.name.asl}"
