import os, results

import common
import grammar
import parser
import transformer

proc write_c_file(code: string, filename: string): Result[void, string] =
  try: write_file(filename, code); ok()
  except OSError: err("An error occurred while trying to create the file")

proc generate(program: Program): Result[string, string] =
  let statements = program.statements
  echo $(statements[0])
  ok("")

proc compile(filename: string): Result[void, string] =
  let parse_result = ? rules.parse(filename, "program")
  let code = ? parse_result.program.generate
  code.write_c_file("asl.c")

when is_main_module:
  let maybe_compiled = "example.asl".absolute_path.compile
  if maybe_compiled.is_err:
    echo maybe_compiled.error
    quit(QuitFailure)
