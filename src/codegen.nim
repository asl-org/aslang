import strformat, strutils, tables

import resolver

proc generate(function: ResolvedFunctionDefinition): seq[string] =
  @[]

proc generate(function: ResolvedStruct): seq[string] =
  @[]

proc generic_id_field(impls: int): (string, int) =
  if impls > 4294967296: ("U64", 8)
  elif impls > 65536: ("U32", 4)
  elif impls > 256: ("U16", 2)
  else: ("U8", 1)

proc generate(prefix: string, generic: ResolvedGeneric, is_value: bool,
    impls: Table[TypedModule, int]): seq[string] =
  var lines: seq[string]
  lines.add(fmt"/* generic {generic.name.asl} */")

  var (id_type, id_offset) = generic_id_field(impls.len)

  # init
  for module, id in impls.pairs:
    # init
    lines.add(@[
      fmt"Pointer {prefix}_{generic.name.asl}_{module.name.asl}_init()",
      "{",
      fmt"Pointer ptr = System_allocate({id_type}_byte_size(1));",
      fmt"ptr = {id_type}_write_Pointer({id}, ptr, 0);",
      "return ptr;",
      "}\n"
    ])

    if is_value:
      let module_name =
        case module.kind:
        of TMK_NATIVE: module.name.asl
        of TMK_USER: "Pointer"

      lines.add(@[
        fmt"Pointer {prefix}_{generic.name.asl}_{module.name.asl}_value_init({module_name} value)",
        "{",
        fmt"Pointer = System.allocate({id_type}_byte_size(1) + {module_name}_byte_size(1));",
        fmt"ptr = {id_type}_write_Pointer({id}, ptr, 0);",
        fmt"ptr = {module_name}_write_Pointer(value, ptr, {id_offset});",
        "return ptr;",
        "}\n"
      ])

      lines.add(@[
        fmt"{module_name} {prefix}_{generic.name.asl}_{module.name.asl}_value_get(Pointer ptr)",
        "{",
        fmt"{module_name} value = {module_name}_read_Pointer(ptr, {id_offset});",
        "return value;",
        "}\n"
      ])

  # get id
  lines.add(@[
      fmt"{id_type} {prefix}_{generic.name.asl}_get_id(Pointer ptr)",
      "{",
      "Pointer ptr = System_allocate({id_type}_byte_size(1));",
      "{id_type} id = {id_type}_read_Pointer(ptr, 0);",
      "return id;",
      "}\n"
    ])

  return lines

proc generate(module: ResolvedModuleDefinition, generic_impls: seq[Table[
    TypedModule, int]]): seq[string] =
  var code: seq[string]
  for index, generic in module.generics.pairs:
    let is_value_generic = module.is_value(generic.generic)
    code.add(generate(module.name.asl, generic, is_value_generic, generic_impls[index]))
  for struct in module.structs:
    code.add(struct.generate())
  for function in module.functions:
    code.add(function.generate())
  return code

proc generate(file: ResolvedFileDefinition, generic_impls: Table[
    TypedUserModule, seq[Table[TypedModule, int]]]): seq[string] =
  var code: seq[string]
  for module in file.modules:
    var generics: seq[Table[TypedModule, int]]
    generics = generic_impls.get_or_default(module.module, generics)
    code.add(module.generate(generics))
  for function in file.functions:
    code.add(function.generate())
  return code

proc generate*(file: ResolvedFile): string =
  file.def.generate(file.generic_impls).join("\n")
