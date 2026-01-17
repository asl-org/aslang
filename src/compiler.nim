import results, strformat, unicode, os, osproc

import analyzer

# Helper to wrap void-returning file operations with error handling
proc safe_void_operation(operation: proc(), filename: string,
    operation_name: string): Result[void, string] =
  try:
    operation()
    ok()
  except OSError as e:
    err(fmt"Failed to {operation_name} file '{filename}': {e.msg}")

proc remove_file_safe(filename: string): Result[void, string] =
  safe_void_operation(proc() = remove_file(filename), filename, "delete")

proc write_file_safe(filename: string, content: string): Result[void, string] =
  safe_void_operation(proc() = write_file(filename, content), filename, "write")

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
  let analyzed_file = ? analyze(typed_file)
  let code = ? analyzed_file.c()

  let output_file = filename.change_file_ext("c")
  ? write_file_safe(output_file, code)
  let exit_code = exec_cmd(fmt"gcc -O3 {output_file} -o {output} -I .")
  if exit_code == 0:
    ? remove_file_safe(output_file)
    ok()
  else:
    err(fmt"Compilation Error exit code {exit_code}")

