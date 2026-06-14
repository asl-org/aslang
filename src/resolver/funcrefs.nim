## FunctionScope alias used by the body walker. The funcref validation
## that used to live here (resolveFunctionRef + the three TypeRef
## helpers) is inlined into resolveFunctionCall now that FunctionCall
## carries just an Identifier root (no impls).

import sets

import parser

# FunctionScope alias — names of variables currently in scope inside
# a function body. body.nim and decls.nim each import this.
type FunctionScope* = HashSet[Identifier]
