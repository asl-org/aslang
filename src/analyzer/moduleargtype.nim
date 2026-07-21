## AnalyzedModuleArgumentType — wraps a resolver ResolvedModuleArgumentType
## with the analyzed impl list, one per position in the source-level
## `Module[Impl, ...]` form. Lives in the same file as
## `AnalyzedArgumentType` because the two are mutually recursive:
## `impls: seq[AnalyzedArgumentType]` refers back to the outer union.
##
## See ./argtype for the actual declaration and accessors.

import ./argtype
export argtype
