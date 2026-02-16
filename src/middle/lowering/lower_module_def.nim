import sequtils

import ../analyzer
import ../../ir/constructors
import lower_generic
import lower_struct
import lower_func_def

proc generate_module_typedefs*(def: AnalyzedModuleDefinition): seq[CDecl] =
  def.data.generate_data_typedefs(def.name.asl)

proc generate_module_decls*(def: AnalyzedModuleDefinition): seq[CDecl] =
  var decls: seq[CDecl]
  for generic in def.generics:
    decls.add(generic.generate_generic_decls(def.name.asl))
  decls.add(def.data.generate_data_decls(def.name.asl))
  decls.add(def.function_defs.map_it(it.generate_func_decl))
  return decls

proc generate_module_defs*(def: AnalyzedModuleDefinition): seq[CDecl] =
  var decls: seq[CDecl]
  for generic in def.generics:
    decls.add(generic.generate_generic_decls(def.name.asl))
  decls.add(def.data.generate_data_defs(def.name.asl))
  return decls
