import re, results, strformat, strutils

type
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
      productions: seq[Production]

  Grammar = ref object of RootObj
    entry: string
    rules: seq[Rule]

  MatchResult = object
    matchedText: string
    head: int
    tail: int

proc find(grammar: Grammar, rule: string): Result[Rule, string] =
  for r in grammar.rules:
    if r.name == rule:
      return ok(r)
  return err(fmt"Failed to find rule: {rule}")

proc match(terminal: Terminal, content: string, index: int): Result[MatchResult, string] =
  case terminal.kind:
    of TK_STATIC:
      let tail = index + terminal.value.len
      if tail > content.len:
        return err(fmt"Expected '{terminal.value}' but reached end of input at position {index}")
      let segment = content[index..<tail]
      if segment == terminal.value:
        return ok(MatchResult(head: index, tail: tail,
            matchedText: segment))
      else:
        return err(fmt"Expected '{terminal.value}' at position {index}, got '{segment}'")

    of TK_DYNAMIC:
      if index >= content.len:
        return err(fmt"Expected dynamic terminal at {index}, but input ended")
      let ch = content[index]
      if terminal.matcher(ch):
        return ok(MatchResult(head: index, tail: index + 1, matchedText: $ch))
      else:
        return err(fmt"Dynamic matcher failed at position {index} for char '{ch}'")

proc match(rule: Rule, grammar: Grammar, content: string,
    index: int = 0): Result[MatchResult, string] =
  case rule.kind:
  of RK_TERMINAL: rule.terminal.match(content, index)
  of RK_NON_TERMINAL:
    for prod in rule.productions:
      var currentIndex = index
      var matchedText = ""
      var failed = false
      for sym in prod.symbols:
        let subRule = ? grammar.find(sym.name)
        var matchedOnce = false
        var collected = ""
        case sym.kind:
        of RK_EXACT_ONE:
          let matched = subRule.match(grammar, content, currentIndex)
          if matched.isErr: failed = true; break
          currentIndex = matched.get.tail
          collected.add matched.get.matchedText
        of RK_AT_MOST_ONE:
          let matched = subRule.match(grammar, content, currentIndex)
          if matched.isOk:
            currentIndex = matched.get.tail
            collected.add matched.get.matchedText
        of RK_AT_LEAST_ONE:
          while true:
            let matched = subRule.match(grammar, content, currentIndex)
            if matched.isErr: break
            currentIndex = matched.get.tail
            collected.add matched.get.matchedText
            matchedOnce = true
          if not matchedOnce:
            failed = true
            break
        of RK_ANY:
          while true:
            let matched = subRule.match(grammar, content, currentIndex)
            if matched.isErr: break
            currentIndex = matched.get.tail
            collected.add matched.get.matchedText
        matchedText.add collected
      if not failed:
        return ok(MatchResult(head: index, tail: currentIndex,
            matchedText: matchedText))
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

proc non_terminal_rule*(name: string, raw_productions: seq[string]): Rule =
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

  Rule(name: name, kind: RuleKind.RK_NON_TERMINAL, productions: productions)

proc new_grammar*(entry: string, rules: seq[Rule]): Grammar =
  Grammar(entry: entry, rules: rules)
