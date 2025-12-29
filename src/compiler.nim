import results, strformat, unicode, os, osproc

import resolver

proc remove_file_safe(filename: string): Result[void, string] =
  try:
    remove_file(filename)
    ok()
  except OSError as e:
    err(fmt"Failed to delete output file '{filename}': {e.msg}")

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
  let file = ? parse(filename, tokens)
  let typed_file = ? assign_type(file)
  let resolved_file = ? resolve(typed_file)
  let code = ? resolved_file.c()

  let output_file = filename.change_file_ext("c")
  ? write_file_safe(output_file, code)
  let exit_code = exec_cmd(fmt"gcc -O3 {output_file} -o {output} -I .")
  if exit_code == 0:
    ? remove_file_safe(output_file)
    ok()
  else:
    err(fmt"Compilation Error exit code {exit_code}")

