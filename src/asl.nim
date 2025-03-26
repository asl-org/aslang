import os
import results

import tokenizer
import parser

proc compile(filename: string, content: string): Result[void, string] =
  let tokens = ? tokenize(filename, content)
  # for t in tokens: echo($(t))
  let statements = ? parse(tokens)
  for s in statements: echo s
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
