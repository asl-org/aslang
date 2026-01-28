# ResolvedFunctionRef, ResolvedFunctionCall, ResolvedStructGet, ResolvedVariable
import results, strformat, sets, options

import parser
import module_ref

# =============================================================================
# ResolvedFunctionRef
# =============================================================================

type
  ResolvedFunctionRefKind* = enum
    RFRK_LOCAL, RFRK_MODULE
  ResolvedFunctionRef* = ref object of RootObj
    name: Identifier
    arity: uint
    case kind: ResolvedFunctionRefKind
    of RFRK_LOCAL: discard
    of RFRK_MODULE: module_ref: ResolvedModuleRef

proc new_resolved_function_ref*(name: Identifier,
    arity: uint): ResolvedFunctionRef =
  ResolvedFunctionRef(kind: RFRK_LOCAL, name: name, arity: arity)

proc new_resolved_function_ref*(module_ref: ResolvedModuleRef, name: Identifier,
    arity: uint): ResolvedFunctionRef =
  ResolvedFunctionRef(kind: RFRK_MODULE, module_ref: module_ref, name: name, arity: arity)

proc module_deps*(fnref: ResolvedFunctionRef): HashSet[Module] =
  case fnref.kind:
  of RFRK_LOCAL: init_hashset[Module]()
  of RFRK_MODULE: fnref.module_ref.module_deps

proc location*(fnref: ResolvedFunctionRef): Location =
  case fnref.kind:
  of RFRK_LOCAL: fnref.name.location
  of RFRK_MODULE: fnref.module_ref.location

proc kind*(fnref: ResolvedFunctionRef): ResolvedFunctionRefKind = fnref.kind
proc name*(fnref: ResolvedFunctionRef): Identifier = fnref.name
proc arity*(fnref: ResolvedFunctionRef): uint = fnref.arity

proc module_ref*(fnref: ResolvedFunctionRef): Result[ResolvedModuleRef, string] =
  case fnref.kind:
  of RFRK_LOCAL: err(fmt"{fnref.location} expected a module function call")
  of RFRK_MODULE: ok(fnref.module_ref)

proc resolve*(file: parser.File, module: Option[parser.Module],
    fnref: FunctionRef, arity: uint): Result[ResolvedFunctionRef, string] =
  case fnref.kind:
  of FRK_LOCAL: ok(new_resolved_function_ref(fnref.name, arity))
  of FRK_MODULE:
    let module_ref = ? resolve(file, module, ? fnref.module)
    ok(new_resolved_function_ref(module_ref, fnref.name, arity))

# =============================================================================
# ResolvedFunctionCall
# =============================================================================

type ResolvedFunctionCall* = ref object of RootObj
  fnref: ResolvedFunctionRef
  args: seq[Argument]

proc new_resolved_function_call*(fnref: ResolvedFunctionRef, args: seq[
    Argument]): ResolvedFunctionCall =
  ResolvedFunctionCall(fnref: fnref, args: args)

proc module_deps*(fncall: ResolvedFunctionCall): HashSet[Module] =
  fncall.fnref.module_deps

proc location*(fncall: ResolvedFunctionCall): Location = fncall.fnref.location
proc fnref*(fncall: ResolvedFunctionCall): ResolvedFunctionRef = fncall.fnref
proc args*(fncall: ResolvedFunctionCall): seq[Argument] = fncall.args

proc resolve*(file: parser.File, module: Option[parser.Module],
    fncall: FunctionCall): Result[ResolvedFunctionCall, string] =
  let fnref = ? resolve(file, module, fncall.fnref, fncall.args.len.uint)
  ok(new_resolved_function_call(fnref, fncall.args))

# =============================================================================
# ResolvedStructGet
# =============================================================================

type ResolvedStructGet* = ref object of RootObj
  variable: Identifier
  field: Identifier

proc new_resolved_struct_get*(variable: Identifier,
    field: Identifier): ResolvedStructGet =
  ResolvedStructGet(variable: variable, field: field)

proc module_deps*(struct_get: ResolvedStructGet): HashSet[Module] =
  init_hashset[Module]()

proc location*(struct_get: ResolvedStructGet): Location = struct_get.variable.location
proc variable*(struct_get: ResolvedStructGet): Identifier = struct_get.variable
proc field*(struct_get: ResolvedStructGet): Identifier = struct_get.field

# =============================================================================
# ResolvedVariable
# =============================================================================

type ResolvedVariable* = ref object of RootObj
  name: Identifier

proc new_resolved_variable*(name: Identifier): ResolvedVariable =
  ResolvedVariable(name: name)

proc location*(variable: ResolvedVariable): Location = variable.name.location
proc name*(variable: ResolvedVariable): Identifier = variable.name

proc module_deps*(variable: ResolvedVariable): HashSet[Module] =
  init_hashset[Module]()
