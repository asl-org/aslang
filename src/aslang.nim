import results, parseopt, os
from compiler import compile

const Usage = """
A Software Language for Zero Maintenance Systems

Usage:
  aslang [options] <input_file>

Options:
  -h, --help           Show this help message
  -o, --output FILE    Specify output binary name

Examples:
  ./aslang example.asl # generates a binary named `example`
  ./aslang example.asl -o=program # generates a binary named `program`
"""

when isMainModule:
  var filename = ""
  var output = ""
  for (kind, key, val) in getopt():
    case kind:
    of cmdArgument:
      filename = key.absolutePath
    of cmdLongOption, cmdShortOption:
      case key:
      of "o", "output":
        output = val
      of "h", "help":
        echo Usage
        quit(QuitSuccess)
      else:
        echo Usage
        quit(QuitFailure)
    of cmdEnd:
      assert(false)

  if filename.len == 0:
    echo Usage
    quit(QuitFailure)


  if output.len == 0:
    (_, output, _) = split_file(filename)

  let maybe_compiled = filename.compile(output)
  if maybe_compiled.is_ok:
    quit(QuitSuccess)
  else:
    echo maybe_compiled.error
    quit(QuitFailure)
