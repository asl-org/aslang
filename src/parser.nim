import strformat, results

import parser/grammar
export grammar

type
  Parser[State, Output] = ref object of RootObj
    grammar: Grammar[State, Output]
    content: string
    index: int = 0
    state: State

proc look_ahead(parser: Parser, count: int): Result[string, string] =
  let head = parser.index
  let tail = parser.index + count
  if tail > parser.content.len:
    return err(fmt"Expected {count} more characters but reached end of input at position {parser.index}")
  return ok(parser.content[head..<tail])

proc parse_static_rule[State, Output](parser: Parser[State, Output], rule: Rule[
    State, Output]): Result[Output, string] =
  let start = parser.index
  var segment = ? parser.look_ahead(rule.value.len)
  if segment != rule.value:
    let value_str = rule.value
    return err(fmt"{start} Expected '{value_str}', got '{segment}'")

  parser.index += segment.len
  let (new_state, output) = rule.reduce_static(parser.state, segment)
  parser.state = new_state
  return ok(output)

proc parse_matcher_rule[State, Output](parser: Parser[State, Output],
    rule: Rule[State, Output]): Result[Output, string] =
  let start = parser.index
  var segment = ? parser.look_ahead(1)
  if not rule.matcher()(segment[0]):
    return err(fmt"{start} Regex matcher failed for char '{segment}'")

  parser.index += segment.len
  let (new_state, output) = rule.reduce_match(parser.state, segment)
  parser.state = new_state
  return ok(output)

# forward declaration for cyclic dependency of parse_production & parse
proc parse[State, Output](parser: Parser[State, Output], rule_name: string,
    depth: int = 0): Result[Output, string]

proc parse_production[State, Output](parser: Parser[State, Output],
    prod: Production, depth: int): Result[seq[seq[Output]], string] =
  var failed_symbol_index = -1
  var parts: seq[seq[Output]]
  for index, sym in prod.symbols:
    var collected_parts: seq[Output]
    var matched = parser.parse(sym.name, depth + 1)

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
    return err(fmt"Failed to match symbol {symbol}")

  ok(parts)

proc parse[State, Output](parser: Parser[State, Output], rule_name: string,
    depth: int): Result[Output, string] =
  let rule = ? parser.grammar.find_rule(rule_name)
  let start = parser.index

  # TODO: May need in future to control memory usage of parser
  # echo rule.name, " ", rule.kind, " ", depth, " ", parser.index
  # if depth > 10: return err(fmt"stack overflow")

  case rule.kind:
  of RK_STATIC: return parser.parse_static_rule(rule)
  of RK_MATCHER: return parser.parse_matcher_rule(rule)
  of RK_RECURSIVE:
    let productions = rule.productions
    var acc = new_seq[seq[seq[Output]]](productions.len)
    for index, prod in productions:
      let maybe_parsed = parser.parse_production(prod, depth)
      if maybe_parsed.is_ok:
        acc[index] = maybe_parsed.get
        let (new_state, output) = rule.reduce_recursive(parser.state, acc)
        parser.state = new_state
        return ok(output)
      else:
        # echo rule.name, " ", start, " ", parser.state
        parser.index = start

  err(fmt"Failed to match any production of <{rule.name}> at position {start}")

proc parse*[State, Output](parser: Parser[State, Output],
    rule_name: string): Result[Output, string] =
  parser.parse(rule_name, 0)

proc new_parser*[State, Output](grammar: Grammar[State, Output],
    content: string, state: State): Parser[State, Output] =
  let content_with_eof = content & '\0'
  Parser[State, Output](grammar: grammar, content: content_with_eof, state: state)
