import ../analyzer
import ../ir/constructors
import gen_module_def
import gen_func_def

proc generate_file_typedefs*(file: AnalyzedFileDefinition): seq[CDecl] =
  var decls: seq[CDecl]
  for module in file.modules:
    decls.add(module.generate_module_typedefs)
  return decls

proc generate_file_decls*(file: AnalyzedFileDefinition): seq[CDecl] =
  var decls: seq[CDecl]
  for module in file.modules:
    decls.add(module.generate_module_decls)
  for fndef in file.function_defs:
    decls.add(fndef.generate_func_decl)
  return decls

proc generate_file_defs*(file: AnalyzedFileDefinition): seq[CDecl] =
  var decls: seq[CDecl]
  for module in file.modules:
    decls.add(module.generate_module_defs)
  return decls
