import results

import tokenizer
import parser
import blocks

type File = blocks.File

proc resolve(file: File): Result[void, string] =
  let main_function = ? file.find_main_function()
  ok()

proc compile(): Result[void, string] =
  let filename = "poc/sample.asl"
  let content = read_file(filename)
  let tokens = ? tokenize(filename, content)
  let lines = ? parse(tokens)
  let file = ? blockify(filename, lines)
  ? resolve(file)
  ok()

when is_main_module:
  let maybe_compiled = compile()
  if maybe_compiled.is_err:
    echo maybe_compiled.error
