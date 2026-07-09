## Package façade. Consumers say `import resolver` to get every
## resolved-side type PLUS the parser layer that resolver builds on
## (types, constructors, accessors, and the `parse*` entry point).
##
## Parser combinators (Spec[T] machinery, oneOf / pair / prefixed /
## etc.) stay private to the parser layer — analyzer, cli, and asl.nim
## never touch them, and re-exporting them here would leak internal
## parser scaffolding through the resolver's API. Callers that need
## the combinator layer directly (parser tests) import
## `resolver/parser/combinators` explicitly.

import ./resolver/parser
export parser

import ./resolver/literals
import ./resolver/patterns
import ./resolver/argtypes
import ./resolver/funcdefs
import ./resolver/data
import ./resolver/body
import ./resolver/funcs
import ./resolver/modules
import ./resolver/imports
import ./resolver/files
import ./resolver/apps
export literals, patterns
export argtypes, funcdefs, data, body, funcs, modules
export imports, files, apps
