import strformat, results

import ./tokenizer

import ./identifiers
import ./literals
import ./structdef
import ./uniondef

# ============================================================
# DataDef
# ============================================================

type
  DataDefKind* = enum
    ddkLiteral, ddkStruct, ddkUnion
  DataDef* = ref object
    case kind: DataDefKind
    of ddkLiteral: literal: LiteralDef
    of ddkStruct: struct: StructDef
    of ddkUnion: union: UnionDef

proc newDataDef*(l: LiteralDef): DataDef =
  DataDef(kind: ddkLiteral, literal: l)

proc newDataDef*(s: StructDef): DataDef =
  DataDef(kind: ddkStruct, struct: s)

proc newDataDef*(u: UnionDef): DataDef =
  DataDef(kind: ddkUnion, union: u)

proc kind*(db: DataDef): DataDefKind = db.kind
proc literal*(db: DataDef): LiteralDef =
  assert(db.kind == ddkLiteral, fmt"DataDef.literal accessed but kind is {db.kind}")
  db.literal
proc struct*(db: DataDef): StructDef =
  assert(db.kind == ddkStruct, fmt"DataDef.struct accessed but kind is {db.kind}")
  db.struct
proc union*(db: DataDef): UnionDef =
  assert(db.kind == ddkUnion, fmt"DataDef.union accessed but kind is {db.kind}")
  db.union

proc loc*(db: DataDef): Location =
  case db.kind:
  of ddkLiteral: db.literal.loc
  of ddkStruct: db.struct.loc
  of ddkUnion: db.union.loc

proc asl*(db: DataDef, level: int, indentWidth: uint32): seq[string] =
  case db.kind:
  of ddkLiteral: db.literal.asl(level, indentWidth)
  of ddkStruct: db.struct.asl(level, indentWidth)
  of ddkUnion: db.union.asl(level, indentWidth)

proc struct*(db: DataDef, module: Identifier): Result[StructDef, string] =
  case db.kind:
  of ddkLiteral: err(fmt"{db.loc} module `{module.asl}` is a literal")
  of ddkUnion: err(fmt"{db.loc} module `{module.asl}` is a union")
  of ddkStruct: ok(db.struct)

proc union*(db: DataDef, module: Identifier): Result[UnionDef, string] =
  case db.kind:
  of ddkLiteral: err(fmt"{db.loc} module `{module.asl}` is a literal")
  of ddkStruct: err(fmt"{db.loc} module `{module.asl}` is a struct")
  of ddkUnion: ok(db.union)
