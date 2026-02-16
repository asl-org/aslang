import sequtils, sets, options

import ../../middle/analyzer
import ../ir/constructors
import lower_generic
import lower_struct
import lower_func_def

proc generate_module_typedefs*(def: AnalyzedModuleDefinition): seq[CDecl] =
  def.data.generate_data_typedefs(def.name.asl)

proc generate_module_decls*(def: AnalyzedModuleDefinition): seq[CDecl] =
  var decls: seq[CDecl]
  for generic in def.generics:
    decls.add(generic.generate_generic_decls(def.name.asl))
  decls.add(def.function_defs.map_it(it.generate_func_decl))
  return decls

proc generate_module_defs*(def: AnalyzedModuleDefinition): seq[CDecl] =
  var decls: seq[CDecl]
  for generic in def.generics:
    decls.add(generic.generate_generic_decls(def.name.asl))
  # Collect C names of manually-defined ExternFunctions (non-expanded).
  # These have runtime-provided bodies; the compiler should NOT generate bodies.
  var manual_extern_names: HashSet[string]
  for fdef in def.function_defs:
    if fdef.extern.is_some and not fdef.expanded:
      manual_extern_names.incl(fdef.extern.get)
  decls.add(def.data.generate_data_defs(def.name.asl,
      def.generics.len.uint64, manual_extern_names))
  return decls
