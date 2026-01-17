import results, strformat, strutils, hashes

import core, identifier
export core, identifier

type
  ModuleRefKind* = enum
    MRK_SIMPLE, MRK_NESTED
  ModuleRef* = ref object of RootObj
    module: Identifier
    case kind: ModuleRefKind
    of MRK_SIMPLE: discard
    of MRK_NESTED: children: seq[ModuleRef]

proc new_module_ref*(module: Identifier): ModuleRef =
  ModuleRef(kind: MRK_SIMPLE, module: module)

proc new_module_ref*(module: Identifier, children: seq[
    ModuleRef]): Result[ModuleRef, ParserError] =
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

proc module*(module_ref: ModuleRef): Identifier =
  module_ref.module

proc kind*(module_ref: ModuleRef): ModuleRefKind =
  module_ref.kind

proc children*(module_ref: ModuleRef): seq[ModuleRef] =
  case module_ref.kind:
  of MRK_SIMPLE: @[]
  of MRK_NESTED: module_ref.children

proc asl*(module_ref: ModuleRef): string =
  case module_ref.kind:
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
  case module_ref.kind:
  of MRK_SIMPLE: discard
  of MRK_NESTED:
    for child in module_ref.children:
      acc = acc !& hash(child)
  return acc

proc module_ref_spec*(parser: Parser): Result[ModuleRef, ParserError] =
  let module_ref = ? parser.expect(identifier_spec)

  var maybe_open_square_bracket = parser.expect(open_square_bracket_spec)
  if maybe_open_square_bracket.is_err: return ok(new_module_ref(module_ref))

  var children: seq[ModuleRef]
  discard ? parser.expect(optional_space_spec)
  children.add( ? parser.expect(module_ref_spec))
  discard ? parser.expect(optional_space_spec)

  while parser.expect(comma_spec).is_ok:
    discard ? parser.expect(optional_space_spec)
    children.add( ? parser.expect(module_ref_spec))
    discard ? parser.expect(optional_space_spec)

  discard ? parser.expect(close_square_bracket_spec)
  new_module_ref(module_ref, children)
