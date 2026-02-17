import results, sets

import ../parser
import ../../utils
import expand_struct
import expand_union
import expand_expression

proc expand_function(function: Function): Result[Function, string] =
  variant function:
  of FK_EXTERN: return ok(function)
  of FK_USER:
    let new_steps = ? flatten_statements(function.steps)
    let maybe_user = new_user_function(function.def, new_steps)
    if maybe_user.is_err: return err($maybe_user.error)
    ok(new_function(maybe_user.get))

proc expand_functions(functions: seq[Function]): Result[seq[Function], string] =
  var expanded: seq[Function]
  for function in functions:
    expanded.add( ? expand_function(function))
  ok(expanded)

proc expand_module(module: Module): Result[Module, string] =
  var all_functions = module.functions
  case module.data.kind:
  of DK_NONE, DK_LITERAL: discard
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

    all_functions = module.functions & generated

  # Flatten nested expression arguments in user function bodies
  let expanded_functions = ? expand_functions(all_functions)

  let maybe_module = new_module(module.def, module.generics, module.data,
      expanded_functions)
  if maybe_module.is_err: return err($maybe_module.error)
  ok(maybe_module.get)

proc expand*(parsed_file: file.File): Result[file.File, string] =
  var expanded_modules: seq[Module]
  for module in parsed_file.modules:
    expanded_modules.add( ? expand_module(module))

  let expanded_functions = ? expand_functions(parsed_file.functions)

  let maybe_file = new_file(parsed_file.path, parsed_file.indent,
      expanded_modules, expanded_functions)
  if maybe_file.is_err: return err($maybe_file.error)
  ok(maybe_file.get)
