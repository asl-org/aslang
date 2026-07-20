## FileScope — the imported-name -> imported Type table populated by
## resolver/imports.nim and threaded through every scope-consuming
## `resolve*` proc downstream. Pure type alias; no procs of its own.

import tables

import ./parser

type FileScope* = Table[Identifier, Type]
