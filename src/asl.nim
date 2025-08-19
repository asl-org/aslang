import os, parseopt, strformat, results

import tokenizer

const
  Version = "0.1.0"
  Usage = """
A Software Language for Zero Maintenance Systems

Usage:
  asl [options] <input_file>

Options:
  -h, --help           Show this help message
  -v, --version        Show version information
  -o, --output FILE    Specify output file (default: asl.c)
  -d, --debug          Enable debug mode
"""

proc write_file_safe(filename: string, code: string): Result[void, string] =
  try:
    write_file(filename, code)
    ok()
  except OSError as e:
    err(fmt"Failed to write output file '{filename}': {e.msg}")

proc read_file_safe(filename: string): Result[string, string] =
  try:
    ok(readFile(filename))
  except OSError as e:
    err(fmt"Failed to read file '{filename}': {e.msg}")

proc compile(input_file: string, output_file: string,
    output_binary: string): Result[void, string] =
  let content = ? read_file_safe(input_file)
  let lexer = new_lexer(input_file, content)
  let tokens = ? lexer.scan_tokens()
  for token in tokens:
    echo token
  ok()

proc show_help() =
  echo fmt"ASL Compiler v{Version}"
  echo Usage
  quit(QuitSuccess)

proc show_version() =
  echo fmt"ASL Compiler v{Version}"
  quit(QuitSuccess)

when is_main_module:
  var
    input_file = ""
    output_file = "generated.c"
    output_binary = "example"
    debug_mode = false

  for (kind, key, val) in getopt():
    case kind:
    of cmdArgument:
      input_file = key
    of cmdLongOption, cmdShortOption:
      case key
      of "help", "h": show_help()
      of "version", "v": show_version()
      of "output", "o": output_file = val
      of "debug", "d": debug_mode = true
      else:
        echo fmt"Unknown option: {key}"
        show_help()
    of cmdEnd: assert(false)

  if input_file == "":
    echo "Error: No input file specified"
    show_help()

  let maybe_compiled = input_file.absolute_path.compile(output_file, output_binary)
  if maybe_compiled.is_err:
    echo "Compilation failed:"
    echo maybe_compiled.error
    quit(QuitFailure)

  echo fmt"Successfully compiled {input_file} to {output_binary}"
