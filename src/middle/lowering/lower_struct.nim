import strformat, sequtils, algorithm

import ../analyzer
import ../../ir/constructors
import ../../backend/emitter
import lower_module_ref
import lower_arg_def
import lower_literal

proc impl_id_params(generics: uint64): seq[(CType, string)] =
  for i in 0.uint64..<generics:
    result.add((c_named("U64"), fmt"__asl_impl_id_{i}"))

proc impl_id_args(generics: uint64): seq[CExpr] =
  for i in 0.uint64..<generics:
    result.add(c_ident(fmt"__asl_impl_id_{i}"))

proc generate_struct_decls*(struct: AnalyzedStruct, prefix: string,
    generics: uint64 = 0): seq[CDecl] =
  let fields = struct.fields.sorted(proc(a,
      b: AnalyzedArgumentDefinition): int =
    if a.generate_byte_size > b.generate_byte_size: -1
    elif b.generate_byte_size > a.generate_byte_size: 1
    else: 0
  )

  let id_params = impl_id_params(generics)
  var decls: seq[CDecl]
  var offset: uint64 = 0
  for field in fields:
    # getter: Type Prefix_get_field(Pointer __asl_ptr);
    decls.add(c_func_decl(field.module_ref.generate_type,
        fmt"{prefix}_get_{field.name.asl}",
        id_params & @[(c_pointer(), "__asl_ptr")]))
    # setter: Pointer Prefix_set_field(Pointer __asl_ptr, Type field);
    decls.add(c_func_decl(c_pointer(),
        fmt"{prefix}_set_{field.name.asl}",
        id_params & @[(c_pointer(), "__asl_ptr"), field.generate_param]))
    offset += field.generate_byte_size

  if prefix == "Array": return decls
  # init: Pointer Prefix_init(args...);
  let init_params = struct.fields.map_it(it.generate_param)
  decls.add(c_func_decl(c_pointer(), fmt"{prefix}_init",
      id_params & init_params))
  return decls

proc generate_struct_defs*(struct: AnalyzedStruct, prefix: string,
    generics: uint64 = 0): seq[CDecl] =
  let fields = struct.fields.sorted(proc(a,
      b: AnalyzedArgumentDefinition): int =
    if a.generate_byte_size > b.generate_byte_size: -1
    elif b.generate_byte_size > a.generate_byte_size: 1
    else: 0
  )

  let id_params = impl_id_params(generics)
  let id_args = impl_id_args(generics)
  var decls: seq[CDecl]
  # byte_size
  decls.add(c_func_def(c_named("U64"), fmt"{prefix}_byte_size",
      id_params & @[(c_named("U64"), "items")],
      @[c_return(c_call("Pointer_byte_size", @[c_ident("items")]))]))
  # read
  decls.add(c_func_def(c_pointer(), fmt"{prefix}_read",
      id_params & @[(c_pointer(), "__asl_ptr"), (c_named("U64"), "offset")],
      @[c_return(c_call("Pointer_read", @[c_ident("__asl_ptr"),
          c_ident("offset")]))]))
  # write
  decls.add(c_func_def(c_pointer(), fmt"{prefix}_write",
      id_params & @[(c_pointer(), "value"), (c_pointer(), "__asl_ptr"),
          (c_named("U64"), "offset")],
      @[c_return(c_call("Pointer_write", @[c_ident("value"),
          c_ident("__asl_ptr"), c_ident("offset")]))]))

  var offset: uint64 = 0
  for field in fields:
    let field_type = field.module_ref.generate_type
    let read_name = fmt"{field_type.emit}_read"
    let write_name = fmt"{field_type.emit}_write"

    # getter
    decls.add(c_func_def(field_type, fmt"{prefix}_get_{field.name.asl}",
        id_params & @[(c_pointer(), "__asl_ptr")],
        @[c_return(c_call(read_name, @[c_ident("__asl_ptr"),
            c_lit($offset)]))]))

    # setter
    decls.add(c_func_def(c_pointer(), fmt"{prefix}_set_{field.name.asl}",
        id_params & @[(c_pointer(), "__asl_ptr"), (field_type, field.name.asl)],
        @[c_return(c_call(write_name, @[c_ident(field.name.asl),
            c_ident("__asl_ptr"), c_lit($offset)]))]))

    offset += field.generate_byte_size

  if prefix == "Array": return decls
  # init function
  let init_params = struct.fields.map_it(it.generate_param)
  var init_body: seq[CStmt]
  init_body.add(c_decl_var(c_pointer(), "__asl_ptr",
      c_call("System_allocate", @[c_lit($offset)])))
  for field in struct.fields:
    init_body.add(c_assign("__asl_ptr",
        c_call(fmt"{prefix}_set_{field.name.asl}",
        id_args & @[c_ident("__asl_ptr"), c_ident(field.name.asl)])))
  init_body.add(c_return(c_ident("__asl_ptr")))
  decls.add(c_func_def(c_pointer(), fmt"{prefix}_init",
      id_params & init_params, init_body))
  return decls

proc generate_branch_decls*(branch: AnalyzedUnionBranch, prefix: string,
    id: uint64, generics: uint64 = 0): seq[CDecl] =
  let sub_prefix = fmt"{prefix}_{branch.name.asl}"
  let fields = branch.fields.sorted(proc(a,
      b: AnalyzedArgumentDefinition): int =
    if a.generate_byte_size > b.generate_byte_size: -1
    elif b.generate_byte_size > a.generate_byte_size: 1
    else: 0
  )

  let id_params = impl_id_params(generics)
  var decls: seq[CDecl]
  var offset: uint64 = 8
  for field in fields:
    decls.add(c_func_decl(field.module_ref.generate_type,
        fmt"{sub_prefix}_get_{field.name.asl}",
        id_params & @[(c_pointer(), "__asl_ptr")]))
    decls.add(c_func_decl(c_pointer(),
        fmt"{sub_prefix}_set_{field.name.asl}",
        id_params & @[(c_pointer(), "__asl_ptr"), field.generate_param]))
    offset += field.generate_byte_size

  if prefix == "Array": return decls
  let init_params = branch.fields.map_it(it.generate_param)
  decls.add(c_func_decl(c_pointer(), fmt"{sub_prefix}_init",
      id_params & init_params))
  return decls

proc generate_branch_defs*(branch: AnalyzedUnionBranch, prefix: string,
    id: uint64, generics: uint64 = 0): seq[CDecl] =
  let sub_prefix = fmt"{prefix}_{branch.name.asl}"
  let fields = branch.fields.sorted(proc(a,
      b: AnalyzedArgumentDefinition): int =
    if a.generate_byte_size > b.generate_byte_size: -1
    elif b.generate_byte_size > a.generate_byte_size: 1
    else: 0
  )

  let id_params = impl_id_params(generics)
  let id_args = impl_id_args(generics)
  var decls: seq[CDecl]
  var offset: uint64 = 8
  for field in fields:
    let field_type = field.module_ref.generate_type
    let read_name = fmt"{field_type.emit}_read"
    let write_name = fmt"{field_type.emit}_write"

    decls.add(c_func_def(field_type,
        fmt"{sub_prefix}_get_{field.name.asl}",
        id_params & @[(c_pointer(), "__asl_ptr")],
        @[c_return(c_call(read_name, @[c_ident("__asl_ptr"),
            c_lit($offset)]))]))

    decls.add(c_func_def(c_pointer(),
        fmt"{sub_prefix}_set_{field.name.asl}",
        id_params & @[(c_pointer(), "__asl_ptr"), (field_type, field.name.asl)],
        @[c_return(c_call(write_name, @[c_ident(field.name.asl),
            c_ident("__asl_ptr"), c_lit($offset)]))]))

    offset += field.generate_byte_size

  if prefix == "Array": return decls
  let init_params = branch.fields.map_it(it.generate_param)
  var init_body: seq[CStmt]
  init_body.add(c_decl_var(c_pointer(), "__asl_ptr",
      c_call("System_allocate", @[c_lit($offset)])))
  init_body.add(c_assign("__asl_ptr",
      c_call(fmt"{prefix}_set_id",
      id_args & @[c_ident("__asl_ptr"), c_lit($id)])))
  for field in branch.fields:
    init_body.add(c_assign("__asl_ptr",
        c_call(fmt"{sub_prefix}_set_{field.name.asl}",
        id_args & @[c_ident("__asl_ptr"), c_ident(field.name.asl)])))
  init_body.add(c_return(c_ident("__asl_ptr")))
  decls.add(c_func_def(c_pointer(), fmt"{sub_prefix}_init",
      id_params & init_params, init_body))
  return decls

proc generate_union_decls*(union: AnalyzedUnion, prefix: string,
    generics: uint64 = 0): seq[CDecl] =
  let id_params = impl_id_params(generics)
  var decls: seq[CDecl]
  # byte_size, read, write declarations
  decls.add(c_func_decl(c_named("U64"), fmt"{prefix}_byte_size",
      id_params & @[(c_named("U64"), "items")]))
  decls.add(c_func_decl(c_pointer(), fmt"{prefix}_read",
      id_params & @[(c_pointer(), "__asl_ptr"), (c_named("U64"), "offset")]))
  decls.add(c_func_decl(c_pointer(), fmt"{prefix}_write",
      id_params & @[(c_pointer(), "value"), (c_pointer(), "__asl_ptr"),
          (c_named("U64"), "offset")]))
  # id getter/setter
  decls.add(c_func_decl(c_named("U64"), fmt"{prefix}_get_id",
      id_params & @[(c_pointer(), "__asl_ptr")]))
  decls.add(c_func_decl(c_pointer(), fmt"{prefix}_set_id",
      id_params & @[(c_pointer(), "__asl_ptr"), (c_named("U64"), "id")]))
  for index, branch in union.branches:
    decls.add(branch.generate_branch_decls(prefix, index.uint64, generics))
  return decls

proc generate_union_defs*(union: AnalyzedUnion, prefix: string,
    generics: uint64 = 0): seq[CDecl] =
  let id_params = impl_id_params(generics)
  var decls: seq[CDecl]
  # byte_size
  decls.add(c_func_def(c_named("U64"), fmt"{prefix}_byte_size",
      id_params & @[(c_named("U64"), "items")],
      @[c_return(c_call("Pointer_byte_size", @[c_ident("items")]))]))
  # read
  decls.add(c_func_def(c_pointer(), fmt"{prefix}_read",
      id_params & @[(c_pointer(), "__asl_ptr"), (c_named("U64"), "offset")],
      @[c_return(c_call("Pointer_read", @[c_ident("__asl_ptr"),
          c_ident("offset")]))]))
  # write
  decls.add(c_func_def(c_pointer(), fmt"{prefix}_write",
      id_params & @[(c_pointer(), "value"), (c_pointer(), "__asl_ptr"),
          (c_named("U64"), "offset")],
      @[c_return(c_call("Pointer_write", @[c_ident("value"),
          c_ident("__asl_ptr"), c_ident("offset")]))]))
  # id getter
  decls.add(c_func_def(c_named("U64"), fmt"{prefix}_get_id",
      id_params & @[(c_pointer(), "__asl_ptr")],
      @[c_return(c_call("U64_read", @[c_ident("__asl_ptr"),
          c_lit("0")]))]))
  # id setter
  decls.add(c_func_def(c_pointer(), fmt"{prefix}_set_id",
      id_params & @[(c_pointer(), "__asl_ptr"), (c_named("U64"), "id")],
      @[c_return(c_call("U64_write", @[c_ident("id"),
          c_ident("__asl_ptr"), c_lit("0")]))]))
  for index, branch in union.branches:
    decls.add(branch.generate_branch_defs(prefix, index.uint64, generics))
  return decls

proc generate_data_typedefs*(data: AnalyzedData, prefix: string): seq[CDecl] =
  case data.kind:
  of ADK_LITERAL: @[data.literal.generate_typedef(prefix)]
  else: @[]

proc generate_data_decls*(data: AnalyzedData, prefix: string,
    generics: uint64 = 0): seq[CDecl] =
  case data.kind:
  of ADK_NONE: @[]
  of ADK_LITERAL: @[]
  of ADK_STRUCT: data.struct.generate_struct_decls(prefix, generics)
  of ADK_UNION: data.union.generate_union_decls(prefix, generics)

proc generate_data_defs*(data: AnalyzedData, prefix: string,
    generics: uint64 = 0): seq[CDecl] =
  case data.kind:
  of ADK_NONE: @[]
  of ADK_LITERAL: @[]
  of ADK_STRUCT: data.struct.generate_struct_defs(prefix, generics)
  of ADK_UNION: data.union.generate_union_defs(prefix, generics)
