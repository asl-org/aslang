## Resolved literal types — the discriminator tag a literal-backed
## module (u8, u16, ..., string, pointer) carries through resolution.
##
## `ResolvedLiteralDef` is a plain enum with no participation in the
## resolver's mutually-recursive cycle, so it lives on its own —
## enum + resolveLiteralDef together, cohesive.

type
  ResolvedLiteralDef* = enum
    rltkU8, rltkU16, rltkU32, rltkU64
    rltkI8, rltkI16, rltkI32, rltkI64
    rltkF32, rltkF64, rltkString, rltkPointer
