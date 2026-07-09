## Package façade. Consumers say `import analyzer` to get the full
## compiler stack: analyzer types and `analyze*`, plus the resolver
## layer that analyzer builds on (which itself re-exports the parser
## AST + `parse*` entry point + Location).
##
## Under the nesting convention, `src/asl.nim` only needs `import
## cli, analyzer` to reach every construct in the compiler.

import ./resolver
export resolver

import ./analyzer/imports
import ./analyzer/argtypes
import ./analyzer/funcrefs
import ./analyzer/patterns
import ./analyzer/body
import ./analyzer/funcs
import ./analyzer/appdefs
export imports, argtypes, funcrefs, patterns, body, funcs, appdefs
