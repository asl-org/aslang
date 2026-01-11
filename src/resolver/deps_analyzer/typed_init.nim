# TypedLiteralInit, TypedStructRef, TypedStructInit, TypedInitializer
import results, strformat, sets

import typed_defs
export typed_defs

# =============================================================================
# TypedLiteralInit
# =============================================================================

type TypedLiteralInit* = ref object of RootObj
  module_ref: TypedModuleRef
  literal: Literal

proc new_typed_literal_init*(module_ref: TypedModuleRef,
    literal: Literal): TypedLiteralInit =
  TypedLiteralInit(module_ref: module_ref, literal: literal)

proc location*(init: TypedLiteralInit): Location = init.module_ref.location
proc module_ref*(init: TypedLiteralInit): TypedModuleRef = init.module_ref
proc literal*(init: TypedLiteralInit): Literal = init.literal

proc module_deps*(init: TypedLiteralInit): HashSet[UserModule] =
  init.module_ref.module_deps

# =============================================================================
# TypedStructRef
# =============================================================================

type
  TypedStructRefKind* = enum
    TSRK_DEFAULT, TSRK_NAMED
  TypedStructRef* = ref object of RootObj
    module_ref: TypedModuleRef
    case kind: TypedStructRefKind
    of TSRK_DEFAULT: discard
    of TSRK_NAMED: name: Identifier

proc new_typed_struct_ref*(module_ref: TypedModuleRef): TypedStructRef =
  TypedStructRef(kind: TSRK_DEFAULT, module_ref: module_ref)

proc new_typed_struct_ref*(module_ref: TypedModuleRef,
    name: Identifier): TypedStructRef =
  TypedStructRef(kind: TSRK_NAMED, module_ref: module_ref, name: name)

proc module_deps*(struct_ref: TypedStructRef): HashSet[UserModule] =
  struct_ref.module_ref.module_deps

proc location*(struct_ref: TypedStructRef): Location = struct_ref.module_ref.location
proc kind*(struct_ref: TypedStructRef): TypedStructRefKind = struct_ref.kind
proc module_ref*(struct_ref: TypedStructRef): TypedModuleRef = struct_ref.module_ref

proc name*(struct_ref: TypedStructRef): Result[Identifier, string] =
  case struct_ref.kind:
  of TSRK_NAMED: ok(struct_ref.name)
  of TSRK_DEFAULT: err(fmt"{struct_ref.location} expected a named struct")

# =============================================================================
# TypedStructInit
# =============================================================================

type TypedStructInit* = ref object of RootObj
  struct_ref: TypedStructRef
  args: seq[KeywordArgument]

proc new_typed_struct_init*(struct_ref: TypedStructRef, args: seq[
    KeywordArgument]): TypedStructInit =
  TypedStructInit(struct_ref: struct_ref, args: args)

proc module_deps*(init: TypedStructInit): HashSet[UserModule] =
  init.struct_ref.module_deps

proc location*(init: TypedStructInit): Location = init.struct_ref.location
proc struct_ref*(init: TypedStructInit): TypedStructRef = init.struct_ref
proc fields*(init: TypedStructInit): seq[KeywordArgument] = init.args

# =============================================================================
# TypedInitializer
# =============================================================================

type
  TypedInitializerKind* = enum
    TIK_LITERAL, TIK_STRUCT
  TypedInitializer* = ref object of RootObj
    case kind: TypedInitializerKind
    of TIK_LITERAL: literal: TypedLiteralInit
    of TIK_STRUCT: struct: TypedStructInit

proc new_typed_initializer*(literal: TypedLiteralInit): TypedInitializer =
  TypedInitializer(kind: TIK_LITERAL, literal: literal)

proc new_typed_initializer*(struct: TypedStructInit): TypedInitializer =
  TypedInitializer(kind: TIK_STRUCT, struct: struct)

proc location*(init: TypedInitializer): Location =
  case init.kind:
  of TIK_LITERAL: init.literal.location
  of TIK_STRUCT: init.struct.location

proc kind*(init: TypedInitializer): TypedInitializerKind = init.kind

proc struct*(init: TypedInitializer): Result[TypedStructInit, string] =
  case init.kind:
  of TIK_STRUCT: ok(init.struct)
  else: err(fmt"{init.location} expected a struct initializer")

proc literal*(init: TypedInitializer): Result[TypedLiteralInit, string] =
  case init.kind:
  of TIK_LITERAL: ok(init.literal)
  else: err(fmt"{init.location} expected a literal initializer")

proc module_deps*(init: TypedInitializer): HashSet[UserModule] =
  case init.kind:
  of TIK_LITERAL: init.literal.module_deps
  of TIK_STRUCT: init.struct.module_deps
