import results, strformat, tables, sets, options

import resolver
import module_ref
import module_def
import file_def
import func_ref

type AnalyzedLiteralInit* = ref object of RootObj
  module_ref: AnalyzedModuleRef
  literal: Literal

proc new_analyzed_literal_init(module_ref: AnalyzedModuleRef,
    literal: Literal): AnalyzedLiteralInit =
  AnalyzedLiteralInit(module_ref: module_ref, literal: literal)

proc module_ref*(literal: AnalyzedLiteralInit): AnalyzedModuleRef = literal.module_ref
proc literal*(lit: AnalyzedLiteralInit): Literal = lit.literal

proc returns*(literal: AnalyzedLiteralInit): AnalyzedModuleRef =
  literal.module_ref

proc generic_impls*(literal: AnalyzedLiteralInit): Table[ResolvedModule, seq[
    HashSet[AnalyzedImpl]]] =
  literal.module_ref.generic_impls

proc asl*(literal: AnalyzedLiteralInit): string =
  fmt"{literal.module_ref.asl} {literal.literal.asl}"

proc analyze*(file_def: AnalyzedFileDefinition, scope: FunctionScope,
    init: ResolvedLiteralInit,
    module_def: Option[AnalyzedModuleDefinition] = none[
        AnalyzedModuleDefinition]()): Result[AnalyzedLiteralInit, string] =
  let analyzed_module_ref = if module_def.is_some:
    ? analyze_def(file_def.file, module_def.get.resolved_module,
        init.module_ref)
  else:
    ? analyze_def(file_def.file, init.module_ref)
  case analyzed_module_ref.kind:
  of AMRK_GENERIC: err(fmt"{init.location} Generics are not supported via literal initialization")
  of AMRK_MODULE:
    ? analyzed_module_ref.module.validate(init.literal)
    ok(new_analyzed_literal_init(analyzed_module_ref, init.literal))
