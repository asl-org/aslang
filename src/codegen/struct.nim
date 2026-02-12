import strformat, sequtils, strutils, algorithm

import analyzer
import module_ref
import arg_def

proc h*(struct: AnalyzedStruct, prefix: string): seq[string] =
  # NOTE: sort fields for efficient packing of bytes
  let fields = struct.fields.sorted(proc(a,
      b: AnalyzedArgumentDefinition): int =
    if a.byte_size > b.byte_size: -1
    elif b.byte_size > a.byte_size: 1
    else: 0
  )

  var lines: seq[string]
  # if id is some then it is a union branch so offset for id
  var offset: uint64 = 0
  for field in fields:
    lines.add(fmt"{field.module_ref.c} {prefix}_get_{field.name.asl}(Pointer __asl_ptr);")
    lines.add(fmt"Pointer {prefix}_set_{field.name.asl}(Pointer __asl_ptr, {field.c});")
    offset += field.byte_size

  # NOTE: This is hack to avoid generating an init method since `Array`
  # module has 2 properties but only 1 is accessible.
  if prefix == "Array": return lines
  # NOTE: maintain field order in the init call
  let args_str = struct.fields.map_it(it.c).join(", ")
  lines.add(fmt"Pointer {prefix}_init({args_str});")
  return lines

proc c*(struct: AnalyzedStruct, prefix: string): seq[string] =
  # NOTE: sort fields for efficient packing of bytes
  let fields = struct.fields.sorted(proc(a,
      b: AnalyzedArgumentDefinition): int =
    if a.byte_size > b.byte_size: -1
    elif b.byte_size > a.byte_size: 1
    else: 0
  )

  var lines: seq[string]
  # internal functions for structs
  # byte size
  lines.add(fmt"U64 {prefix}_byte_size(U64 items)")
  lines.add("{")
  lines.add("return Pointer_byte_size(items);")
  lines.add("}")
  # read
  lines.add(fmt"Pointer {prefix}_read(Pointer __asl_ptr, U64 offset)")
  lines.add("{")
  lines.add("return Pointer_read(__asl_ptr, offset);")
  lines.add("}")
  # write
  lines.add(fmt"Pointer {prefix}_write(Pointer value, Pointer __asl_ptr, U64 offset)")
  lines.add("{")
  lines.add("return Pointer_write(value, __asl_ptr, offset);")
  lines.add("}")

  # if id is some then it is a union branch so offset for id
  var offset: uint64 = 0
  for field in fields:
    lines.add(fmt"{field.module_ref.c} {prefix}_get_{field.name.asl}(Pointer __asl_ptr)")
    lines.add("{")
    lines.add(fmt"return {field.module_ref.c}_read(__asl_ptr, {offset});")
    lines.add("}")

    lines.add(fmt"Pointer {prefix}_set_{field.name.asl}(Pointer __asl_ptr, {field.c})")
    lines.add("{")
    lines.add(fmt"return {field.module_ref.c}_write({field.name.asl}, __asl_ptr, {offset});")
    lines.add("}")

    offset += field.byte_size

  if prefix == "Array": return lines
  # NOTE: maintain field order in the init call
  let args_str = struct.fields.map_it(it.c).join(", ")
  lines.add(fmt"Pointer {prefix}_init({args_str})")
  lines.add("{")
  lines.add(fmt"Pointer __asl_ptr = System_allocate({offset});")

  for field in struct.fields:
    lines.add(fmt"__asl_ptr = {prefix}_set_{field.name.asl}(__asl_ptr, {field.name.asl});")

  lines.add("return __asl_ptr;")
  lines.add("}")
  return lines

proc h*(branch: AnalyzedUnionBranch, prefix: string, id: uint64): seq[string] =
  let sub_prefix = fmt"{prefix}_{branch.name.asl}"

  # NOTE: sort fields for efficient packing of bytes
  let fields = branch.fields.sorted(proc(a,
      b: AnalyzedArgumentDefinition): int =
    if a.byte_size > b.byte_size: -1
    elif b.byte_size > a.byte_size: 1
    else: 0
  )

  var lines: seq[string]
  # if id is some then it is a union branch so offset for id
  var offset: uint64 = 8
  for field in fields:
    lines.add(fmt"{field.module_ref.c} {sub_prefix}_get_{field.name.asl}(Pointer __asl_ptr);")
    lines.add(fmt"Pointer {sub_prefix}_set_{field.name.asl}(Pointer __asl_ptr, {field.c});")
    offset += field.byte_size

  # NOTE: This is hack to avoid generating an init method since `Array`
  # module has 2 properties but only 1 is accessible.
  if prefix == "Array": return lines
  # NOTE: maintain field order in the init call
  let args_str = branch.fields.map_it(it.c).join(", ")
  lines.add(fmt"Pointer {sub_prefix}_init({args_str});")
  return lines

proc c*(branch: AnalyzedUnionBranch, prefix: string, id: uint64): seq[string] =
  let sub_prefix = fmt"{prefix}_{branch.name.asl}"

  # NOTE: sort fields for efficient packing of bytes
  let fields = branch.fields.sorted(proc(a,
      b: AnalyzedArgumentDefinition): int =
    if a.byte_size > b.byte_size: -1
    elif b.byte_size > a.byte_size: 1
    else: 0
  )

  var lines: seq[string]
  var offset: uint64 = 8
  for field in fields:
    lines.add(fmt"{field.module_ref.c} {sub_prefix}_get_{field.name.asl}(Pointer __asl_ptr)")
    lines.add("{")
    lines.add(fmt"return {field.module_ref.c}_read(__asl_ptr, {offset});")
    lines.add("}")

    lines.add(fmt"Pointer {sub_prefix}_set_{field.name.asl}(Pointer __asl_ptr, {field.c})")
    lines.add("{")
    lines.add(fmt"return {field.module_ref.c}_write({field.name.asl}, __asl_ptr, {offset});")
    lines.add("}")

    offset += field.byte_size

  if prefix == "Array": return lines
  # NOTE: maintain field order in the init call
  let args_str = branch.fields.map_it(it.c).join(", ")
  lines.add(fmt"Pointer {sub_prefix}_init({args_str})")
  lines.add("{")
  lines.add(fmt"Pointer __asl_ptr = System_allocate({offset});")
  lines.add(fmt"__asl_ptr = {prefix}_set_id(__asl_ptr, {id});")

  for field in branch.fields:
    lines.add(fmt"__asl_ptr = {sub_prefix}_set_{field.name.asl}(__asl_ptr, {field.name.asl});")

  lines.add("return __asl_ptr;")
  lines.add("}")
  return lines

proc h*(union: AnalyzedUnion, prefix: string): seq[string] =
  var lines: seq[string]
  lines.add(fmt"U64 {prefix}_byte_size(U64 items);") # byte size
  lines.add(fmt"Pointer {prefix}_read(Pointer __asl_ptr, U64 offset);") # read
  lines.add(fmt"Pointer {prefix}_write(Pointer value, Pointer __asl_ptr, U64 offset);") # write
  # union branch id getter
  lines.add(fmt"U64 {prefix}_get_id(Pointer __asl_ptr);")
  # union branch id setter
  lines.add(fmt"Pointer {prefix}_set_id(Pointer __asl_ptr, U64 id);")
  for index, branch in union.branches:
    lines.add(branch.h(prefix, index.uint64))
  return lines

proc c*(union: AnalyzedUnion, prefix: string): seq[string] =
  var lines: seq[string]
  # internal functions for structs
  # byte size
  lines.add(fmt"U64 {prefix}_byte_size(U64 items)")
  lines.add("{")
  lines.add("return Pointer_byte_size(items);")
  lines.add("}")
  # read
  lines.add(fmt"Pointer {prefix}_read(Pointer __asl_ptr, U64 offset)")
  lines.add("{")
  lines.add("return Pointer_read(__asl_ptr, offset);")
  lines.add("}")
  # write
  lines.add(fmt"Pointer {prefix}_write(Pointer value, Pointer __asl_ptr, U64 offset)")
  lines.add("{")
  lines.add("return Pointer_write(value, __asl_ptr, offset);")
  lines.add("}")
  # union branch id getter
  lines.add(fmt"U64 {prefix}_get_id(Pointer __asl_ptr)")
  lines.add("{")
  lines.add(fmt"return U64_read(__asl_ptr, 0);")
  lines.add("}")

  # union branch id setter
  lines.add(fmt"Pointer {prefix}_set_id(Pointer __asl_ptr, U64 id)")
  lines.add("{")
  lines.add(fmt"return U64_write(id, __asl_ptr, 0);")
  lines.add("}")
  for index, branch in union.branches:
    lines.add(branch.c(prefix, index.uint64))
  return lines

proc h*(data: AnalyzedData, prefix: string): seq[string] =
  var lines: seq[string]
  case data.kind:
  of ADK_NONE: discard
  of ADK_LITERAL: do_assert false, "[UNREACHABLE] literal codegen is not supported"
  of ADK_STRUCT:
    lines.add(data.struct.h(prefix))
  of ADK_UNION:
    lines.add(data.union.h(prefix))
  return lines

proc c*(data: AnalyzedData, prefix: string): seq[string] =
  var lines: seq[string]
  case data.kind:
  of ADK_NONE: discard
  of ADK_LITERAL: do_assert false, "[UNREACHABLE] literal code gen is not supported"
  of ADK_STRUCT: lines.add(data.struct.c(prefix))
  of ADK_UNION: lines.add(data.union.c(prefix))
  return lines
