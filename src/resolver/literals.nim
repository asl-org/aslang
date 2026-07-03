## Resolved literal types — the discriminator tag a literal-backed
## module (u8, u16, ..., string, pointer) carries through resolution.
##
## `ResolvedLiteralDef` is a plain enum with no participation in the
## resolver's mutually-recursive cycle, so it lives on its own —
## enum + resolveLiteralDef together, cohesive.

import results, strformat

import parser

type
  ResolvedLiteralDef* = enum
    rltkU8, rltkU16, rltkU32, rltkU64
    rltkI8, rltkI16, rltkI32, rltkI64
    rltkF32, rltkF64, rltkString, rltkPointer

proc resolveLiteralDef*(file: parser.File, literal: LiteralDef): Result[ResolvedLiteralDef, string] =
  case literal.content:
  of "u8": ok(rltkU8)
  of "u16": ok(rltkU16)
  of "u32": ok(rltkU32)
  of "u64": ok(rltkU64)
  of "i8": ok(rltkI8)
  of "i16": ok(rltkI16)
  of "i32": ok(rltkI32)
  of "i64": ok(rltkI64)
  of "f32": ok(rltkF32)
  of "f64": ok(rltkF64)
  of "string": ok(rltkString)
  of "pointer": ok(rltkPointer)
  else: err(fmt"{literal.loc} unsupported literal type encountered `{literal.content}`")
