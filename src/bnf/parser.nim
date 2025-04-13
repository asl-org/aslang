import re, results, strformat, strutils

type
  StructKind* = enum
    SK_RAW, SK_NON_TERMINAL
  Struct* = ref object of RootObj
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
    entry: string
    rules: seq[Rule]

  MatchResult = object
    struct: Struct
    head: int
    tail: int

proc raw_transform(parts: seq[seq[Struct]]): Struct =
  var value: string
  for group in parts:
    var collected: string
    for chunk in group:
      case chunk.kind:
      of StructKind.SK_RAW:
        collected.add(chunk.value)
      else:
        discard
    value.add(collected)
  Struct(kind: StructKind.SK_RAW, value: value)

proc find(grammar: Grammar, rule: string): Result[Rule, string] =
  for r in grammar.rules:
    if r.name == rule:
      return ok(r)
  return err(fmt"Failed to find rule: {rule}")

proc match(rule: Rule, grammar: Grammar, content: string,
    index: int = 0): Result[MatchResult, string] =
  case rule.kind:
  of RK_TERMINAL:
    case rule.terminal.kind:
    of TK_STATIC:
      let tail = index + rule.terminal.value.len
      if tail > content.len:
        return err(fmt"Expected '{rule.terminal.value}' but reached end of input at position {index}")
      let segment = content[index..<tail]
      if segment == rule.terminal.value:
        return ok(MatchResult(head: index, tail: tail, struct: Struct(kind: SK_RAW,
                value: segment)))
      else:
        return err(fmt"Expected '{rule.terminal.value}' at position {index}, got '{segment}'")

    of TK_DYNAMIC:
      if index >= content.len:
        return err(fmt"Expected dynamic terminal at {index}, but input ended")
      let ch = content[index]
      if rule.terminal.matcher(ch):
        return ok(MatchResult(head: index, tail: index + 1, struct: Struct(kind: SK_RAW,
                value: $ch)))
      else:
        return err(fmt"Dynamic matcher failed at position {index} for char '{ch}'")
  of RK_NON_TERMINAL:
    for prod in rule.productions:
      var head = index
      var matchedText: seq[string]
      var failed = false
      var parts: seq[seq[Struct]]
      for sym in prod.symbols:
        let maybe_sub_rule = grammar.find(sym.name)
        if maybe_sub_rule.is_err: failed = true; break

        case sym.kind:
        of RK_AT_MOST_ONE:
          let matched = maybe_sub_rule.get.match(grammar, content, head)
          if matched.is_ok:
            head = matched.get.tail
            parts.add(@[matched.get.struct])
          else:
            parts.add(@[])
        of RK_EXACT_ONE:
          let matched = maybe_sub_rule.get.match(grammar, content, head)
          if matched.is_err: failed = true; break
          head = matched.get.tail
          parts.add(@[matched.get.struct])
        of RK_AT_LEAST_ONE:
          var matched = maybe_sub_rule.get.match(grammar, content, head)
          var match_count = 0
          var collected: seq[string]
          var collected_parts: seq[Struct]
          while matched.is_ok:
            match_count += 1
            head = matched.get.tail
            collected_parts.add(matched.get.struct)
            matched = maybe_sub_rule.get.match(grammar, content, head)
          if match_count < 1: failed = true; break
          matchedText.add(collected.join(""))
          parts.add(collected_parts)
        of RK_ANY:
          var collected: seq[string]
          var collected_parts: seq[Struct]
          while true:
            let matched = maybe_sub_rule.get.match(grammar, content, head)
            if matched.is_err: break
            head = matched.get.tail
            collected_parts.add(matched.get.struct)
          matchedText.add(collected.join(""))
          parts.add(collected_parts)

      if not failed:
        return ok(MatchResult(head: index, tail: head, struct: rule.transform(parts)))
    return err(fmt"Failed to match any production of <{rule.name}> at position {index}")

proc match*(grammar: Grammar, content: string): Result[MatchResult, string] =
  let entryRule = ? grammar.find(grammar.entry)
  return entryRule.match(grammar, content)

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

proc new_grammar*(entry: string, rules: seq[Rule]): Grammar =
  Grammar(entry: entry, rules: rules)
