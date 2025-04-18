import os, results

import common
import grammar
import parser
import transformer

proc compile(filename: string): Result[void, string] =
  let parse_result = ? rules.parse(filename, "program")
  let statements = parse_result.program.statements
  echo $(statements[0])
  ok()

when is_main_module:
  let maybe_compiled = "example.asl".absolute_path.compile
  if maybe_compiled.is_err:
    echo maybe_compiled.error
    quit(QuitFailure)
