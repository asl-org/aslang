## ResolvedGenericArgumentType — a parser Generic reference. Lives in
## the same file as `ResolvedArgumentType` because both variants of the
## outer union must be declared in the same Nim `type` block for the
## case-object machinery to compile.
##
## See ./argtype for the actual declaration and accessors.

import argtype
export argtype
