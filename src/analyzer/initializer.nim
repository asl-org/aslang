import results, tables, sets

import resolver
import module_ref
import module_def
import file_def
import func_ref
import struct_init
import literal

type
  AnalyzedInitializerKind = enum
    RIK_LITERAL, RIK_STRUCT
  AnalyzedInitializer* = ref object of RootObj
    case kind: AnalyzedInitializerKind
    of RIK_LITERAL: literal: AnalyzedLiteral
    of RIK_STRUCT: struct: AnalyzedStructInit

proc new_analyzed_initializer(struct: AnalyzedStructInit): AnalyzedInitializer =
  AnalyzedInitializer(kind: RIK_STRUCT, struct: struct)

proc new_analyzed_initializer(literal: AnalyzedLiteral): AnalyzedInitializer =
  AnalyzedInitializer(kind: RIK_LITERAL, literal: literal)

proc returns*(init: AnalyzedInitializer): AnalyzedModuleRef =
  case init.kind:
  of RIK_STRUCT: init.struct.returns
  of RIK_LITERAL: init.literal.returns

proc generic_impls*(init: AnalyzedInitializer): Table[ResolvedModule, seq[
    HashSet[AnalyzedImpl]]] =
  case init.kind:
  of RIK_LITERAL: init.literal.generic_impls
  of RIK_STRUCT: init.struct.generic_impls

proc asl*(init: AnalyzedInitializer): string =
  case init.kind:
  of RIK_LITERAL: init.literal.asl
  of RIK_STRUCT: init.struct.asl

proc c*(init: AnalyzedInitializer, result_arg: string): seq[string] =
  case init.kind:
  of RIK_LITERAL: @[init.literal.c(result_arg)]
  of RIK_STRUCT: init.struct.c(result_arg)

proc analyze*(file_def: AnalyzedFileDefinition,
    module_def: AnalyzedModuleDefinition, scope: FunctionScope,
    init: ResolvedInitializer): Result[AnalyzedInitializer, string] =
  case init.kind:
  of TIK_STRUCT:
    let struct_init = ? init.struct
    let analyzed_struct_init = ? analyze(file_def, module_def, scope, struct_init)
    ok(new_analyzed_initializer(analyzed_struct_init))
  of TIK_LITERAL:
    let literal_init = ? init.literal
    let analyzed_literal = ? analyze(file_def, module_def, scope, literal_init)
    ok(new_analyzed_initializer(analyzed_literal))

proc analyze*(file_def: AnalyzedFileDefinition, scope: FunctionScope,
    init: ResolvedInitializer): Result[AnalyzedInitializer, string] =
  case init.kind:
  of TIK_STRUCT:
    let struct_init = ? init.struct
    let analyzed_struct_init = ? analyze(file_def, scope, struct_init)
    ok(new_analyzed_initializer(analyzed_struct_init))
  of TIK_LITERAL:
    let literal_init = ? init.literal
    let analyzed_literal = ? analyze(file_def, scope, literal_init)
    ok(new_analyzed_initializer(analyzed_literal))
