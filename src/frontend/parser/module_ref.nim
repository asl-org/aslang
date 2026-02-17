import results, strformat, strutils, hashes

import core, identifier
import ../../utils

union ModuleRef:
  module: Identifier
  MRK_SIMPLE
  MRK_NESTED:
    children: seq[ModuleRef]

proc new_module_ref*(module: Identifier): ModuleRef =
  ModuleRef(kind: MRK_SIMPLE, module: module)

proc new_module_ref*(module: Identifier, children: seq[
    ModuleRef]): Result[ModuleRef, core.Error] =
  if children.len == 0:
    err(err_parser_empty_generic_list(module.location))
  elif children.len > MAX_TYPE_CHILDREN_COUNT:
    err(err_parser_generic_list_too_long(module.location, children.len))
  else:
    ok(ModuleRef(kind: MRK_NESTED, module: module, children: children))

proc new_module_ref*(module: string): ModuleRef =
  let module_id = new_identifier(module)
  new_module_ref(module_id)

proc location*(module_ref: ModuleRef): Location =
  module_ref.module.location

proc children*(module_ref: ModuleRef): seq[ModuleRef] =
  variant module_ref:
  of MRK_SIMPLE: @[]
  of MRK_NESTED(children): children

proc asl*(module_ref: ModuleRef): string =
  variant module_ref:
  of MRK_SIMPLE: module_ref.module.asl
  of MRK_NESTED:
    var children: seq[string]
    for child in module_ref.children:
      children.add(child.asl)
    let module_str = module_ref.module.asl
    let children_str = children.join(", ")
    fmt"{module_str}[{children_str}]"

proc hash*(module_ref: ModuleRef): Hash =
  var acc = hash(module_ref.module)
  variant module_ref:
  of MRK_SIMPLE: discard
  of MRK_NESTED:
    for child in module_ref.children:
      acc = acc !& hash(child)
  return acc

proc module_ref_spec*(parser: Parser): Result[ModuleRef, core.Error] =
  let module_ref = ? parser.expect(identifier_spec)

  var maybe_open_square_bracket = parser.expect(open_square_bracket_spec)
  if maybe_open_square_bracket.is_err: return ok(new_module_ref(module_ref))

  discard ? parser.expect_any(space_spec)
  let children = ? parser.non_empty_list_spec(module_ref_spec, comma_spec)
  discard ? parser.expect(close_square_bracket_spec)
  new_module_ref(module_ref, children)
