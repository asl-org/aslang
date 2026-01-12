import results, strformat, tables, hashes

import core, identifier, module_ref, defs
export core, identifier, module_ref, defs

# =============================================================================
# Generic
# =============================================================================

type
  GenericKind* = enum
    GK_DEFAULT, GK_CONSTRAINED
  Generic* = ref object of RootObj
    name: Identifier
    location: Location
    defs_hash_map: Table[Hash, int]
    defs_map: Table[Identifier, Table[int, seq[int]]] # Name => Arity => Indexes
    case kind: GenericKind
    of GK_DEFAULT: discard
    of GK_CONSTRAINED: defs: seq[FunctionDefinition]

proc new_generic*(name: Identifier, location: Location): Generic =
  Generic(kind: GK_DEFAULT, name: name, location: location)

proc new_generic*(name: Identifier, defs: seq[FunctionDefinition],
    location: Location): Result[Generic, string] =
  if defs.len == 0:
    return err(fmt"{location} [PE135] generic `{name.asl}` must have at least one constraint")

  var defs_map: Table[Identifier, Table[int, seq[int]]]
  var defs_hash_map: Table[Hash, int]
  for index, def in defs.pairs:
    let def_hash = def.hash
    if def_hash in defs_hash_map:
      let predefined_def_location = defs[defs_hash_map[def_hash]].location
      return err(fmt"{def.location} [PE136] generic constraint `{def.name.asl}` is already defined at {predefined_def_location}")
    defs_hash_map[def_hash] = index

    if def.name notin defs_map:
      defs_map[def.name] = init_table[int, seq[int]]()
    if def.args.len notin defs_map[def.name]:
      defs_map[def.name][def.args.len] = new_seq[int]()
    defs_map[def.name][def.args.len].add(index)

  ok(Generic(kind: GK_CONSTRAINED, name: name, defs: defs, defs_map: defs_map,
      defs_hash_map: defs_hash_map, location: location))

proc module_ref*(generic: Generic): ModuleRef =
  new_module_ref(generic.name)

proc location*(generic: Generic): Location =
  generic.location

proc defs*(generic: Generic): seq[FunctionDefinition] =
  case generic.kind:
  of GK_DEFAULT: @[]
  of GK_CONSTRAINED: generic.defs

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

proc generic_default_spec*(parser: Parser, indent: int): Result[Generic, string] =
  discard ? parser.expect(indent_spec, indent)
  let generic_keyword = ? parser.expect(generic_keyword_spec)
  discard ? parser.expect(space_spec)
  discard ? parser.expect(optional_space_spec)
  let name = ? parser.expect(identifier_spec)
  ok(new_generic(name, generic_keyword.location))

proc generic_constrained_spec*(parser: Parser, indent: int): Result[Generic, string] =
  discard ? parser.expect(indent_spec, indent)
  let generic_keyword = ? parser.expect(generic_keyword_spec)
  discard ? parser.expect(space_spec)
  discard ? parser.expect(optional_space_spec)
  let name = ? parser.expect(identifier_spec)
  discard ? parser.expect(optional_space_spec)
  discard ? parser.expect(colon_spec)

  var defs: seq[FunctionDefinition]
  discard ? parser.expect(optional_empty_line_spec)

  var maybe_func_def = parser.expect(function_definition_spec, indent + 1)
  while maybe_func_def.is_ok:
    defs.add(maybe_func_def.get)
    discard ? parser.expect(strict_empty_line_spec)
    maybe_func_def = parser.expect(function_definition_spec, indent + 1)

  new_generic(name, defs, generic_keyword.location)

proc generic_spec*(parser: Parser, indent: int): Result[Generic, string] =
  let maybe_generic_constrained = parser.expect(generic_constrained_spec, indent)
  if maybe_generic_constrained.is_ok:
    maybe_generic_constrained
  else:
    # NOTE: generic default parser must be second since it is a subset of
    # generic_named spec and therefore may result in malformed parsing.
    parser.expect(generic_default_spec, indent)
