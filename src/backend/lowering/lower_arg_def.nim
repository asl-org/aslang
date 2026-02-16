import ../../middle/analyzer
import ../ir/constructors
import lower_module_ref

proc generate_param*(arg: AnalyzedArgumentDefinition): (CType, string) =
  (arg.module_ref.generate_type, arg.name.asl)

proc generate_byte_size*(arg: AnalyzedArgumentDefinition): uint64 =
  arg.module_ref.generate_byte_size
