import os, results, strformat

import grammar
import parser
import scope

proc write_c_file(code: string, filename: string): Result[void, string] =
  try: write_file(filename, code); ok()
  except OSError: err("An error occurred while trying to create the file")

proc compile(filename: string): Result[void, string] =
  let parse_result = ? rules.parse(filename, "program")
  let code = ? parse_result.program.generate
  code.write_c_file("asl.c")

when is_main_module:
  let maybe_compiled = "example.asl".absolute_path.compile
  if maybe_compiled.is_err:
    echo maybe_compiled.error
    quit(QuitFailure)
