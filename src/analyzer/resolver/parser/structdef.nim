import strformat, strutils, tables, results

import ./tokenizer
import ./error

import ./identifiers
import ./argdef

# ============================================================
# StructDef
# ============================================================

proc buildNameIndex(fields: seq[ArgumentDef]): Result[Table[Identifier, int], ParserError] =
  var fieldIndex: Table[Identifier, int]
  for index, field in fields:
    if field.name in fieldIndex:
      let prev = fields[fieldIndex[field.name]]
      let msg = fmt"duplicate field encountered, see previous declaration at {prev.loc}"
      return err(newParserError(msg, field.loc))
    fieldIndex[field.name] = index
  ok(fieldIndex)

type StructDef* = ref object
  fields: seq[ArgumentDef]
  fieldIndex: Table[Identifier, int]
  loc: Location

proc fields*(s: StructDef): seq[ArgumentDef] = s.fields
proc loc*(s: StructDef): Location = s.loc

proc newStructDef*(fields: seq[ArgumentDef], loc: Location): Result[StructDef, ParserError] =
  if fields.len == 0:
    err(newParserError("struct must have at least one field", loc))
  else:
    let fieldIndex = ? buildNameIndex(fields)
    ok(StructDef(fields: fields, fieldIndex: fieldIndex, loc: loc))

proc asl*(s: StructDef, level: int, indentWidth: uint32): seq[string] =
  let indent = " ".repeat(level * indentWidth.int)
  let inner = " ".repeat((level + 1) * indentWidth.int)
  var lines: seq[string]
  lines.add(fmt"{indent}struct:")
  for field in s.fields:
    lines.add(fmt"{inner}{asl(field)}")
  lines

proc findFieldId*(struct: StructDef, name: Identifier): Result[int, string] =
  if name notin struct.fieldIndex:
    err(fmt"{name.loc} field `{name.asl}` is not present in the struct")
  else:
    ok(struct.fieldIndex[name])
