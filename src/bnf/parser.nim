import results, strformat, strutils

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
        return ok(MatchResult(head: index, tail: tail,
            matchedText: segment))
      else:
        return err(fmt"Expected '{rule.terminal.value}' at position {index}, got '{segment}'")

    of TK_DYNAMIC:
      if index >= content.len:
        return err(fmt"Expected dynamic terminal at {index}, but input ended")
      let ch = content[index]
      if rule.terminal.matcher(ch):
        return ok(MatchResult(head: index, tail: index + 1, matchedText: $ch))
      else:
        return err(fmt"Dynamic matcher failed at position {index} for char '{ch}'")

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

proc match(grammar: Grammar, content: string): Result[MatchResult, string] =
  let entryRule = ? grammar.find(grammar.entry)
  return entryRule.match(grammar, content)


let grammar = Grammar(
  entry: "program",
  rules: @[
    # new_line ::= "\n"
  Rule(name: "new_line", kind: RuleKind.RK_TERMINAL, terminal: Terminal(
      kind: TK_STATIC, value: "\n")),
  # space ::= " "
  Rule(name: "space", kind: RuleKind.RK_TERMINAL, terminal: Terminal(
      kind: TK_STATIC, value: " ")),
  # equal ::= "="
  Rule(name: "equal", kind: RuleKind.RK_TERMINAL, terminal: Terminal(
      kind: TK_STATIC, value: "=")),
  # lowercase_alphabet ::= [a-z]
  Rule(name: "lowercase_alphabet", kind: RuleKind.RK_TERMINAL,
      terminal: Terminal(kind: TK_DYNAMIC, matcher: isLowerAscii)),
  # uppercase_alphabet ::= [A-Z]
  Rule(name: "uppercase_alphabet", kind: RuleKind.RK_TERMINAL,
      terminal: Terminal(kind: TK_DYNAMIC, matcher: isUpperAscii)),
  # alphabet ::= lowercase_alphabet | uppercase_alphabet
  Rule(name: "alphabet", kind: RuleKind.RK_NON_TERMINAL,
      productions: @[
        Production(symbols: @[Symbol(name: "lowercase_alphabet",
            kind: RegexKind.RK_EXACT_ONE)]),
        Production(symbols: @[Symbol(name: "uppercase_alphabet",
            kind: RegexKind.RK_EXACT_ONE)])]),
  # digit ::= [0-9]
  Rule(name: "digit", kind: RuleKind.RK_TERMINAL,
      terminal: Terminal(kind: TK_DYNAMIC, matcher: isDigit)),
  # word ::= alphabet+
  Rule(name: "word", kind: RuleKind.RK_NON_TERMINAL,
      productions: @[
        Production(symbols: @[Symbol(name: "alphabet",
            kind: RegexKind.RK_AT_LEAST_ONE)])]),
  # integer ::= digit+
  Rule(name: "integer", kind: RuleKind.RK_NON_TERMINAL,
    productions: @[
      Production(symbols: @[Symbol(name: "digit",
          kind: RegexKind.RK_AT_LEAST_ONE)])]),
  # identifier_head ::= underscore | word
  Rule(name: "identifier_head", kind: RuleKind.RK_NON_TERMINAL,
    productions: @[
      Production(symbols: @[Symbol(name: "word",
          kind: RegexKind.RK_EXACT_ONE)]),
      Production(symbols: @[Symbol(name: "underscore",
          kind: RegexKind.RK_EXACT_ONE)])]),
  # identifier_tail ::= underscore | word | integer
  Rule(name: "identifier_tail", kind: RuleKind.RK_NON_TERMINAL,
    productions: @[
      Production(symbols: @[Symbol(name: "word",
          kind: RegexKind.RK_EXACT_ONE)]),
      Production(symbols: @[Symbol(name: "underscore",
          kind: RegexKind.RK_EXACT_ONE)]),
      Production(symbols: @[Symbol(name: "integer",
          kind: RegexKind.RK_EXACT_ONE)])]),
  # identifier ::= identifier_head identifier_tail*
  Rule(name: "identifier", kind: RuleKind.RK_NON_TERMINAL,
    productions: @[
      Production(symbols: @[
        Symbol(name: "identifier_head", kind: RegexKind.RK_EXACT_ONE),
        Symbol(name: "identifier_tail", kind: RegexKind.RK_ANY)])]),
  # empty_line ::= space* new_line
  Rule(name: "empty_line", kind: RuleKind.RK_NON_TERMINAL,
    productions: @[Production(symbols: @[
      Symbol(name: "space", kind: RegexKind.RK_ANY),
      Symbol(name: "new_line", kind: RegexKind.RK_EXACT_ONE)])]),
  # statement ::= identifier space* equal space* integer empty_line+
  Rule(name: "statement", kind: RuleKind.RK_NON_TERMINAL,
    productions: @[Production(symbols: @[
      Symbol(name: "identifier", kind: RegexKind.RK_EXACT_ONE),
      Symbol(name: "space", kind: RegexKind.RK_ANY),
      Symbol(name: "equal", kind: RegexKind.RK_EXACT_ONE),
      Symbol(name: "space", kind: RegexKind.RK_ANY),
      Symbol(name: "integer", kind: RegexKind.RK_EXACT_ONE),
      Symbol(name: "empty_line", kind: RegexKind.RK_AT_LEAST_ONE)])]),
  # last_statement ::= identifier space* equal space* integer space*
  Rule(name: "last_statement", kind: RuleKind.RK_NON_TERMINAL,
    productions: @[Production(symbols: @[
      Symbol(name: "identifier", kind: RegexKind.RK_EXACT_ONE),
      Symbol(name: "space", kind: RegexKind.RK_ANY),
      Symbol(name: "equal", kind: RegexKind.RK_EXACT_ONE),
      Symbol(name: "space", kind: RegexKind.RK_ANY),
      Symbol(name: "integer", kind: RegexKind.RK_EXACT_ONE),
      Symbol(name: "space", kind: RegexKind.RK_ANY)])]),
  # program ::= statement* last_statement
  Rule(name: "program", kind: RuleKind.RK_NON_TERMINAL,
    productions: @[Production(symbols: @[Symbol(name: "statement",
        kind: RegexKind.RK_ANY), Symbol(name: "last_statement",
        kind: RegexKind.RK_AT_LEAST_ONE)])])
])
let content = @[
  "x = 1",
  "dsdf=2",
  "dkhjk    =2",
  "erb=   2",
  "dsxvc    =   2",
].join("\n")

when isMainModule:
  let maybe_match = grammar.match(content)
  if maybe_match.isErr: echo maybe_match.error
  echo maybe_match.get
