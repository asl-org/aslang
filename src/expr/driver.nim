import results

import parser
import rules

let filename = "sample.asl"
let maybe_grammar = asl_grammar()
if maybe_grammar.is_err:
  # echo maybe_grammar.error
  discard
else:
  echo $(maybe_grammar.get)
  let content = readFile(filename)
  let parser = maybe_grammar.get.new_parser(content, new_location(filename))
  # TOOD: ensure that parser fails if it could not parse the whole content
  let maybe_parsed = parser.parse("program")
  if maybe_parsed.is_err:
    echo maybe_parsed.error
  else:
    echo maybe_parsed.get.program.only_statements
