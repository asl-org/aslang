import results, tables, sets

import ../analyzer
import ../metadata
import ../ir/constructors
import ../emitter/emit
import ../optimizer/lifetime
import ../optimizer/runtime_metadata
import gen_func_def
import gen_file_def
import gen_module
import gen_function

proc generic_impls(file: AnalyzedFile): Result[Table[
    AnalyzedModuleDefinition, seq[seq[(AnalyzedModuleDefinition, seq[
    AnalyzedFunctionDefinition])]]], string] =
  var impl_set: Table[ResolvedModule, seq[HashSet[AnalyzedImpl]]]
  impl_set = impl_set.merge(file.def.generic_impls)
  for module in file.modules: impl_set = impl_set.merge(module.generic_impls)
  for function in file.functions: impl_set = impl_set.merge(
      function.generic_impls)

  var impl_map: Table[AnalyzedModuleDefinition, seq[seq[(
      AnalyzedModuleDefinition, seq[AnalyzedFunctionDefinition])]]]
  for module, children in impl_set.pairs:
    var analyzed_children: seq[seq[(AnalyzedModuleDefinition, seq[
        AnalyzedFunctionDefinition])]]
    for impls in children:
      var analyzed_impls: seq[(AnalyzedModuleDefinition, seq[
          AnalyzedFunctionDefinition])]
      for impl in impls:
        case impl.module_ref.kind:
        of AMRK_GENERIC:
          return err("[INTERNAL ERROR] unexpected generic in impl resolution")
        of AMRK_MODULE:
          let module_def = ? file.def.find_module_def(
              impl.module_ref.module)
          var analyzed_function_defs: seq[AnalyzedFunctionDefinition]
          for def in impl.defs:
            let analyzed_function_def = ? module_def.find_function_def(def)
            analyzed_function_defs.add(analyzed_function_def)
          analyzed_impls.add((module_def,
              analyzed_function_defs))
      analyzed_children.add(analyzed_impls)

    let analyzed_module_def = ? file.def.find_module_def(module)
    impl_map[analyzed_module_def] = analyzed_children
  return ok(impl_map)

proc generate*(file: AnalyzedFile): Result[CProgram, string] =
  let impls = ? file.generic_impls

  var includes: seq[CDecl]
  includes.add(c_include("stdint.h"))
  includes.add(c_include("string.h"))
  includes.add(c_include("stdio.h"))
  includes.add(c_include("stdlib.h"))

  var typedefs: seq[CDecl]
  typedefs.add(c_typedef("const char *", "string"))
  typedefs.add(file.def.generate_file_typedefs)

  var forward_decls: seq[CDecl]
  forward_decls.add(file.def.generate_file_decls)

  var definitions: seq[CDecl]
  definitions.add(file.def.generate_file_defs)
  for module in file.modules:
    let module_impls = impls.get_or_default(module.def, @[])
    definitions.add(module.generate_module(module_impls))
  for function in file.functions:
    definitions.add(function.generate_user_function)

  let main_body = @[
    c_return(c_call(file.start_function_def.generate_func_name,
        @[c_ident("argc")]))
  ]
  let main = c_func_def(c_named("int"), "main",
      @[(c_named("int"), "argc"), (c_named("char**"), "argv")], main_body)

  # Assemble pre-populated metadata from analyzer
  var metadata: Table[string, FunctionMetadata]
  add_runtime_metadata(metadata)
  for module in file.modules:
    # Data-generated functions (init, get_*, set_*, etc.)
    for name, m in compute_data_metadata(module.def.data, module.def.name.asl):
      metadata[name] = m
    # Module-level user/extern functions
    for function in module.functions:
      case function.kind:
      of AFK_USER:
        metadata[function.user.def.generate_func_name] = function.user.def.metadata
      of AFK_EXTERN:
        let name = function.extern_def.generate_func_name
        if name notin metadata:
          metadata[name] = function.extern_def.metadata
  # File-level functions
  for function in file.functions:
    metadata[function.def.generate_func_name] = function.def.metadata

  ok(c_program(includes, typedefs, forward_decls, definitions, main, metadata))

proc c*(file: AnalyzedFile): Result[string, string] =
  let program = ? generate(file)
  let optimized = optimize(program)
  ok(emit(optimized))
