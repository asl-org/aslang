## FunctionScope — the set of variable names in scope at a body-level
## site. Threaded through every statement/expression resolver so name
## lookups can distinguish a bound local from an unresolved reference.
## Pure type alias; no procs of its own.

import sets

import ./parser

type FunctionScope* = HashSet[Identifier]
