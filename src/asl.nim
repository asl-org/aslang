import os
import results

import tokenizer
import parser
import codegen


proc write_file(code: string): Result[void, string] =
  try:
    writeFile("asl.c", code)
    ok()
  except OSError:
    err("An error occurred while trying to create the file")

proc compile(filename: string, content: string): Result[void, string] =
  let tokens = ? tokenize(filename, content)
  let statements = ? parse(tokens)
  let code = ? generate(statements)
  ? write_file(code)
  ok()

when isMainModule:
  try:
    let args = commandLineParams()
    let content = readFile(args[0])
    let maybe_compiled = compile(args[0], content)
    if maybe_compiled.is_err: echo maybe_compiled.error
  except IOError as e:
    echo e.msg
