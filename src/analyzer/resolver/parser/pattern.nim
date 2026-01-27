import results, strformat, strutils, tables

import core, identifier, literal
export core, identifier, literal

# =============================================================================
# MatchDefinition
# =============================================================================

type
  MatchDefinitionKind* = enum
    MDK_DEFAULT, MDK_ASSIGNED
  MatchDefinition* = ref object of RootObj
    kind: MatchDefinitionKind
    operand: Identifier
    arg: Identifier

proc new_match_definition*(operand: Identifier,
    location: Location): Result[MatchDefinition, Error] =
  let arg = new_identifier(location)
  ok(MatchDefinition(kind: MDK_DEFAULT, arg: arg, operand: operand))

proc new_match_definition*(def: MatchDefinition,
    arg: Identifier): MatchDefinition =
  MatchDefinition(kind: MDK_ASSIGNED, arg: arg, operand: def.operand)

proc location*(def: MatchDefinition): Location = def.arg.location
proc operand*(def: MatchDefinition): Identifier = def.operand
proc arg*(def: MatchDefinition): Identifier = def.arg

proc asl*(def: MatchDefinition): string =
  case def.kind:
  of MDK_DEFAULT: fmt"match {def.operand.asl}:"
  of MDK_ASSIGNED: fmt"{def.arg.asl} = match {def.operand.asl}:"

proc match_definition_default_spec*(parser: Parser): Result[
    MatchDefinition, Error] =
  let match_keyword = ? parser.expect(match_keyword_spec)
  discard ? parser.expect(strict_space_spec)
  let operand = ? parser.expect(identifier_spec)
  discard ? parser.expect(optional_space_spec)
  discard ? parser.expect(colon_spec)
  new_match_definition(operand, match_keyword.location)

proc match_definition_assigned_spec*(parser: Parser): Result[MatchDefinition,
    Error] =
  let arg = ? parser.expect(identifier_spec)
  discard ? parser.expect(optional_space_spec)
  discard ? parser.expect(equal_spec)
  discard ? parser.expect(optional_space_spec)
  let match_def_default = ? parser.expect(match_definition_default_spec)
  ok(new_match_definition(match_def_default, arg))

proc match_definition_spec*(parser: Parser): Result[MatchDefinition,
    Error] =
  var errors: seq[Error]
  let maybe_match_def_default = parser.expect(match_definition_default_spec)
  if maybe_match_def_default.is_ok: return maybe_match_def_default
  else: errors.add(maybe_match_def_default.error)

  let maybe_match_def_assigned = parser.expect(match_definition_assigned_spec)
  if maybe_match_def_assigned.is_ok: return maybe_match_def_assigned
  else: errors.add(maybe_match_def_assigned.error)

  err(errors.max())

proc keyword_value_identifier_spec*(parser: Parser): Result[(Identifier,
    Identifier), Error] =
  let name = ? parser.expect(identifier_spec)
  discard ? parser.expect(optional_space_spec)
  discard ? parser.expect(colon_spec)
  discard ? parser.expect(optional_space_spec)
  let value = ? parser.expect(identifier_spec)
  ok((name, value))

# =============================================================================
# StructPattern
# =============================================================================

type
  StructPatternKind* = enum
    SPK_DEFAULT, SPK_NAMED
  StructPattern* = ref object of RootObj
    location: Location
    args: seq[(Identifier, Identifier)]
    case kind: StructPatternKind
    of SPK_DEFAULT: discard
    of SPK_NAMED: struct: Identifier

proc new_struct_pattern*(args: seq[(Identifier, Identifier)],
    location: Location): Result[StructPattern, Error] =
  if args.len == 0:
    return err(err_parser_empty_arg_list(location))
  if args.len > MAX_ARGS_LENGTH:
    return err(err_parser_arg_list_too_long(location, args.len))

  var keys_map: Table[Identifier, int]
  var values_map: Table[Identifier, int]
  for index, (key, value) in args.pairs:
    if key in keys_map:
      let predefined_field_location = args[keys_map[key]][0].location
      return err(err_parser_arg_already_defined(key.location, key.asl,
          predefined_field_location))
    keys_map[key] = index

    if value in values_map:
      let predefined_field_location = args[values_map[value]][1].location
      return err(err_parser_arg_already_defined(value.location, value.asl,
          predefined_field_location))
    values_map[value] = index

  ok(StructPattern(kind: SPK_DEFAULT, args: args, location: location))

proc new_struct_pattern*(struct: Identifier, pattern: StructPattern): Result[
    StructPattern, Error] =
  case pattern.kind:
  of SPK_DEFAULT:
    ok(StructPattern(kind: SPK_NAMED, location: struct.location, struct: struct,
        args: pattern.args))
  of SPK_NAMED:
    err(err_parser_struct_conversion_error(struct.location))

proc location*(pattern: StructPattern): Location = pattern.location
proc kind*(pattern: StructPattern): StructPatternKind = pattern.kind
proc args*(pattern: StructPattern): seq[(Identifier, Identifier)] = pattern.args

proc struct*(pattern: StructPattern): Result[Identifier, string] =
  case pattern.kind:
  of SPK_DEFAULT: err(fmt"{pattern.location} expected a named struct but found a default struct")
  of SPK_NAMED: ok(pattern.struct)

proc asl*(pattern: StructPattern): string =
  var args: seq[string]
  for (key, val) in pattern.args:
    args.add(fmt"{key.asl}: {val.asl}")

  case pattern.kind:
  of SPK_DEFAULT: "{ " & args.join(", ") & " }"
  of SPK_NAMED: pattern.struct.asl & " { " & args.join(", ") & " }"

proc struct_pattern_default_spec*(parser: Parser): Result[StructPattern,
    Error] =
  let open_curly = ? parser.expect(open_curly_bracket_spec)
  discard ? parser.expect(optional_space_spec)

  var keywords: seq[(Identifier, Identifier)]
  keywords.add( ? parser.expect(keyword_value_identifier_spec))
  discard ? parser.expect(optional_space_spec)
  var maybe_comma = parser.expect(comma_spec)
  while maybe_comma.is_ok:
    discard ? parser.expect(optional_space_spec)
    keywords.add( ? parser.expect(keyword_value_identifier_spec))
    discard ? parser.expect(optional_space_spec)
    maybe_comma = parser.expect(comma_spec)

  discard ? parser.expect(close_curly_bracket_spec)
  new_struct_pattern(keywords, open_curly.location)

proc struct_pattern_named_spec*(parser: Parser): Result[StructPattern,
    Error] =
  let struct = ? parser.expect(identifier_spec)
  discard ? parser.expect(optional_space_spec)
  let struct_pattern_default = ? parser.expect(struct_pattern_default_spec)
  new_struct_pattern(struct, struct_pattern_default)

proc struct_pattern_spec*(parser: Parser): Result[StructPattern, Error] =
  let maybe_struct_pattern_named = parser.expect(struct_pattern_named_spec)
  if maybe_struct_pattern_named.is_ok:
    maybe_struct_pattern_named
  else:
    parser.expect(struct_pattern_default_spec)

# =============================================================================
# CasePattern
# =============================================================================

type
  CasePatternKind* = enum
    CPK_LITERAL, CPK_STRUCT
  CasePattern* = ref object of RootObj
    case kind: CasePatternKind
    of CPK_LITERAL: literal: Literal
    of CPK_STRUCT: struct: StructPattern

proc new_case_pattern*(literal: Literal): CasePattern =
  CasePattern(kind: CPK_LITERAL, literal: literal)

proc new_case_pattern*(struct: StructPattern): CasePattern =
  CasePattern(kind: CPK_STRUCT, struct: struct)

proc location*(pattern: CasePattern): Location =
  case pattern.kind:
  of CPK_LITERAL: pattern.literal.location
  of CPK_STRUCT: pattern.struct.location

proc kind*(pattern: CasePattern): CasePatternKind = pattern.kind

proc literal*(pattern: CasePattern): Result[Literal, string] =
  case pattern.kind:
  of CPK_LITERAL: ok(pattern.literal)
  of CPK_STRUCT: err(fmt"{pattern.location} expected case pattern to be literal but struct was found")

proc struct*(pattern: CasePattern): Result[StructPattern, string] =
  case pattern.kind:
  of CPK_LITERAL: err(fmt"{pattern.location} expected case pattern to be struct but literal was found")
  of CPK_STRUCT: ok(pattern.struct)

proc asl*(pattern: CasePattern): string =
  case pattern.kind:
  of CPK_LITERAL: pattern.literal.asl
  of CPK_STRUCT: pattern.struct.asl

proc case_pattern_spec*(parser: Parser): Result[CasePattern, Error] =
  var errors: seq[Error]

  let maybe_struct_pattern = parser.expect(struct_pattern_spec)
  if maybe_struct_pattern.is_ok: return ok(new_case_pattern(
      maybe_struct_pattern.get))
  else: errors.add(maybe_struct_pattern.error)

  let maybe_literal = parser.expect(literal_spec)
  if maybe_literal.is_ok: return ok(new_case_pattern(maybe_literal.get))
  else: errors.add(maybe_literal.error)

  err(errors.max())

# =============================================================================
# CaseDefinition
# =============================================================================

type CaseDefinition* = ref object of RootObj
  pattern: CasePattern
  location: Location

proc new_case_definition*(pattern: CasePattern,
    location: Location): CaseDefinition =
  CaseDefinition(pattern: pattern, location: location)

proc location*(def: CaseDefinition): Location = def.location
proc pattern*(def: CaseDefinition): CasePattern = def.pattern

proc asl*(def: CaseDefinition): string =
  fmt"case {def.pattern.asl}:"

proc case_definition_spec*(parser: Parser): Result[CaseDefinition,
    Error] =
  let case_keyword = ? parser.expect(case_keyword_spec)
  discard ? parser.expect(space_spec)
  discard ? parser.expect(optional_space_spec)
  let pattern = ? parser.expect(case_pattern_spec)
  discard ? parser.expect(optional_space_spec)
  discard ? parser.expect(colon_spec)
  ok(new_case_definition(pattern, case_keyword.location))
