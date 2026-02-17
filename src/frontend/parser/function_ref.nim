import results, strformat

import core, identifier, module_ref
import ../../utils

# =============================================================================
# FunctionRef
# =============================================================================

union FunctionRef:
  name: Identifier
  FRK_LOCAL
  FRK_MODULE:
    module: ModuleRef

proc new_function_ref*(name: Identifier): FunctionRef =
  FunctionRef(kind: FRK_LOCAL, name: name)

proc new_function_ref*(name: Identifier, module: ModuleRef): FunctionRef =
  FunctionRef(kind: FRK_MODULE, name: name, module: module)

proc location*(fnref: FunctionRef): Location =
  variant fnref:
  of FRK_LOCAL: fnref.name.location
  of FRK_MODULE(module): module.location

proc asl*(fnref: FunctionRef): string =
  variant fnref:
  of FRK_LOCAL: fnref.name.asl
  of FRK_MODULE(module): fmt"{module.asl}.{fnref.name.asl}"

proc function_ref_local_spec(parser: Parser): Result[FunctionRef,
    core.Error] =
  let name = ? parser.expect(identifier_spec)
  ok(new_function_ref(name))

proc function_ref_module_spec(parser: Parser): Result[FunctionRef,
    core.Error] =
  let module_ref = ? parser.expect(module_ref_spec)
  discard ? parser.expect(dot_spec)
  let name = ? parser.expect(identifier_spec)
  ok(new_function_ref(name, module_ref))

proc function_ref_spec*(parser: Parser): Result[FunctionRef, core.Error] =
  parser.expect_one_of([function_ref_module_spec, function_ref_local_spec])
