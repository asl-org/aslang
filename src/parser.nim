import strformat, results, strutils

import parser/grammar
export grammar

type ParseError* = ref object of RootObj
  stack: seq[(Location, string)]

proc push(parse_error: ParseError, location: Location,
    message: string): ParseError =
  parse_error.stack.add((location, message))
  parse_error

proc new_parse_error(): ParseError = ParseError()

proc new_parse_error(location: Location, message: string): ParseError =
  new_parse_error().push(location, message)

proc location(parse_error: ParseError): Location =
  if parse_error.stack.len == 0: Location()
  else: parse_error.stack[0][0]

proc `$`*(parse_error: ParseError): string =
  var content: seq[string]
  for (location, message) in parse_error.stack:
    content.add(fmt"{location} {message}")
  return content.join("\n")

type
  Parser[Output] = ref object of RootObj
    grammar: Grammar[Output]
    content: string
    location: Location

proc look_ahead(parser: Parser, count: int): Result[string, ParseError] =
  let head = parser.location.index
  let tail = head + count
  if tail > parser.content.len:
    return err(new_parse_error(parser.location,
        fmt"Expected {count} more characters but reached end of input"))
  return ok(parser.content[head..<tail])

proc update_location(content: string, location: Location): Location =
  var updated = location
  for ch in content:
    if ch == '\n':
      updated.line += 1
      updated.col = 1
    else: updated.col += 1
    updated.index += 1
  return updated

proc parse_static_rule[Output](parser: Parser[Output], rule: Rule[
    Output]): Result[Output, ParseError] =
  var segment = ? parser.look_ahead(rule.value.len)
  if segment != rule.value:
    let value_str = rule.value
    return err(new_parse_error(parser.location,
        fmt"Expected '{value_str}', got '{segment}'"))

  parser.location = update_location(segment, parser.location)
  let output = rule.reduce_static(parser.location, segment)
  return ok(output)

proc parse_matcher_rule[Output](parser: Parser[Output],
    rule: Rule[Output]): Result[Output, ParseError] =
  var segment = ? parser.look_ahead(1)
  if not rule.matcher()(segment[0]):
    let rule_name = rule.name
    return err(new_parse_error(parser.location,
        fmt"{rule_name} Regex matcher failed for char '{segment}'"))

  parser.location = update_location(segment, parser.location)
  let output = rule.reduce_match(parser.location, segment)
  return ok(output)

# forward declaration for cyclic dependency of parse_production & parse
proc parse[Output](parser: Parser[Output], rule_name: string,
    depth: int = 0): Result[Output, ParseError]

proc parse_production[Output](parser: Parser[Output],
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
    return err(matched.error.push(parser.location,
        fmt"Failed to match symbol {symbol}"))

  ok(parts)

proc parse[Output](parser: Parser[Output], rule_name: string,
    depth: int): Result[Output, ParseError] =
  let maybe_rule = parser.grammar.find_rule(rule_name)
  if maybe_rule.is_err:
    return err(new_parse_error(parser.location, maybe_rule.error))

  let rule = maybe_rule.get
  var initial_location = parser.location

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
        let output = rule.reduce_recursive(initial_location, acc)
        return ok(output)
      else:
        if prod_err.location < maybe_parsed.error.location:
          prod_err = maybe_parsed.error
        parser.location = initial_location
    err(prod_err.push(initial_location, fmt"Failed to match rule {rule_name}"))

proc parse*[Output](parser: Parser[Output],
    rule_name: string): Result[Output, ParseError] =
  parser.parse(rule_name, 0)

proc new_parser*[Output](grammar: Grammar[Output],
    filename: string, content: string): Parser[Output] =
  let content_with_eof = content & '\0'
  Parser[Output](grammar: grammar, content: content_with_eof,
      location: new_location(filename))
