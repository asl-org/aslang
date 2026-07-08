## Package façade — re-exports every component file. Consumers
## (asl.nim, tests) only need `import resolver` to get `resolve*`
## and any of the Resolved* types they care about.

import literals, patterns
import argtypes, funcdefs, data, body, funcs, modules
import imports, files, apps
export literals, patterns
export argtypes, funcdefs, data, body, funcs, modules
export imports, files, apps
