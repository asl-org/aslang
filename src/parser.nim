import re, strformat, results, sequtils

from common/location import Location

type
  TerminalKind = enum
    TK_STATIC, TK_DYNAMIC

  Terminal = ref object of RootObj
    case kind: TerminalKind
    of TK_STATIC: value: string
    of TK_DYNAMIC: matcher: proc(x: char): bool

  SymbolKind = enum
    SK_EXACT_ONE, SK_ANY, SK_AT_LEAST_ONE, SK_AT_MOST_ONE

  Symbol = ref object of RootObj
    name: string
    kind: SymbolKind

  Production = ref object of RootObj
    symbols: seq[Symbol]

  RuleKind = enum
    RK_TERMINAL, RK_NON_TERMINAL

  Rule[T] = ref object of RootObj
    name: string
    case kind: RuleKind
    of RK_TERMINAL:
      terminal: Terminal
      terminal_transform: proc(value: string, location: Location): T
    of RK_NON_TERMINAL:
      non_terminal_transform: proc(parts: seq[seq[seq[T]]],
          location: Location): T
      productions: seq[Production]

  Parser[T] = ref object of RootObj
    grammar: seq[Rule[T]]
    content: string
    location: Location

proc look_ahead(parser: Parser, count: int): Result[string, string] =
  let head = parser.location.index
  let tail = parser.location.index + count
  if tail > parser.content.len:
    return err(fmt"Expected {count} more characters but reached end of input at position {parser.location}")
  return ok(parser.content[head..<tail])

proc update_location(parser: Parser, value: string): void =
  for ch in value:
    if ch == '\n':
      parser.location.line += 1
      parser.location.column = 1
    else:
      parser.location.column += 1
    parser.location.index += 1

proc find_rule[T](parser: Parser[T], rule_name: string): Result[Rule[T], string] =
  for rule in parser.grammar:
    if rule.name == rule_name:
      return ok(rule)
  return err(fmt"Failed to find rule: {rule_name}")

proc parse[T](parser: Parser[T], rule_name: string): Result[T, string] =
  let rule = ? parser.find_rule(rule_name)
  let location = parser.location
  case rule.kind:
  of RK_TERMINAL:
    var segment: string

    case rule.terminal.kind:
    of TK_STATIC:
      segment = ? parser.look_ahead(rule.terminal.value.len)
      if segment != rule.terminal.value:
        return err(fmt"{parser.location} Expected '{rule.terminal.value}', got '{segment}'")
    of TK_DYNAMIC:
      segment = ? parser.look_ahead(1)
      if not rule.terminal.matcher(segment[0]):
        return err(fmt"{parser.location} Regex matcher failed for char '{segment}'")

    parser.update_location(segment)
    return ok(rule.terminal_transform(segment, location))
  of RK_NON_TERMINAL:
    var acc = new_seq[seq[seq[T]]](rule.productions.len)
    for index, prod in rule.productions.pairs:
      var failed = false
      var parts: seq[seq[T]]
      for sym in prod.symbols:
        var collected_parts: seq[T]
        var matched = parser.parse(sym.name)

        case sym.kind:
        of SK_AT_MOST_ONE:
          if matched.is_err: continue
          collected_parts.add(matched.get)
        of SK_EXACT_ONE:
          if matched.is_err: failed = true; break
          collected_parts.add(matched.get)
        of SK_AT_LEAST_ONE:
          if matched.is_err: failed = true; break
          while matched.is_ok:
            collected_parts.add(matched.get)
            matched = parser.parse(sym.name)
        of SK_ANY:
          while matched.is_ok:
            collected_parts.add(matched.get)
            matched = parser.parse(sym.name)

        parts.add(collected_parts)

      if not failed:
        acc[index] = parts
        return ok(rule.non_terminal_transform(acc, location))
      else: parser.location = location
    return err(fmt"Failed to match any production of <{rule.name}> at position {location}")

proc parse*[T](rules: seq[Rule[T]], filename, entry: string): Result[T, string] =
  let content = readFile(filename)
  let parser = Parser[T](grammar: rules, content: content, location: Location(
      filename: filename))
  parser.parse(entry)

proc static_terminal_rule*[T](name, value: string, transform: proc(
    value: string, location: Location): T): Rule[T] =
  Rule[T](name: name, kind: RuleKind.RK_TERMINAL, terminal_transform: transform,
      terminal: Terminal(kind: TK_STATIC, value: value))

proc dynamic_terminal_rule*[T](name: string, matcher: proc(x: char): bool,
    transform: proc(value: string, location: Location): T): Rule[T] =
  Rule[T](name: name, kind: RuleKind.RK_TERMINAL, terminal_transform: transform,
      terminal: Terminal(kind: TK_DYNAMIC, matcher: matcher))

proc parse_symbol(symbol: string): Symbol =
  case symbol[^1]:
  of '+': Symbol(kind: SK_AT_LEAST_ONE, name: symbol[0..<(symbol.len - 1)])
  of '?': Symbol(kind: SK_AT_MOST_ONE, name: symbol[0..<(symbol.len - 1)])
  of '*': Symbol(kind: SK_ANY, name: symbol[0..<(symbol.len - 1)])
  else: Symbol(kind: SK_EXACT_ONE, name: symbol)

proc non_terminal_rule*[T](name: string, raw_productions: seq[string],
    transform: proc(parts: seq[seq[seq[T]]], location: Location): T): Rule[T] =
  var productions: seq[Production]
  for p in raw_productions:
    let symbols = p.replace(re"\s+", " ").strip().split(" ").map(parse_symbol)
    productions.add(Production(symbols: symbols))

  Rule[T](name: name, kind: RuleKind.RK_NON_TERMINAL, productions: productions,
      non_terminal_transform: transform)
