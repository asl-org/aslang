import results, sequtils, strformat, tables, strutils, sets, options

import resolver

import module_ref
import arg_def

type AnalyzedFunctionDefinition* = ref object of RootObj
  resolved_def: ResolvedFunctionDefinition
  args: seq[AnalyzedArgumentDefinition]
  returns: AnalyzedModuleRef
  prefix: string
  generics: uint64
  extern: Option[string]

proc new_analyzed_function_definition(def: ResolvedFunctionDefinition,
    args: seq[AnalyzedArgumentDefinition], returns: AnalyzedModuleRef,
    prefix: string = "", generics: uint64 = 0): AnalyzedFunctionDefinition =
  AnalyzedFunctionDefinition(resolved_def: def, args: args, returns: returns,
      prefix: prefix, generics: generics)

# WIP
proc new_analyzed_function_definition(def: ResolvedFunctionDefinition,
    args: seq[AnalyzedArgumentDefinition], returns: AnalyzedModuleRef,
    extern: Option[string], prefix: string = "",
    generics: uint64 = 0): AnalyzedFunctionDefinition =
  AnalyzedFunctionDefinition(resolved_def: def, args: args, returns: returns,
      prefix: prefix, generics: generics, extern: extern)

proc args*(def: AnalyzedFunctionDefinition): seq[
    AnalyzedArgumentDefinition] = def.args
proc returns*(def: AnalyzedFunctionDefinition): AnalyzedModuleRef = def.returns
proc extern*(def: AnalyzedFunctionDefinition): Option[string] = def.extern
proc prefix*(def: AnalyzedFunctionDefinition): string = def.prefix
proc generics*(def: AnalyzedFunctionDefinition): uint64 = def.generics

proc resolved_def*(def: AnalyzedFunctionDefinition): ResolvedFunctionDefinition = def.resolved_def
proc name*(def: AnalyzedFunctionDefinition): Identifier = def.resolved_def.name
proc location*(def: AnalyzedFunctionDefinition): Location = def.resolved_def.location

proc arity*(def: AnalyzedFunctionDefinition): uint = def.args.len.uint
proc concretize*(def: AnalyzedFunctionDefinition, concrete_map: Table[
    ResolvedGeneric, AnalyzedModuleRef]): AnalyzedFunctionDefinition =
  var concretized_args: seq[AnalyzedArgumentDefinition]
  for arg in def.args:
    concretized_args.add(arg.concretize(concrete_map))
  let concretized_returns = def.returns.concretize(concrete_map)
  new_analyzed_function_definition(def.resolved_def, concretized_args,
      concretized_returns, def.extern)

proc generic_impls*(def: AnalyzedFunctionDefinition): Table[
    ResolvedModule, seq[HashSet[AnalyzedImpl]]] =
  var impl_set: Table[ResolvedModule, seq[HashSet[AnalyzedImpl]]]
  for arg in def.args: impl_set = impl_set.merge(arg.generic_impls())
  impl_set = impl_set.merge(def.returns.generic_impls())
  return impl_set

proc asl*(def: AnalyzedFunctionDefinition): string =
  let args = def.args.map_it(it.asl).join(", ")
  fmt"fn {def.name.asl}({args}): {def.returns.asl}"

# Helper for resolving ResolvedFunctionDefinition with ResolvedModule
proc analyze_def(file: ResolvedFile,
    function: ResolvedFunction, module: ResolvedModule,
    generic: Option[ResolvedGeneric]): Result[AnalyzedFunctionDefinition, string] =
  let def = function.def
  var analyzed_args: seq[AnalyzedArgumentDefinition]
  for arg in def.args:
    let analyzed_arg = ? analyze_def(file, module, generic, arg)
    analyzed_args.add(analyzed_arg)

  let analyzed_returns = ? analyze_def(file, module, generic, def.returns)

  let prefix = function_prefix(module.name, generic)

  case function.kind:
  of RFK_EXTERN:
    ok(new_analyzed_function_definition(def, analyzed_args,
        analyzed_returns, function.extern_name, prefix,
        module.generics.len.uint64))
  of RFK_USER:
    ok(new_analyzed_function_definition(def, analyzed_args,
        analyzed_returns, prefix, module.generics.len.uint64))

proc analyze_def(file: ResolvedFile,
    def: ResolvedFunctionDefinition, module: ResolvedModule,
    generic: Option[ResolvedGeneric]): Result[AnalyzedFunctionDefinition, string] =
  var analyzed_args: seq[AnalyzedArgumentDefinition]
  for arg in def.args:
    let analyzed_arg = ? analyze_def(file, module, generic, arg)
    analyzed_args.add(analyzed_arg)

  let analyzed_returns = ? analyze_def(file, module,
      generic, def.returns)

  let prefix = function_prefix(module.name, generic)

  ok(new_analyzed_function_definition(def, analyzed_args, analyzed_returns,
      prefix, module.generics.len.uint64))

# Helper for resolving ResolvedFunctionDefinition without module
proc analyze_def*(file: ResolvedFile,
    def: ResolvedFunctionDefinition): Result[AnalyzedFunctionDefinition, string] =
  var analyzed_args: seq[AnalyzedArgumentDefinition]
  for arg in def.args:
    let analyzed_arg = ? analyze_def(file, arg)
    analyzed_args.add(analyzed_arg)
  let analyzed_returns = ? analyze_def(file, def.returns)
  ok(new_analyzed_function_definition(def, analyzed_args, analyzed_returns))

proc analyze_def*(file: ResolvedFile,
    function: ResolvedFunction): Result[AnalyzedFunctionDefinition, string] =
  var analyzed_args: seq[AnalyzedArgumentDefinition]
  let def = function.def
  for arg in def.args:
    let analyzed_arg = ? analyze_def(file, arg)
    analyzed_args.add(analyzed_arg)
  let analyzed_returns = ? analyze_def(file, def.returns)
  case function.kind:
  of RFK_EXTERN:
    ok(new_analyzed_function_definition(def, analyzed_args, analyzed_returns,
        function.extern_name))
  of RFK_USER:
    ok(new_analyzed_function_definition(def, analyzed_args, analyzed_returns))

proc analyze_def*(file: ResolvedFile, module: ResolvedModule,
    generic: ResolvedGeneric, def: ResolvedFunction): Result[
        AnalyzedFunctionDefinition, string] =
  analyze_def(file, def, module, some(generic))

proc analyze_def*(file: ResolvedFile, module: ResolvedModule,
    generic: ResolvedGeneric, def: ResolvedFunctionDefinition): Result[
        AnalyzedFunctionDefinition, string] =
  analyze_def(file, def, module, some(generic))

proc analyze_def*(file: ResolvedFile, module: ResolvedModule,
    def: ResolvedFunctionDefinition): Result[AnalyzedFunctionDefinition, string] =
  analyze_def(file, def, module, none(ResolvedGeneric))

proc analyze_def*(file: ResolvedFile, module: ResolvedModule,
    function: ResolvedFunction): Result[AnalyzedFunctionDefinition, string] =
  analyze_def(file, function, module, none(ResolvedGeneric))
