import results, sequtils, strformat, tables, strutils, sets, options

import resolver

import module_ref
import arg_def

type AnalyzedFunctionDefinition* = ref object of RootObj
  name: Identifier
  args: seq[AnalyzedArgumentDefinition]
  returns: AnalyzedModuleRef
  prefix: string
  generics: uint64
  extern: Option[string]
  location: Location

proc new_analyzed_function_definition(name: Identifier,
    args: seq[AnalyzedArgumentDefinition], returns: AnalyzedModuleRef,
    location: Location, prefix: string = "",
        generics: uint64 = 0): AnalyzedFunctionDefinition =
  AnalyzedFunctionDefinition(name: name, args: args,
      returns: returns, location: location, prefix: prefix, generics: generics)

# WIP
proc new_analyzed_function_definition(name: Identifier,
    args: seq[AnalyzedArgumentDefinition], returns: AnalyzedModuleRef,
    location: Location, extern: Option[string], prefix: string = "",
        generics: uint64 = 0): AnalyzedFunctionDefinition =
  AnalyzedFunctionDefinition(name: name, args: args, returns: returns,
      location: location, prefix: prefix, generics: generics, extern: extern)

proc name*(def: AnalyzedFunctionDefinition): Identifier = def.name
proc args*(def: AnalyzedFunctionDefinition): seq[
    AnalyzedArgumentDefinition] = def.args
proc returns*(def: AnalyzedFunctionDefinition): AnalyzedModuleRef = def.returns
proc arity*(def: AnalyzedFunctionDefinition): uint = def.args.len.uint
proc concretize*(def: AnalyzedFunctionDefinition, concrete_map: Table[
    ResolvedGeneric, AnalyzedModuleRef]): AnalyzedFunctionDefinition =
  var concretized_args: seq[AnalyzedArgumentDefinition]
  for arg in def.args:
    concretized_args.add(arg.concretize(concrete_map))
  let concretized_returns = def.returns.concretize(concrete_map)
  new_analyzed_function_definition(def.name, concretized_args,
      concretized_returns, def.location, def.extern)

proc generic_impls*(def: AnalyzedFunctionDefinition): Table[
    ResolvedModule, seq[HashSet[AnalyzedImpl]]] =
  var impl_set: Table[ResolvedModule, seq[HashSet[AnalyzedImpl]]]
  for arg in def.args: impl_set = impl_set.merge(arg.generic_impls())
  impl_set = impl_set.merge(def.returns.generic_impls())
  return impl_set

proc asl*(def: AnalyzedFunctionDefinition): string =
  let args = def.args.map_it(it.asl).join(", ")
  fmt"fn {def.name.asl}({args}): {def.returns.asl}"

proc c_name*(def: AnalyzedFunctionDefinition): string =
  if def.extern.is_some:
    def.extern.get
  elif def.prefix == "":
    fmt"{def.name.asl}_{def.location.hash.to_hex}"
  else:
    fmt"{def.prefix}_{def.name.asl}_{def.location.hash.to_hex}"

proc h*(def: AnalyzedFunctionDefinition): string =
  let generic_args = if def.generics > 0: ((0.uint64)..<(
      def.generics)).map_it(fmt"U64 __asl_impl_id_{it}") else: @[]
  let args = generic_args & def.args.map_it(it.c)
  let args_str = args.join(", ")
  let code = fmt"{def.returns.c} {def.c_name}({args_str});"
  if def.extern.is_some: fmt"extern {code}" else: code

# Helper for resolving ResolvedFunctionDefinition with ResolvedModule
proc analyze_def(file: ResolvedFile,
    function: ResolvedFunction, module: ResolvedModule,
    generic: Option[ResolvedGeneric]): Result[AnalyzedFunctionDefinition, string] =
  let def = function.def
  var analyzed_args: seq[AnalyzedArgumentDefinition]
  for arg in def.args:
    let analyzed_arg = ? analyze_arg_with_generic(file, module, generic, arg)
    analyzed_args.add(analyzed_arg)

  let analyzed_returns = ? analyze_module_ref_with_generic(file, module,
      generic, def.returns)

  let prefix = function_prefix(module.name, generic)

  case function.kind:
  of RFK_EXTERN:
    ok(new_analyzed_function_definition(def.name, analyzed_args,
        analyzed_returns, def.location, function.extern_name, prefix,
        module.generics.len.uint64))
  of RFK_USER:
    ok(new_analyzed_function_definition(def.name, analyzed_args,
        analyzed_returns, def.location, prefix, module.generics.len.uint64))

proc analyze_def(file: ResolvedFile,
    def: ResolvedFunctionDefinition, module: ResolvedModule,
    generic: Option[ResolvedGeneric]): Result[AnalyzedFunctionDefinition, string] =
  var analyzed_args: seq[AnalyzedArgumentDefinition]
  for arg in def.args:
    let analyzed_arg = ? analyze_arg_with_generic(file, module, generic, arg)
    analyzed_args.add(analyzed_arg)

  let analyzed_returns = ? analyze_module_ref_with_generic(file, module,
      generic, def.returns)

  let prefix = function_prefix(module.name, generic)

  ok(new_analyzed_function_definition(def.name, analyzed_args,
      analyzed_returns, def.location, prefix, module.generics.len.uint64))

# Helper for resolving ResolvedFunctionDefinition without module
proc analyze_function_definition_no_module(file: ResolvedFile,
    def: ResolvedFunctionDefinition): Result[AnalyzedFunctionDefinition, string] =
  var analyzed_args: seq[AnalyzedArgumentDefinition]
  for arg in def.args:
    let analyzed_arg = ? analyze_def(file, arg)
    analyzed_args.add(analyzed_arg)
  let analyzed_returns = ? analyze_def(file, def.returns)
  ok(new_analyzed_function_definition(def.name, analyzed_args, analyzed_returns, def.location))

proc analyze_function_definition_no_module(file: ResolvedFile,
    function: ResolvedFunction): Result[AnalyzedFunctionDefinition, string] =
  var analyzed_args: seq[AnalyzedArgumentDefinition]
  let def = function.def
  for arg in def.args:
    let analyzed_arg = ? analyze_def(file, arg)
    analyzed_args.add(analyzed_arg)
  let analyzed_returns = ? analyze_def(file, def.returns)
  case function.kind:
  of RFK_EXTERN:
    ok(new_analyzed_function_definition(def.name, analyzed_args,
        analyzed_returns, def.location, function.extern_name))
  of RFK_USER:
    ok(new_analyzed_function_definition(def.name, analyzed_args,
        analyzed_returns, def.location))

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

proc analyze_def*(file: ResolvedFile, def: ResolvedFunctionDefinition): Result[
    AnalyzedFunctionDefinition, string] =
  analyze_function_definition_no_module(file, def)

proc analyze_def*(file: ResolvedFile, function: ResolvedFunction): Result[
    AnalyzedFunctionDefinition, string] =
  analyze_function_definition_no_module(file, function)
