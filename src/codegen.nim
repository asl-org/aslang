import options, sequtils, strutils, strformat

proc literalByteSizeFunction*(moduleName: string, literalType: string): seq[string] =
  @[
    fmt"size_t {moduleName}_byte_size()",
    "{",
    fmt"return sizeof({literalType});",
    "}",
  ]

proc structFieldOffsetFunction*(moduleName: string, fieldName: string, prevField: Option[string]): seq[string] =
  if prevField.isNone:
    @[
      fmt"size_t {moduleName}_{fieldName}_offset()",
      "{",
      "return 0;",
      "}",
    ]
  else:
    @[
      fmt"size_t {moduleName}_{fieldName}_offset()",
      "{",
      fmt"return {moduleName}_{prevField.get}_offset() + {moduleName}_{prevField.get}_size();",
      "}",
    ]

proc variantFieldOffsetFunction*(moduleName: string, variantName: string, fieldName: string, prevField: Option[string]): seq[string] =
  if prevField.isNone:
    @[
      fmt"size_t {moduleName}_{variantName}_{fieldName}_offset()",
      "{",
      "return 1;", # A variant always contains a field called `id` of 1 byte because there can only be 256 variants at max
      "}",
    ]
  else:
    @[
      fmt"size_t {moduleName}_{variantName}_{fieldName}_offset()",
      "{",
      fmt"return {moduleName}_{variantName}_{prevField.get}_offset() + {moduleName}_{variantName}_{prevField.get}_size();",
      "}",
    ]

proc structFieldSizeFunction*(moduleName: string, fieldName: string, fieldType: string): seq[string] =
  @[
    fmt"size_t {moduleName}_{fieldName}_size()",
    "{",
    fmt"return sizeof({fieldType});",
    "}",
  ]

proc variantFieldSizeFunction*(moduleName: string, variantName: string, fieldName: string, fieldType: string): seq[string] =
  @[
    fmt"size_t {moduleName}_{variantName}_{fieldName}_size()",
    "{",
    fmt"return sizeof({fieldType});",
    "}",
  ]

proc structFieldGetterFunction*(moduleName: string, fieldName: string, fieldType: string): seq[string] =
  @[
    fmt"{fieldType} {moduleName}_get_{fieldName}(pointer __asl_ptr)",
    "{",
    fmt"return *(({fieldType} *)(__asl_ptr + {moduleName}_{fieldName}_offset()));",
    "}",
  ]

proc variantFieldGetterFunction*(moduleName: string, variantName: string, fieldName: string, fieldType: string): seq[string] =
  @[
    fmt"{fieldType} {moduleName}_{variantName}_get_{fieldName}(pointer __asl_ptr)",
    "{",
    fmt"return *(({fieldType} *)(__asl_ptr + {moduleName}_{variantName}_{fieldName}_offset()));",
    "}",
  ]

proc structFieldSetterFunction*(moduleName: string, fieldName: string, fieldType: string): seq[string] =
  @[
    fmt"pointer {moduleName}_set_{fieldName}(pointer __asl_ptr, {fieldType} __asl_value)",
    "{",
    fmt"*(({fieldType} *)(__asl_ptr + {moduleName}_{fieldName}_offset())) = __asl_value;",
    "return __asl_ptr;",
    "}",
  ]

proc variantFieldSetterFunction*(moduleName: string, variantName: string, fieldName: string, fieldType: string): seq[string] =
  @[
    fmt"pointer {moduleName}_{variantName}_set_{fieldName}(pointer __asl_ptr, {fieldType} __asl_value)",
    "{",
    fmt"*(({fieldType} *)(__asl_ptr + {moduleName}_{variantName}_{fieldName}_offset())) = __asl_value;",
    "return __asl_ptr;",
    "}",
  ]

proc structByteSizeFunction*(moduleName: string, lastField: string): seq[string] =
  @[
    fmt"size_t {moduleName}_byte_size()",
    "{",
    fmt"return {moduleName}_{lastField}_offset() + {moduleName}_{lastField}_size();",
    "}",
  ]

proc variantByteSizeFunction*(moduleName: string, variantName: string, lastField: Option[string]): seq[string] =
  if lastField.isSome:
    @[
      fmt"size_t {moduleName}_{variantName}_byte_size()",
      "{",
      fmt"return {moduleName}_{variantName}_{lastField.get}_offset() + {moduleName}_{variantName}_{lastField.get}_size();",
      "}",
    ]
  else:
    @[
      fmt"size_t {moduleName}_{variantName}_byte_size()",
      "{",
      "return 1;", # variant can have zero fields but `id` will always be present
      "}",
    ]

proc structInitFunction*(moduleName: string, fieldTypes: seq[string], fieldNames: seq[string]): seq[string] =
  assert(fieldTypes.len == fieldNames.len, "[BUG] - field type and name must be of same length")
  let argDefs = zip(fieldTypes, fieldNames).mapIt(fmt"{it[0]} {it[1]}").join(", ")
  var code: seq[string]
  code.add(fmt"pointer {moduleName}_init({argDefs})")
  code.add("{")
  code.add(fmt"pointer __asl_ptr = System_allocate({moduleName}_byte_size());")
  for fieldName in fieldNames:
    code.add(fmt"__asl_ptr = {moduleName}_set_{fieldName}(__asl_ptr, {fieldName});")
  code.add(fmt"return __asl_ptr;")
  code.add("}")
  return code

proc variantInitFunction*(moduleName: string, variantName: string, variantId: int, fieldTypes: seq[string], fieldNames: seq[string]): seq[string] =
  assert(fieldTypes.len == fieldNames.len, "[BUG] - field type and name must be of same length")
  let argDefs = zip(fieldTypes, fieldNames).mapIt(fmt"{it[0]} {it[1]}").join(", ")
  var code: seq[string]
  code.add(fmt"pointer {moduleName}_{variantName}_init({argDefs})")
  code.add("{")
  code.add(fmt"pointer __asl_ptr = System_allocate({moduleName}_{variantName}_byte_size());")
  code.add(fmt"__asl_ptr = {moduleName}_set_id(__asl_ptr, {variantId});")
  for fieldName in fieldNames:
    code.add(fmt"__asl_ptr = {moduleName}_{variantName}_set_{fieldName}(__asl_ptr, {fieldName});")
  code.add(fmt"return __asl_ptr;")
  code.add("}")
  return code

proc structFunctions*(moduleName: string, fieldNames: seq[string], fieldTypes: seq[string]): seq[string] =
  assert(fieldNames.len == fieldTypes.len, "[BUG] - struct field names and types must be of equal length")
  assert(fieldNames.len > 0, "[BUG] - struct must have at least 1 field")

  var code: seq[string]
  for id in countup(0, fieldNames.len - 1):
    let fieldName = fieldNames[id]
    let fieldType = fieldTypes[id]
    let prevField = if id == 0: none(string) else: some(fieldNames[id - 1])

    code.add(structFieldOffsetFunction(moduleName, fieldName, prevField))
    code.add(structFieldSizeFunction(moduleName, fieldName, fieldType))
    code.add(structFieldGetterFunction(moduleName, fieldName, fieldType))
    code.add(structFieldSetterFunction(moduleName, fieldName, fieldType))

  code.add(structByteSizeFunction(moduleName, fieldNames[^1]))
  code.add(structInitFunction(moduleName, fieldTypes, fieldNames))
  return code

proc variantFunctions*(moduleName: string, variantName: string, variantId: int, fieldNames: seq[string], fieldTypes: seq[string]): seq[string] =
  assert(fieldNames.len == fieldTypes.len, "[BUG] - variant field names and types must be of equal length")
  var code: seq[string]
  for fieldId in countup(0, fieldNames.len - 1):
    let fieldName = fieldNames[fieldId]
    let fieldType = fieldTypes[fieldId]
    let prevField = if fieldId == 0: none(string) else: some(fieldNames[fieldId - 1])
    code.add(variantFieldOffsetFunction(moduleName, variantName, fieldName, prevField))
    code.add(variantFieldSizeFunction(moduleName, variantName, fieldName, fieldType))
    code.add(variantFieldGetterFunction(moduleName, variantName, fieldName, fieldType))
    code.add(variantFieldSetterFunction(moduleName, variantName, fieldName, fieldType))

  let lastField = if fieldNames.len == 0: none(string) else: some(fieldNames[^1])
  code.add(variantByteSizeFunction(moduleName, variantName, lastField))
  code.add(variantInitFunction(moduleName, variantName, variantId, fieldTypes, fieldNames))
  return code

proc unionIdGetterFunction*(moduleName: string): seq[string] =
  @[
    fmt"uint8_t {moduleName}_get_id(pointer __asl_ptr)",
    "{",
    "return *((uint8_t *)__asl_ptr);",
    "}",
  ]

proc unionIdSetterFunction*(moduleName: string): seq[string] =
  @[
    fmt"pointer {moduleName}_set_id(pointer __asl_ptr, uint8_t __asl_value)",
    "{",
    "*((uint8_t *)__asl_ptr) = __asl_value;",
    "return __asl_ptr;",
    "}",
  ]