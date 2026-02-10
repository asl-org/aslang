import results, strformat, tables, sets, options

import resolver
import module_ref

type AnalyzedArgumentDefinition* = ref object of RootObj
  name: Identifier
  module_ref: AnalyzedModuleRef
  location: Location

proc new_analyzed_argument_definition*(module_ref: AnalyzedModuleRef,
    name: Identifier, location: Location): AnalyzedArgumentDefinition =
  AnalyzedArgumentDefinition(name: name, module_ref: module_ref,
      location: location)

proc new_analyzed_argument_definition*(module_ref: AnalyzedModuleRef,
    name: Identifier): AnalyzedArgumentDefinition =
  new_analyzed_argument_definition(module_ref, name, module_ref.location)

proc concretize*(arg: AnalyzedArgumentDefinition, concrete_map: Table[
    ResolvedGeneric, AnalyzedModuleRef]): AnalyzedArgumentDefinition =
  let concretized_module_ref = arg.module_ref.concretize(concrete_map)
  new_analyzed_argument_definition(concretized_module_ref, arg.name)

proc name*(arg: AnalyzedArgumentDefinition): Identifier = arg.name
proc byte_size*(arg: AnalyzedArgumentDefinition): uint64 = arg.module_ref.byte_size
proc module_ref*(arg: AnalyzedArgumentDefinition): AnalyzedModuleRef = arg.module_ref
proc location*(arg: AnalyzedArgumentDefinition): Location = arg.location

proc generic_impls*(arg: AnalyzedArgumentDefinition): Table[ResolvedModule,
    seq[HashSet[AnalyzedImpl]]] =
  arg.module_ref.generic_impls

proc asl*(arg: AnalyzedArgumentDefinition): string =
  fmt"{arg.module_ref.asl} {arg.name.asl}"

proc c*(arg: AnalyzedArgumentDefinition): string =
  fmt"{arg.module_ref.c} {arg.name.asl}"

proc function_prefix*(module_name: Identifier,
    generic: Option[ResolvedGeneric]): string =
  if generic.is_some:
    fmt"{module_name.asl}_{generic.get.name.asl}"
  else:
    module_name.asl

# Helper to analyze module_ref with optional generic
proc analyze_def*(file: ResolvedFile, module: ResolvedModule,
    generic: Option[ResolvedGeneric], module_ref: ResolvedModuleRef): Result[
        AnalyzedModuleRef, string] =
  if generic.is_some:
    analyze_def(file, module, generic.get, module_ref)
  else:
    analyze_def(file, module, module_ref)

# Helper to analyze arg with optional generic
proc analyze_def*(file: ResolvedFile, module: ResolvedModule,
    generic: Option[ResolvedGeneric], arg: ResolvedArgumentDefinition): Result[
        AnalyzedArgumentDefinition, string] =
  let analyzed_module_ref = ? analyze_def(file, module, generic, arg.module_ref)
  ? analyzed_module_ref.can_be_argument
  ok(new_analyzed_argument_definition(analyzed_module_ref, arg.name))

# Helper for resolving ResolvedArgumentDefinition without module
proc analyze_def*(file: ResolvedFile,
    arg: ResolvedArgumentDefinition): Result[AnalyzedArgumentDefinition, string] =
  let analyzed_module_ref = ? analyze_def(file, arg.module_ref)
  ? analyzed_module_ref.can_be_argument
  ok(new_analyzed_argument_definition(analyzed_module_ref, arg.name))

proc analyze_def*(file: ResolvedFile, module: ResolvedModule,
    generic: ResolvedGeneric, arg: ResolvedArgumentDefinition): Result[
        AnalyzedArgumentDefinition, string] =
  analyze_def(file, module, some(generic), arg)

proc analyze_def*(file: ResolvedFile, module: ResolvedModule,
    arg: ResolvedArgumentDefinition): Result[AnalyzedArgumentDefinition, string] =
  analyze_def(file, module, none(ResolvedGeneric), arg)
