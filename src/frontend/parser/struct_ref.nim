import results, strformat

import core, identifier, module_ref
import ../../utils

# =============================================================================
# StructRef
# =============================================================================

union StructRef:
  module: ModuleRef
  SRK_DEFAULT
  SRK_NAMED:
    struct: Identifier

proc new_struct_ref*(module: ModuleRef): StructRef =
  StructRef(kind: SRK_DEFAULT, module: module)

proc new_struct_ref*(module: ModuleRef, struct: Identifier): StructRef =
  StructRef(kind: SRK_NAMED, module: module, struct: struct)

proc location*(struct_ref: StructRef): Location =
  struct_ref.module.location

proc asl*(struct_ref: StructRef): string =
  variant struct_ref:
  of SRK_DEFAULT: struct_ref.module.asl
  of SRK_NAMED(struct): fmt"{struct_ref.module.asl}.{struct.asl}"

proc struct_ref_spec*(parser: Parser): Result[StructRef, core.Error] =
  let module = ? parser.expect(module_ref_spec)
  let maybe_dot = parser.expect(dot_spec)
  if maybe_dot.is_ok:
    let struct = ? parser.expect(identifier_spec)
    ok(new_struct_ref(module, struct))
  else:
    ok(new_struct_ref(module))
