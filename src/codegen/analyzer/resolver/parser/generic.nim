import results, strformat, tables, hashes

import core, identifier, module_ref, defs

# =============================================================================
# Generic
# =============================================================================

type
  GenericKind* = enum
    GK_DEFAULT, GK_CONSTRAINED
  Generic* = ref object of RootObj
    name: Identifier
    location: Location
    defs_repo: Repo[FunctionDefinition]
    case kind: GenericKind
    of GK_DEFAULT: discard
    of GK_CONSTRAINED: defs: seq[FunctionDefinition]

proc new_generic*(name: Identifier, location: Location): Generic =
  Generic(kind: GK_DEFAULT, name: name, location: location)

proc new_generic*(name: Identifier, defs: seq[FunctionDefinition],
    location: Location): Result[Generic, core.Error] =
  if defs.len == 0:
    return err(err_parser_empty_generic_constraint_list(location, name.asl))

  let maybe_defs_repo = new_repo(defs, @[new_index[FunctionDefinition](
      "def", hash, true)])
  if maybe_defs_repo.is_err:
    let error = maybe_defs_repo.error
    let def = error.current
    let predefined_def_location = error.previous.location
    return err(err_parser_generic_constraint_already_defined(def.location,
        def.name.asl, predefined_def_location))

  ok(Generic(kind: GK_CONSTRAINED, name: name, defs_repo: maybe_defs_repo.get,
      location: location))

proc module_ref*(generic: Generic): ModuleRef =
  new_module_ref(generic.name)

proc location*(generic: Generic): Location =
  generic.location

proc defs*(generic: Generic): seq[FunctionDefinition] =
  case generic.kind:
  of GK_DEFAULT: @[]
  of GK_CONSTRAINED: generic.defs_repo.items

proc name*(generic: Generic): Identifier =
  generic.name

proc asl*(generic: Generic, indent: string): seq[string] =
  case generic.kind:
  of GK_DEFAULT:
    @[fmt"generic {generic.name.asl}"]
  of GK_CONSTRAINED:
    let header = fmt"generic {generic.name.asl}:"

    var defs: seq[string]
    for def in generic.defs:
      defs.add(indent & def.asl)

    @[header] & defs

proc hash*(generic: Generic): Hash =
  generic.location.hash

proc `==`*(self: Generic, other: Generic): bool =
  self.hash == other.hash

proc generic_default_spec*(parser: Parser, indent: int): Result[Generic,
    core.Error] =
  discard ? parser.expect(indent_spec, indent)
  let generic_keyword = ? parser.expect(generic_keyword_spec)
  discard ? parser.expect(space_spec)
  discard ? parser.expect(optional_space_spec)
  let name = ? parser.expect(identifier_spec)
  ok(new_generic(name, generic_keyword.location))

proc generic_constrained_spec*(parser: Parser, indent: int): Result[Generic,
    core.Error] =
  discard ? parser.expect(indent_spec, indent)
  let generic_keyword = ? parser.expect(generic_keyword_spec)
  discard ? parser.expect(space_spec)
  discard ? parser.expect(optional_space_spec)
  let name = ? parser.expect(identifier_spec)
  discard ? parser.expect(optional_space_spec)
  discard ? parser.expect(colon_spec)

  discard ? parser.expect(optional_empty_line_spec)
  let defs = ? parser.zero_or_more_spec(function_definition_spec, indent + 1,
      strict_empty_line_spec)
  new_generic(name, defs, generic_keyword.location)

# NOTE: generic_constrained must be first since generic_default is a subset of
# it and therefore may result in malformed parsing.
proc generic_spec*(parser: Parser, indent: int): Result[Generic, core.Error] =
  parser.first_of([generic_constrained_spec, generic_default_spec], indent)

