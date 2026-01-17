# ResolvedLiteralInit, ResolvedStructRef, ResolvedStructInit, ResolvedInitializer
import results, strformat, sets

import defs
export defs

# =============================================================================
# ResolvedLiteralInit
# =============================================================================

type ResolvedLiteralInit* = ref object of RootObj
  module_ref: ResolvedModuleRef
  literal: Literal

proc new_resolved_literal_init*(module_ref: ResolvedModuleRef,
    literal: Literal): ResolvedLiteralInit =
  ResolvedLiteralInit(module_ref: module_ref, literal: literal)

proc location*(init: ResolvedLiteralInit): Location = init.module_ref.location
proc module_ref*(init: ResolvedLiteralInit): ResolvedModuleRef = init.module_ref
proc literal*(init: ResolvedLiteralInit): Literal = init.literal

proc module_deps*(init: ResolvedLiteralInit): HashSet[UserModule] =
  init.module_ref.module_deps

# =============================================================================
# ResolvedStructRef
# =============================================================================

type
  ResolvedStructRefKind* = enum
    TSRK_DEFAULT, TSRK_NAMED
  ResolvedStructRef* = ref object of RootObj
    module_ref: ResolvedModuleRef
    case kind: ResolvedStructRefKind
    of TSRK_DEFAULT: discard
    of TSRK_NAMED: name: Identifier

proc new_resolved_struct_ref*(module_ref: ResolvedModuleRef): ResolvedStructRef =
  ResolvedStructRef(kind: TSRK_DEFAULT, module_ref: module_ref)

proc new_resolved_struct_ref*(module_ref: ResolvedModuleRef,
    name: Identifier): ResolvedStructRef =
  ResolvedStructRef(kind: TSRK_NAMED, module_ref: module_ref, name: name)

proc module_deps*(struct_ref: ResolvedStructRef): HashSet[UserModule] =
  struct_ref.module_ref.module_deps

proc location*(struct_ref: ResolvedStructRef): Location = struct_ref.module_ref.location
proc kind*(struct_ref: ResolvedStructRef): ResolvedStructRefKind = struct_ref.kind
proc module_ref*(struct_ref: ResolvedStructRef): ResolvedModuleRef = struct_ref.module_ref

proc name*(struct_ref: ResolvedStructRef): Result[Identifier, string] =
  case struct_ref.kind:
  of TSRK_NAMED: ok(struct_ref.name)
  of TSRK_DEFAULT: err(fmt"{struct_ref.location} expected a named struct")

# =============================================================================
# ResolvedStructInit
# =============================================================================

type ResolvedStructInit* = ref object of RootObj
  struct_ref: ResolvedStructRef
  args: seq[KeywordArgument]

proc new_resolved_struct_init*(struct_ref: ResolvedStructRef, args: seq[
    KeywordArgument]): ResolvedStructInit =
  ResolvedStructInit(struct_ref: struct_ref, args: args)

proc module_deps*(init: ResolvedStructInit): HashSet[UserModule] =
  init.struct_ref.module_deps

proc location*(init: ResolvedStructInit): Location = init.struct_ref.location
proc struct_ref*(init: ResolvedStructInit): ResolvedStructRef = init.struct_ref
proc fields*(init: ResolvedStructInit): seq[KeywordArgument] = init.args

# =============================================================================
# ResolvedInitializer
# =============================================================================

type
  ResolvedInitializerKind* = enum
    TIK_LITERAL, TIK_STRUCT
  ResolvedInitializer* = ref object of RootObj
    case kind: ResolvedInitializerKind
    of TIK_LITERAL: literal: ResolvedLiteralInit
    of TIK_STRUCT: struct: ResolvedStructInit

proc new_resolved_initializer*(literal: ResolvedLiteralInit): ResolvedInitializer =
  ResolvedInitializer(kind: TIK_LITERAL, literal: literal)

proc new_resolved_initializer*(struct: ResolvedStructInit): ResolvedInitializer =
  ResolvedInitializer(kind: TIK_STRUCT, struct: struct)

proc location*(init: ResolvedInitializer): Location =
  case init.kind:
  of TIK_LITERAL: init.literal.location
  of TIK_STRUCT: init.struct.location

proc kind*(init: ResolvedInitializer): ResolvedInitializerKind = init.kind

proc struct*(init: ResolvedInitializer): Result[ResolvedStructInit, string] =
  case init.kind:
  of TIK_STRUCT: ok(init.struct)
  else: err(fmt"{init.location} expected a struct initializer")

proc literal*(init: ResolvedInitializer): Result[ResolvedLiteralInit, string] =
  case init.kind:
  of TIK_LITERAL: ok(init.literal)
  else: err(fmt"{init.location} expected a literal initializer")

proc module_deps*(init: ResolvedInitializer): HashSet[UserModule] =
  case init.kind:
  of TIK_LITERAL: init.literal.module_deps
  of TIK_STRUCT: init.struct.module_deps
