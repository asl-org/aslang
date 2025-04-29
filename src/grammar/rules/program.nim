import sequtils

import "../parser"
import "../transformer"

import "../location"
import "../common/line"
import "../common/program"

proc program_transform(parts: seq[seq[seq[ParseResult]]],
    location: Location): ParseResult =
  let lines = parts[0][0].map(proc(p: ParseResult): Line = p.line)
  new_program(lines, location).new_program_parse_result()

let program_rules* = @[
  # program ::= statement+
  non_terminal_rule("program", @["line+"], program_transform),
]
