# ResolvedFunctionRef, ResolvedFunctionCall, ResolvedStructGet, ResolvedVariable
import results, strformat, sets

import initializer
export initializer

# =============================================================================
# ResolvedFunctionRef
# =============================================================================

type
  ResolvedFunctionRefKind* = enum
    TFRK_LOCAL, TFRK_MODULE
  ResolvedFunctionRef* = ref object of RootObj
    name: Identifier
    arity: uint
    case kind: ResolvedFunctionRefKind
    of TFRK_LOCAL: discard
    of TFRK_MODULE: module_ref: ResolvedModuleRef

proc new_resolved_function_ref*(name: Identifier,
    arity: uint): ResolvedFunctionRef =
  ResolvedFunctionRef(kind: TFRK_LOCAL, name: name, arity: arity)

proc new_resolved_function_ref*(module_ref: ResolvedModuleRef, name: Identifier,
    arity: uint): ResolvedFunctionRef =
  ResolvedFunctionRef(kind: TFRK_MODULE, module_ref: module_ref, name: name, arity: arity)

proc module_deps*(fnref: ResolvedFunctionRef): HashSet[UserModule] =
  case fnref.kind:
  of TFRK_LOCAL: init_hashset[UserModule]()
  of TFRK_MODULE: fnref.module_ref.module_deps

proc location*(fnref: ResolvedFunctionRef): Location =
  case fnref.kind:
  of TFRK_LOCAL: fnref.name.location
  of TFRK_MODULE: fnref.module_ref.location

proc kind*(fnref: ResolvedFunctionRef): ResolvedFunctionRefKind = fnref.kind
proc name*(fnref: ResolvedFunctionRef): Identifier = fnref.name
proc arity*(fnref: ResolvedFunctionRef): uint = fnref.arity

proc module_ref*(fnref: ResolvedFunctionRef): Result[ResolvedModuleRef, string] =
  case fnref.kind:
  of TFRK_LOCAL: err(fmt"{fnref.location} expected a module function call")
  of TFRK_MODULE: ok(fnref.module_ref)

# =============================================================================
# ResolvedFunctionCall
# =============================================================================

type ResolvedFunctionCall* = ref object of RootObj
  fnref: ResolvedFunctionRef
  args: seq[Argument]

proc new_resolved_function_call*(fnref: ResolvedFunctionRef, args: seq[
    Argument]): ResolvedFunctionCall =
  ResolvedFunctionCall(fnref: fnref, args: args)

proc module_deps*(fncall: ResolvedFunctionCall): HashSet[UserModule] =
  fncall.fnref.module_deps

proc location*(fncall: ResolvedFunctionCall): Location = fncall.fnref.location
proc fnref*(fncall: ResolvedFunctionCall): ResolvedFunctionRef = fncall.fnref
proc args*(fncall: ResolvedFunctionCall): seq[Argument] = fncall.args

# =============================================================================
# ResolvedStructGet
# =============================================================================

type ResolvedStructGet* = ref object of RootObj
  variable: Identifier
  field: Identifier

proc new_resolved_struct_get*(variable: Identifier,
    field: Identifier): ResolvedStructGet =
  ResolvedStructGet(variable: variable, field: field)

proc module_deps*(struct_get: ResolvedStructGet): HashSet[UserModule] =
  init_hashset[UserModule]()

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

proc module_deps*(variable: ResolvedVariable): HashSet[UserModule] =
  init_hashset[UserModule]()
