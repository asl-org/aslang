# TypedFunctionRef, TypedFunctionCall, TypedStructGet, TypedVariable
import results, strformat, sets

import typed_init
export typed_init

# =============================================================================
# TypedFunctionRef
# =============================================================================

type
  TypedFunctionRefKind* = enum
    TFRK_LOCAL, TFRK_MODULE
  TypedFunctionRef* = ref object of RootObj
    name: Identifier
    arity: uint
    case kind: TypedFunctionRefKind
    of TFRK_LOCAL: discard
    of TFRK_MODULE: module_ref: TypedModuleRef

proc new_typed_function_ref*(name: Identifier, arity: uint): TypedFunctionRef =
  TypedFunctionRef(kind: TFRK_LOCAL, name: name, arity: arity)

proc new_typed_function_ref*(module_ref: TypedModuleRef, name: Identifier,
    arity: uint): TypedFunctionRef =
  TypedFunctionRef(kind: TFRK_MODULE, module_ref: module_ref, name: name, arity: arity)

proc module_deps*(fnref: TypedFunctionRef): HashSet[UserModule] =
  case fnref.kind:
  of TFRK_LOCAL: init_hashset[UserModule]()
  of TFRK_MODULE: fnref.module_ref.module_deps

proc location*(fnref: TypedFunctionRef): Location =
  case fnref.kind:
  of TFRK_LOCAL: fnref.name.location
  of TFRK_MODULE: fnref.module_ref.location

proc kind*(fnref: TypedFunctionRef): TypedFunctionRefKind = fnref.kind
proc name*(fnref: TypedFunctionRef): Identifier = fnref.name
proc arity*(fnref: TypedFunctionRef): uint = fnref.arity

proc module_ref*(fnref: TypedFunctionRef): Result[TypedModuleRef, string] =
  case fnref.kind:
  of TFRK_LOCAL: err(fmt"{fnref.location} expected a module function call")
  of TFRK_MODULE: ok(fnref.module_ref)

# =============================================================================
# TypedFunctionCall
# =============================================================================

type TypedFunctionCall* = ref object of RootObj
  fnref: TypedFunctionRef
  args: seq[Argument]

proc new_typed_function_call*(fnref: TypedFunctionRef, args: seq[
    Argument]): TypedFunctionCall =
  TypedFunctionCall(fnref: fnref, args: args)

proc module_deps*(fncall: TypedFunctionCall): HashSet[UserModule] =
  fncall.fnref.module_deps

proc location*(fncall: TypedFunctionCall): Location = fncall.fnref.location
proc fnref*(fncall: TypedFunctionCall): TypedFunctionRef = fncall.fnref
proc args*(fncall: TypedFunctionCall): seq[Argument] = fncall.args

# =============================================================================
# TypedStructGet
# =============================================================================

type TypedStructGet* = ref object of RootObj
  variable: Identifier
  field: Identifier

proc new_typed_struct_get*(variable: Identifier,
    field: Identifier): TypedStructGet =
  TypedStructGet(variable: variable, field: field)

proc module_deps*(struct_get: TypedStructGet): HashSet[UserModule] =
  init_hashset[UserModule]()

proc location*(struct_get: TypedStructGet): Location = struct_get.variable.location
proc variable*(struct_get: TypedStructGet): Identifier = struct_get.variable
proc field*(struct_get: TypedStructGet): Identifier = struct_get.field

# =============================================================================
# TypedVariable
# =============================================================================

type TypedVariable* = ref object of RootObj
  name: Identifier

proc new_typed_variable*(name: Identifier): TypedVariable =
  TypedVariable(name: name)

proc location*(variable: TypedVariable): Location = variable.name.location
proc name*(variable: TypedVariable): Identifier = variable.name

proc module_deps*(variable: TypedVariable): HashSet[UserModule] =
  init_hashset[UserModule]()
