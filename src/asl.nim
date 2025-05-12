import os, results, strformat, parseopt

import parser
import rules
import blocks

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

proc write_file_safe(code: string, filename: string): Result[void, string] =
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

proc compile(filename: string, output_file: string): Result[void, string] =
  let content = ? read_file_safe(filename)
  let grammar = ? asl_grammar()
  let parser = grammar.new_parser(content, new_location(filename))
  let parse_result = ? parser.parse("program")
  let code = ? parse_result.program.collect_defintions()
  # let blocks = ? extract_blocks(parse_result.program)
  # let code = ? blocks.generate()
  code.write_file_safe(output_file)

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
    output_file = "asl.c"
    debug_mode = false

  for kind, key, val in getopt():
    case kind
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

  let maybe_compiled = input_file.absolute_path.compile(output_file)
  if maybe_compiled.is_err:
    echo fmt"Compilation failed: {maybe_compiled.error}"
    quit(QuitFailure)

  echo fmt"Successfully compiled {input_file} to {output_file}"
