# Location is re-exported so downstream layers (resolver, analyzer,
# tests) can consume it via a single `import parser` — it's part of
# the parser's public surface (every AST node carries one). The rest
# of the tokenizer (Token, TokenKind, tokenize) stays private to the
# parser layer.
import ./parser/tokenizer/location
export location

# combinators.nim (Spec[T] + oneOf / any / pair / prefixed / ...) is
# imported but NOT re-exported. It's parser-internal scaffolding.
# Downstream layers (resolver, analyzer, cli, asl.nim) consume the
# parser through the AST types + `parse*` entry point below; the
# combinator machinery has no callers outside the parser layer.
# Parser tests that need it import `./parser/combinators` directly.
import ./parser/combinators
import ./parser/identifiers
import ./parser/literals
import ./parser/imports
import ./parser/argtypes
import ./parser/patterns
import ./parser/body
import ./parser/data
import ./parser/funcs
import ./parser/generics
import ./parser/modules
import ./parser/decls
import ./parser/loader
export identifiers, literals, imports,
       argtypes, patterns, body, data, funcs, generics, modules,
       decls, loader
