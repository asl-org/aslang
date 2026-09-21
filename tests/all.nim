## Test suite entry point. Each test_*.nim file registers its own
## unittest suites at top level — importing them here is enough to
## run them when this file is compiled and executed.

import test_tokenizer
import test_combinators
import test_ast
import test_grammar
import test_loader
import test_resolver
import test_analyzer
import test_cli
import test_lsp
