import re, results, strformat, strutils, options

type
  Location = object
    filename: string
    line*: int = 1
    column*: int = 1
    index*: int = 0

  StructKind* = enum
    SK_RAW, SK_NON_TERMINAL

  Struct* = ref object of RootObj
    location*: Location
    case kind*: StructKind
    of SK_RAW: value*: string
    else: discard

  RegexKind = enum
    RK_EXACT_ONE, RK_ANY, RK_AT_LEAST_ONE, RK_AT_MOST_ONE

  TerminalKind = enum
    TK_STATIC, TK_DYNAMIC

  Terminal = ref object of RootObj
    case kind: TerminalKind
    of TK_STATIC: value: string
    of TK_DYNAMIC: matcher: proc(x: char): bool

  Symbol = ref object of RootObj
    name: string
    kind: RegexKind

  Production = ref object of RootObj
    symbols: seq[Symbol]

  RuleKind = enum
    RK_TERMINAL, RK_NON_TERMINAL

  Rule = ref object of RootObj
    name: string
    case kind: RuleKind
    of RK_TERMINAL:
      terminal: Terminal
    of RK_NON_TERMINAL:
      transform: proc(parts: seq[seq[Struct]]): Struct
      productions: seq[Production]

  Grammar = ref object of RootObj
    rules: seq[Rule]

  Parser = ref object of RootObj
    grammar: Grammar
    content: string
    location: Location

proc `$`(location: Location): string =
  fmt"{location.filename}({location.line}, {location.column})"

proc raw_transform(parts: seq[seq[Struct]]): Struct =
  var value: string
  var location: Option[Location]
  for group in parts:
    var collected: string
    for chunk in group:
      case chunk.kind:
      of StructKind.SK_RAW:
        if location.is_none: location = some(chunk.location)
        collected.add(chunk.value)
      else: discard
    value.add(collected)
  Struct(kind: StructKind.SK_RAW, location: location.get, value: value)

proc find_rule(parser: Parser, rule: string): Result[Rule, string] =
  for r in parser.grammar.rules:
    if r.name == rule:
      return ok(r)
  return err(fmt"Failed to find rule: {rule}")

proc look_ahead(parser: Parser, count: int): Result[string, string] =
  let head = parser.location.index
  let tail = parser.location.index + count
  if tail > parser.content.len:
    return err(fmt"Expected {count} more characters but reached end of input at position {parser.location}")
  return ok(parser.content[head..<tail])

proc terminal_result(parser: Parser, value: string): Struct =
  let location = parser.location
  for ch in value:
    if ch == '\n':
      parser.location.line += 1
      parser.location.column = 1
    else:
      parser.location.column += 1
    parser.location.index += 1

  Struct(kind: SK_RAW, location: location, value: value)

proc parse_static_terminal(parser: Parser, value: string): Result[Struct, string] =
  let segment = ? parser.look_ahead(value.len)
  if segment == value: return ok(parser.terminal_result(segment))
  err(fmt"{parser.location} Expected '{value}', got '{segment}'")

proc parse_dynamic_terminal(parser: Parser, matcher: proc(
    x: char): bool): Result[Struct, string] =
  let segment = ? parser.look_ahead(1)
  if matcher(segment[0]): return ok(parser.terminal_result(segment))
  err(fmt"{parser.location} Dynamic matcher failed for char '{segment}'")

proc parse_terminal(parser: Parser, terminal: Terminal): Result[Struct, string] =
  case terminal.kind:
  of TK_STATIC:
    parser.parse_static_terminal(terminal.value)
  of TK_DYNAMIC:
    parser.parse_dynamic_terminal(terminal.matcher)

proc parse(parser: Parser, rule_name: string): Result[Struct, string] =
  let rule = ? parser.find_rule(rule_name)
  case rule.kind:
  of RK_TERMINAL:
    return parser.parse_terminal(rule.terminal)
  of RK_NON_TERMINAL:
    var location = parser.location
    for prod in rule.productions:
      var failed = false
      var parts: seq[seq[Struct]]
      for sym in prod.symbols:
        var collected_parts: seq[Struct]
        var matched = parser.parse(sym.name)

        case sym.kind:
        of RK_AT_MOST_ONE:
          if matched.is_err: continue
          collected_parts.add(matched.get)
        of RK_EXACT_ONE:
          if matched.is_err: failed = true; break
          collected_parts.add(matched.get)
        of RK_AT_LEAST_ONE:
          if matched.is_err: failed = true; break
          while matched.is_ok:
            collected_parts.add(matched.get)
            matched = parser.parse(sym.name)
        of RK_ANY:
          while matched.is_ok:
            collected_parts.add(matched.get)
            matched = parser.parse(sym.name)

        parts.add(collected_parts)

      if not failed: return ok(rule.transform(parts))
      else: parser.location = location
    return err(fmt"Failed to match any production of <{rule.name}> at position {location}")

proc static_terminal_rule*(name, value: string): Rule =
  Rule(name: name, kind: RuleKind.RK_TERMINAL, terminal: Terminal(
      kind: TK_STATIC, value: value))

proc dynamic_terminal_rule*(name: string, matcher: proc(x: char): bool): Rule =
  Rule(name: name, kind: RuleKind.RK_TERMINAL, terminal: Terminal(
      kind: TK_DYNAMIC, matcher: matcher))

proc non_terminal_rule*(name: string, raw_productions: seq[string],
    transform: proc(parts: seq[seq[Struct]]): Struct = raw_transform): Rule =
  var productions: seq[Production]
  for p in raw_productions:
    let raw_symbols = p.replace(re"\s+", " ").strip().split(" ")
    var symbols: seq[Symbol]
    for s in raw_symbols:
      var kind: RegexKind
      var name: string
      case s[^1]:
      of '+':
        name = s[0..<(s.len - 1)].join("")
        kind = RegexKind.RK_AT_LEAST_ONE
      of '?':
        name = s[0..<(s.len - 1)].join("")
        kind = RegexKind.RK_AT_MOST_ONE
      of '*':
        name = s[0..<(s.len - 1)].join("")
        kind = RegexKind.RK_ANY
      else:
        name = s
        kind = RegexKind.RK_EXACT_ONE
      symbols.add(Symbol(name: name, kind: kind))
    productions.add(Production(symbols: symbols))

  Rule(name: name, kind: RuleKind.RK_NON_TERMINAL, productions: productions,
      transform: transform)

proc parse*(filename, entry: string, rules: seq[Rule]): Result[
    Struct, string] =
  let content = readFile(filename)
  let parser = Parser(grammar: Grammar(rules: rules),
      content: content, location: Location(filename: filename))
  parser.parse(entry)
