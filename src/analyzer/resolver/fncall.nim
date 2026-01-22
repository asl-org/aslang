# ResolvedUserFunctionRef, ResolvedUserFunctionCall, ResolvedStructGet, ResolvedVariable
import results, strformat, sets, options

import initializer
export initializer

# =============================================================================
# ResolvedUserFunctionRef
# =============================================================================

type
  ResolvedUserFunctionRefKind* = enum
    TFRK_LOCAL, TFRK_MODULE
  ResolvedUserFunctionRef* = ref object of RootObj
    name: Identifier
    arity: uint
    case kind: ResolvedUserFunctionRefKind
    of TFRK_LOCAL: discard
    of TFRK_MODULE: module_ref: ResolvedModuleRef

proc new_resolved_function_ref*(name: Identifier,
    arity: uint): ResolvedUserFunctionRef =
  ResolvedUserFunctionRef(kind: TFRK_LOCAL, name: name, arity: arity)

proc new_resolved_function_ref*(module_ref: ResolvedModuleRef, name: Identifier,
    arity: uint): ResolvedUserFunctionRef =
  ResolvedUserFunctionRef(kind: TFRK_MODULE, module_ref: module_ref, name: name, arity: arity)

proc module_deps*(fnref: ResolvedUserFunctionRef): HashSet[Module] =
  case fnref.kind:
  of TFRK_LOCAL: init_hashset[Module]()
  of TFRK_MODULE: fnref.module_ref.module_deps

proc location*(fnref: ResolvedUserFunctionRef): Location =
  case fnref.kind:
  of TFRK_LOCAL: fnref.name.location
  of TFRK_MODULE: fnref.module_ref.location

proc kind*(fnref: ResolvedUserFunctionRef): ResolvedUserFunctionRefKind = fnref.kind
proc name*(fnref: ResolvedUserFunctionRef): Identifier = fnref.name
proc arity*(fnref: ResolvedUserFunctionRef): uint = fnref.arity

proc module_ref*(fnref: ResolvedUserFunctionRef): Result[ResolvedModuleRef, string] =
  case fnref.kind:
  of TFRK_LOCAL: err(fmt"{fnref.location} expected a module function call")
  of TFRK_MODULE: ok(fnref.module_ref)

proc resolve*(file: parser.File, module: Option[parser.Module],
    fnref: FunctionRef, arity: uint): Result[ResolvedUserFunctionRef, string] =
  case fnref.kind:
  of FRK_LOCAL: ok(new_resolved_function_ref(fnref.name, arity))
  of FRK_MODULE:
    let module_ref = ? resolve(file, module, ? fnref.module)
    ok(new_resolved_function_ref(module_ref, fnref.name, arity))

# =============================================================================
# ResolvedUserFunctionCall
# =============================================================================

type ResolvedUserFunctionCall* = ref object of RootObj
  fnref: ResolvedUserFunctionRef
  args: seq[Argument]

proc new_resolved_function_call*(fnref: ResolvedUserFunctionRef, args: seq[
    Argument]): ResolvedUserFunctionCall =
  ResolvedUserFunctionCall(fnref: fnref, args: args)

proc module_deps*(fncall: ResolvedUserFunctionCall): HashSet[Module] =
  fncall.fnref.module_deps

proc location*(fncall: ResolvedUserFunctionCall): Location = fncall.fnref.location
proc fnref*(fncall: ResolvedUserFunctionCall): ResolvedUserFunctionRef = fncall.fnref
proc args*(fncall: ResolvedUserFunctionCall): seq[Argument] = fncall.args

proc resolve*(file: parser.File, module: Option[parser.Module],
    fncall: FunctionCall): Result[ResolvedUserFunctionCall, string] =
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
