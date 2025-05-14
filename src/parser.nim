import strformat, results, strutils

import parser/grammar
export grammar

type ParseError* = ref object of RootObj
  stack: seq[(int, string)]

proc push(parse_error: ParseError, index: int, message: string): ParseError =
  parse_error.stack.add((index, message))
  parse_error

proc new_parse_error(): ParseError = ParseError()

proc new_parse_error(index: int, message: string): ParseError =
  new_parse_error().push(index, message)

proc index(parse_error: ParseError): int =
  if parse_error.stack.len > 0:
    parse_error.stack[0][0]
  else:
    return 0

proc `$`*(parse_error: ParseError): string =
  var content: seq[string]
  for (index, message) in parse_error.stack:
    content.add(fmt"{message} at index {index}")
  return content.join("\n")

type
  Parser[State, Output] = ref object of RootObj
    grammar: Grammar[State, Output]
    content: string
    index: int = 0
    state: State

proc look_ahead(parser: Parser, count: int): Result[string, ParseError] =
  let head = parser.index
  let tail = parser.index + count
  if tail > parser.content.len:
    return err(new_parse_error(head, fmt"Expected {count} more characters but reached end of input at position {parser.index}"))
  return ok(parser.content[head..<tail])

proc parse_static_rule[State, Output](parser: Parser[State, Output], rule: Rule[
    State, Output]): Result[Output, ParseError] =
  let start = parser.index
  var segment = ? parser.look_ahead(rule.value.len)
  if segment != rule.value:
    let value_str = rule.value
    return err(new_parse_error(start, fmt"Expected '{value_str}', got '{segment}' at index: {start}"))

  parser.index += segment.len
  let (new_state, output) = rule.reduce_static(parser.state, segment)
  parser.state = new_state
  return ok(output)

proc parse_matcher_rule[State, Output](parser: Parser[State, Output],
    rule: Rule[State, Output]): Result[Output, ParseError] =
  let start = parser.index
  var segment = ? parser.look_ahead(1)
  if not rule.matcher()(segment[0]):
    let rule_name = rule.name
    return err(new_parse_error(start, fmt"{rule_name} Regex matcher failed for char '{segment}' at index: {start}"))

  parser.index += segment.len
  let (new_state, output) = rule.reduce_match(parser.state, segment)
  parser.state = new_state
  return ok(output)

# forward declaration for cyclic dependency of parse_production & parse
proc parse[State, Output](parser: Parser[State, Output], rule_name: string,
    depth: int = 0): Result[Output, ParseError]

proc parse_production[State, Output](parser: Parser[State, Output],
    prod: Production, depth: int): Result[seq[seq[Output]], ParseError] =
  var failed_symbol_index = -1
  var parts: seq[seq[Output]]
  var matched: Result[Output, ParseError]
  for index, sym in prod.symbols:
    var collected_parts: seq[Output]
    matched = parser.parse(sym.name, depth + 1)

    case sym.kind:
    of SK_AT_MOST_ONE:
      if matched.is_err: continue
      collected_parts.add(matched.get)
    of SK_EXACT_ONE:
      if matched.is_err: failed_symbol_index = index; break
      collected_parts.add(matched.get)
    of SK_AT_LEAST_ONE:
      if matched.is_err: failed_symbol_index = index; break
      while matched.is_ok:
        collected_parts.add(matched.get)
        matched = parser.parse(sym.name, depth + 1)
    of SK_ANY:
      while matched.is_ok:
        collected_parts.add(matched.get)
        matched = parser.parse(sym.name, depth + 1)

    parts.add(collected_parts)

  if failed_symbol_index != -1:
    let symbol = $(prod.symbols[failed_symbol_index])
    return err(matched.error.push(parser.index,
        fmt"Failed to match symbol {symbol}"))

  ok(parts)

proc parse[State, Output](parser: Parser[State, Output], rule_name: string,
    depth: int): Result[Output, ParseError] =
  let maybe_rule = parser.grammar.find_rule(rule_name)
  if maybe_rule.is_err:
    return err(new_parse_error(parser.index, maybe_rule.error))

  let rule = maybe_rule.get
  let start = parser.index

  # TODO: May need in future to control memory usage of parser
  # echo rule.name, " ", rule.kind, " ", depth, " ", parser.index
  # if depth > 10: return err(fmt"stack overflow")

  case rule.kind:
  of RK_STATIC: return parser.parse_static_rule(rule)
  of RK_MATCHER: return parser.parse_matcher_rule(rule)
  of RK_RECURSIVE:
    let productions = rule.productions
    var prod_err = new_parse_error()
    var acc = new_seq[seq[seq[Output]]](productions.len)
    for index, prod in productions:
      let maybe_parsed = parser.parse_production(prod, depth)
      if maybe_parsed.is_ok:
        acc[index] = maybe_parsed.get
        let (new_state, output) = rule.reduce_recursive(parser.state, acc)
        parser.state = new_state
        return ok(output)
      else:
        if prod_err.index < maybe_parsed.error.index:
          prod_err = maybe_parsed.error
        # echo rule.name, " ", start, " ", parser.state
        parser.index = start
    # echo rule.name, " ", rule.kind, " ", depth, " ", parser.index
    err(prod_err.push(start, fmt"Failed to match rule {rule_name} at index: {start}"))

proc parse*[State, Output](parser: Parser[State, Output],
    rule_name: string): Result[Output, ParseError] =
  parser.parse(rule_name, 0)

proc new_parser*[State, Output](grammar: Grammar[State, Output],
    content: string, state: State): Parser[State, Output] =
  let content_with_eof = content & '\0'
  Parser[State, Output](grammar: grammar, content: content_with_eof, state: state)
