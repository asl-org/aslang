import results, strformat, unicode

import tokenizer
import parser

proc write_file_safe(filename: string, content: string): Result[void, string] =
  try:
    write_file(filename, content)
    ok()
  except OSError as e:
    err(fmt"Failed to write output file '{filename}': {e.msg}")

proc read_file_safe(filename: string): Result[string, string] =
  try:
    let content = readFile(filename)
    let invalid_index = validateUtf8(content)
    if invalid_index != -1:
      let invalid_char = content.rune_at(invalid_index)
      return err(fmt"Failed to read UTF8 file due to unexpected character `{invalid_char}` at index {invalid_index}")
    ok(content)
  except OSError as e:
    err(fmt"Failed to read file '{filename}': {e.msg}")

proc compile*(filename: string, output: string): Result[void, string] =
  let content = ? read_file_safe(filename)
  let tokens = ? tokenize(filename, content)
  discard ? parse(filename, tokens)
  ok()
