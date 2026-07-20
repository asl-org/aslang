## ResolvedModuleArgumentType — a parser Module reference with its
## impl-list (empty for bare initializers, non-empty for
## `Module[Impl, ...]` forms). Lives in the same file as
## `ResolvedArgumentType` because the two are mutually recursive:
## `impls: seq[ResolvedArgumentType]` refers back to the outer union.
##
## See ./argtype for the actual declaration and accessors.

import ./argtype
export argtype
