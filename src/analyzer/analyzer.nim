## Package façade — re-exports every component file. Consumers
## (src/asl.nim, tests) only need `import analyzer` to get `analyze*`
## and any of the Analyzed* types they care about.

import literals, imports, argtypes, funcdefs, data, modules, funcrefs, patterns, body, funcs, decls
export literals, imports, argtypes, funcdefs, data, modules, funcrefs, patterns, body, funcs, decls
