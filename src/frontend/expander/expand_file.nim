import results, sets

import ../parser
import expand_struct
import expand_union

proc expand_module(module: Module): Result[Module, string] =
  case module.data.kind:
  of DK_NONE, DK_LITERAL:
    ok(module)
  of DK_STRUCT, DK_UNION:
    var existing_names: HashSet[(string, int)]
    for function in module.functions:
      existing_names.incl((function.name.asl, function.def.args.len))

    let prefix = module.name.asl
    var generated: seq[Function]
    case module.data.kind:
    of DK_STRUCT:
      generated = ? expand_struct(module.data.struct, prefix,
          module.name.asl, module.generics, existing_names)
    of DK_UNION:
      generated = ? expand_union(module.data.union, prefix,
          module.name.asl, module.generics, existing_names)
    else: discard

    if generated.len == 0:
      return ok(module)

    let all_functions = module.functions & generated
    let maybe_module = new_module(module.def, module.generics, module.data,
        all_functions)
    if maybe_module.is_err: return err($maybe_module.error)
    ok(maybe_module.get)

proc expand*(parsed_file: file.File): Result[file.File, string] =
  var expanded_modules: seq[Module]
  for module in parsed_file.modules:
    expanded_modules.add( ? expand_module(module))

  let maybe_file = new_file(parsed_file.path, parsed_file.indent,
      expanded_modules, parsed_file.functions)
  if maybe_file.is_err: return err($maybe_file.error)
  ok(maybe_file.get)
