import strformat, strutils, tables, results

import ./tokenizer
import ./error

import ./identifiers
import ./variantdef

# ============================================================
# UnionDef
# ============================================================

proc buildNameIndex(variants: seq[VariantDef]): Result[Table[Identifier, int], ParserError] =
  var variantIndex: Table[Identifier, int]
  for index, variant in variants:
    if variant.name in variantIndex:
      let prev = variants[variantIndex[variant.name]]
      let msg = fmt"duplicate variant encountered, see previous declaration at {prev.loc}"
      return err(newParserError(msg, variant.loc))
    variantIndex[variant.name] = index
  ok(variantIndex)

type UnionDef* = ref object
  variants: seq[VariantDef]
  variantIndex: Table[Identifier, int]
  loc: Location

proc newUnionDef*(variants: seq[VariantDef], loc: Location): Result[UnionDef, ParserError] =
  let variantIndex = ? buildNameIndex(variants)
  ok(UnionDef(variants: variants, variantIndex: variantIndex, loc: loc))

proc variants*(u: UnionDef): seq[VariantDef] = u.variants
proc loc*(u: UnionDef): Location = u.loc

proc asl*(u: UnionDef, level: int, indentWidth: uint32): seq[string] =
  let indent = " ".repeat(level * indentWidth.int)
  let inner = " ".repeat((level + 1) * indentWidth.int)
  var lines: seq[string]
  lines.add(fmt"{indent}union:")
  for variant in u.variants:
    lines.add(fmt"{inner}{asl(variant)}")
  lines

proc findVariantId(union: UnionDef, variant: Identifier): Result[int, string] =
  if variant notin union.variantIndex:
    err(fmt"{variant.loc} variant `{variant.asl}` does not exist in union")
  else:
    ok(union.variantIndex[variant])

proc findVariant*(union: UnionDef, variant: Identifier): Result[VariantDef, string] =
  let variantId = ? union.findVariantId(variant)
  ok(union.variants[variantId])
