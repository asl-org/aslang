import ../analyzer
import ../../ir/constructors
import lower_func_def

proc generate_generic_decls*(generic: AnalyzedGeneric,
    prefix: string): seq[CDecl] =
  var decls: seq[CDecl]
  for def in generic.defs:
    decls.add(def.generate_func_decl)
  return decls
