import os
import results

import common
import tokenizer

proc compile(filename: string, content: string): Result[void, string] =
  var cursor = new_cursor(filename, content)
  let tokens = ? tokenize(cursor)
  for t in tokens: echo t
  ok()

when isMainModule:
  try:
    let args = commandLineParams()
    let content = readFile(args[0])
    let maybe_compiled = compile(args[0], content)
    if maybe_compiled.is_err:
      echo maybe_compiled.error
  except IOError as e:
    echo e.msg
