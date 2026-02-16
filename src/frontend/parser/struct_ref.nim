import results, strformat

import core, identifier, module_ref

# =============================================================================
# StructRef
# =============================================================================

type
  StructRefKind* = enum
    SRK_DEFAULT, SRK_NAMED
  StructRef* = ref object of RootObj
    module: ModuleRef
    case kind: StructRefKind
    of SRK_DEFAULT: discard
    of SRK_NAMED: struct: Identifier

proc new_struct_ref*(module: ModuleRef): StructRef =
  StructRef(kind: SRK_DEFAULT, module: module)

proc new_struct_ref*(module: ModuleRef, struct: Identifier): StructRef =
  StructRef(kind: SRK_NAMED, module: module, struct: struct)

proc location*(struct_ref: StructRef): Location =
  struct_ref.module.location

proc kind*(struct_ref: StructRef): StructRefKind = struct_ref.kind
proc module*(struct_ref: StructRef): ModuleRef = struct_ref.module

proc struct*(struct_ref: StructRef): Identifier =
  do_assert struct_ref.kind == SRK_NAMED, fmt"{struct_ref.location} expected named struct"
  struct_ref.struct

proc asl*(struct_ref: StructRef): string =
  case struct_ref.kind:
  of SRK_DEFAULT: struct_ref.module.asl
  of SRK_NAMED: fmt"{struct_ref.module.asl}.{struct_ref.struct.asl}"

proc struct_ref_spec*(parser: Parser): Result[StructRef, core.Error] =
  let module = ? parser.expect(module_ref_spec)
  let maybe_dot = parser.expect(dot_spec)
  if maybe_dot.is_ok:
    let struct = ? parser.expect(identifier_spec)
    ok(new_struct_ref(module, struct))
  else:
    ok(new_struct_ref(module))
