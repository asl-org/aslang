# Compute FunctionMetadata for user-defined functions from analyzed bodies.
#
# Walks each statement's expression to determine:
#   - allocates: any REK_INIT or fncall to an allocating function
#   - mutates_args: any fncall to a mutating function
#   - reads_only: negation of allocates/mutates
#   - returns_allocated: last expression is REK_INIT or returns allocated

import ../../metadata
import expression
import fncall
import func_def

proc compute_user_metadata*(steps: seq[AnalyzedStatement]): FunctionMetadata =
  var meta = new_function_metadata()

  for step in steps:
    case step.expression.kind:
    of REK_INIT:
      meta.allocates = true
      meta.reads_only = false
    of REK_FNCALL:
      let called = step.expression.fncall.concrete_def.metadata
      if called.allocates:
        meta.allocates = true
        meta.reads_only = false
      if called.mutates_args:
        meta.mutates_args = true
        meta.reads_only = false
    of REK_MATCH, REK_VARIABLE:
      discard

  # Check if the function returns an allocated value
  if steps.len > 0:
    let last = steps[^1].expression
    case last.kind:
    of REK_INIT:
      meta.returns_allocated = true
    of REK_FNCALL:
      if last.fncall.concrete_def.metadata.returns_allocated:
        meta.returns_allocated = true
    of REK_MATCH, REK_VARIABLE:
      discard

  return meta
