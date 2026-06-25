# Two import statements pointing at the same source file with
# different visible names. Current language policy allows this —
# the parser's BFS deduplicates parsing via a HashSet on absolute
# paths, but both Import AST nodes are preserved and each gets
# its own ResolvedImport.targetFileId in the resolver.
import { Solver as First } from "./problem001.asl"
import { Solver as Second } from "./problem001.asl"

module Caller:
  func start(): u8
    u8 0
