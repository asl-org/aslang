import strformat, strutils, sequtils, tables, results

import ./tokenizer
import ./error

import ./identifiers
import ./argdef

# ============================================================
# VariantDef
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

type VariantDef* = ref object
  name: Identifier
  fields: seq[ArgumentDef]
  fieldIndex: Table[Identifier, int]
  loc: Location

proc newVariantDef*(name: Identifier, fields: seq[ArgumentDef],
    loc: Location): Result[VariantDef, ParserError] =
  let fieldIndex = ? buildNameIndex(fields)
  ok(VariantDef(name: name, fields: fields, fieldIndex: fieldIndex, loc: loc))

proc name*(v: VariantDef): Identifier = v.name
proc fields*(v: VariantDef): seq[ArgumentDef] = v.fields
proc loc*(v: VariantDef): Location = v.loc

proc asl*(varDef: VariantDef): string =
  var content: string
  content.add(asl(varDef.name))
  if varDef.fields.len > 0:
    let inner = varDef.fields.mapIt(asl(it)).join(", ")
    content.add(fmt" {{ {inner} }}")
  content

proc findFieldId*(variant: VariantDef, name: Identifier): Result[int, string] =
  if name notin variant.fieldIndex:
    err(fmt"{name.loc} field `{name.asl}` does not exist in union variant `{variant.name.asl}`")
  else:
    ok(variant.fieldIndex[name])
