## ResolvedFileScope — Identifier (binding name) -> ResolvedType.
##
## Doubles as the defined-type lookup scope for the body walker:
## imports contribute per-binding entries, and the file's local
## defined types are inserted at the analyzer entry point. Pure type
## alias; no procs of its own (`findType` / `findModuleDef` /
## `extractDataDef` / `extractStructFor` / `extractUnionFor` live on
## the analyzer facade because they thread the resolver types too).

import tables

import ./resolver

type ResolvedFileScope* = Table[Identifier, ResolvedType]
