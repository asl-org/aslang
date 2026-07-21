## AnalyzedGenericArgumentType — wraps a resolver ResolvedGeneric with
## a use-site location. Lives in the same file as `AnalyzedArgumentType`
## because both variants of the outer union must be declared in the
## same Nim `type` block for the case-object machinery to compile.
##
## See ./argtype for the actual declaration and accessors.

import ./argtype
export argtype
