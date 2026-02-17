import results, strformat

import core, identifier, module_ref, literal, arg
import ../../utils

# =============================================================================
# LiteralInit
# =============================================================================

struct LiteralInit:
  module: ModuleRef
  literal: Literal

proc new_literal_init*(module: ModuleRef, literal: Literal): LiteralInit =
  LiteralInit(module: module, literal: literal)

proc location*(init: LiteralInit): Location =
  init.module.location

proc asl*(init: LiteralInit): string =
  fmt"{init.module.asl} {init.literal.asl}"

proc literal_init_spec*(parser: Parser): Result[LiteralInit, core.Error] =
  let module_ref = ? parser.expect(module_ref_spec)
  discard ? parser.expect_at_least_one(space_spec)
  let literal = ? parser.expect(literal_spec)
  ok(new_literal_init(module_ref, literal))

# =============================================================================
# Initializer
# =============================================================================

union Initializer:
  IK_LITERAL:
    literal: LiteralInit
  IK_STRUCT:
    struct: StructInit

proc new_initializer*(literal: LiteralInit): Initializer =
  Initializer(kind: IK_LITERAL, literal: literal)

proc new_initializer*(struct: StructInit): Initializer =
  Initializer(kind: IK_STRUCT, struct: struct)

proc location*(init: Initializer): Location =
  variant init:
  of IK_LITERAL(literal): literal.location
  of IK_STRUCT(struct): struct.location

proc asl*(init: Initializer): string =
  variant init:
  of IK_LITERAL(literal): literal.asl
  of IK_STRUCT(struct): struct.asl

proc initializer_spec*(parser: Parser): Result[Initializer, core.Error] =
  var errors: seq[core.Error]
  let maybe_literal_init = parser.expect(literal_init_spec)
  if maybe_literal_init.is_ok: return ok(new_initializer(
      maybe_literal_init.get))
  else: errors.add(maybe_literal_init.error)

  let maybe_struct_init = parser.expect(struct_init_spec)
  if maybe_struct_init.is_ok: return ok(new_initializer(maybe_struct_init.get))
  else: errors.add(maybe_struct_init.error)

  err(errors.max())

# =============================================================================
# StructGet
# =============================================================================

struct StructGet:
  name: Identifier
  field: Identifier

proc new_struct_get*(name: Identifier, field: Identifier): StructGet =
  StructGet(name: name, field: field)

proc location*(struct_get: StructGet): Location = struct_get.name.location

proc asl*(struct_get: StructGet): string =
  fmt"{struct_get.name.asl}.{struct_get.field.asl}"

proc struct_get_spec*(parser: Parser): Result[StructGet, core.Error] =
  let name = ? parser.expect(identifier_spec)
  discard ? parser.expect(dot_spec)
  let field = ? parser.expect(identifier_spec)
  ok(new_struct_get(name, field))
