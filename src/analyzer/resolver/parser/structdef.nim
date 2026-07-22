import strformat, strutils, sequtils, tables, results

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

proc validateRequiresNameConflict(requires: seq[Identifier]): Result[void, ParserError] =
  var requiresIndex: Table[Identifier, int]
  for index, required in requires:
    if required in requiresIndex:
      let prev = requires[requiresIndex[required]]
      let msg = fmt"duplicate generic encountered, see previous declaration at {prev.loc}"
      return err(newParserError(msg, required.loc))
    requiresIndex[required] = index
  ok()

type StructDef* = ref object
  requires: seq[Identifier]
  fields: seq[ArgumentDef]
  fieldIndex: Table[Identifier, int]
  loc: Location

proc newStructDef*(requires: seq[Identifier], fields: seq[ArgumentDef], loc: Location): Result[StructDef, ParserError] =
  if fields.len == 0:
    err(newParserError("struct must have at least one field", loc))
  else:
    ? validateRequiresNameConflict(requires)
    let fieldIndex = ? buildNameIndex(fields)
    ok(StructDef(requires: requires, fields: fields, fieldIndex: fieldIndex, loc: loc))

proc requires*(s: StructDef): seq[Identifier] = s.requires
proc fields*(s: StructDef): seq[ArgumentDef] = s.fields
proc loc*(s: StructDef): Location = s.loc

proc asl*(s: StructDef, level: int, indentWidth: uint32): seq[string] =
  let indent = " ".repeat(level * indentWidth.int)
  let inner = " ".repeat((level + 1) * indentWidth.int)
  var lines: seq[string]
  if s.requires.len > 0:
    let impls = s.requires.mapIt(it.asl).join(", ")
    lines.add(fmt"{indent}struct({impls}):")
  else:
    lines.add(fmt"{indent}struct:")

  for field in s.fields:
    lines.add(fmt"{inner}{field.asl}")
  lines

proc findFieldId*(struct: StructDef, name: Identifier): Result[int, string] =
  if name notin struct.fieldIndex:
    err(fmt"{name.loc} field `{name.asl}` is not present in the struct")
  else:
    ok(struct.fieldIndex[name])
