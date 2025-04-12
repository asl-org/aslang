import results, strformat, strutils

type
  RegexKind = enum
    RK_EXACT_ONE, RK_ANY, RK_AT_LEAST_ONE, RK_AT_MOST_ONE

  Symbol = ref object of RootObj
    name: string
    kind: RegexKind

  Production = ref object of RootObj
    symbols: seq[Symbol]

  RuleKind = enum
    RK_STATIC_TERMINAL, RK_DYNAMIC_TERMINAL, RK_NON_TERMINAL

  Rule = ref object of RootObj
    name: string
    case kind: RuleKind
    of RK_STATIC_TERMINAL: terminal: string
    of RK_DYNAMIC_TERMINAL: matcher: proc(x: char): bool
    of RK_NON_TERMINAL: productions: seq[Production]

  Grammar = ref object of RootObj
    entry: string
    rules: seq[Rule]

proc find(grammar: Grammar, rule: string): Result[Rule, string] =
  for r in grammar.rules:
    if r.name == rule:
      return ok(r)
  return err(fmt"failed to find rule {rule}")

proc match(rule: Rule, grammar: Grammar, content: string, index: int = 0): (
    bool, int) =
  case rule.kind:
  of RuleKind.RK_STATIC_TERMINAL:
    let endpoint = index + rule.terminal.len
    if endpoint >= content.len: return(false, index)
    let matched = rule.terminal == content[index..<endpoint].join("")
    return (matched, endpoint)
  of RuleKind.RK_DYNAMIC_TERMINAL:
    if index >= content.len: return(false, index)
    let matched = rule.matcher(content[index])
    return (matched, index + int(matched))
  of RuleKind.RK_NON_TERMINAL:
    for p in rule.productions:
      var head: int = index
      for s in p.symbols:
        let maybe_rule = grammar.find(s.name)
        if maybe_rule.is_err:
          echo maybe_rule.error
          head = index
          break

        case s.kind:
        of RegexKind.RK_AT_MOST_ONE:
          let (matched, new_head) = maybe_rule.get.match(grammar, content, head)
          discard matched
          head = new_head
        of RegexKind.RK_EXACT_ONE:
          let (matched, new_head) = maybe_rule.get.match(grammar, content, head)
          if matched: head = new_head
          else: head = index; break
        of RegexKind.RK_AT_LEAST_ONE:
          var (matched, new_head) = maybe_rule.get.match(grammar, content, head)
          if matched: head = new_head
          else: head = index; break
          (matched, new_head) = maybe_rule.get.match(grammar, content, head)
          while matched:
            head = new_head
            (matched, new_head) = maybe_rule.get.match(grammar, content, head)
          head = new_head
        of RegexKind.RK_ANY:
          var (matched, new_head) = maybe_rule.get.match(grammar, content, head)
          while matched:
            head = new_head
            (matched, new_head) = maybe_rule.get.match(grammar, content, head)
          head = new_head
      if head > index:
        return (true, head)
  (false, index)

proc match(grammar: Grammar, content: string): void =
  let maybe_rule = grammar.find(grammar.entry)
  if maybe_rule.is_err:
    echo maybe_rule.error
  echo "Rule Matched: ", maybe_rule.get.match(grammar, content)

#### USER CODE ####

let content = @[
  "x = 1",
  "dsdf=2",
  "dkhjk    =2",
  "erb=   2 x",
  "dsxvc    =   2",
].join("\n")

let grammar = Grammar(
  entry: "program",
  rules: @[
    Rule(name: "new_line", kind: RuleKind.RK_STATIC_TERMINAL, terminal: "\n"),
    Rule(name: "space", kind: RuleKind.RK_STATIC_TERMINAL, terminal: " "),
    Rule(name: "equal", kind: RuleKind.RK_STATIC_TERMINAL, terminal: "="),
    Rule(name: "lowercase_alphabet", kind: RuleKind.RK_DYNAMIC_TERMINAL,
        matcher: isLowerAscii),
    Rule(name: "uppercase_alphabet", kind: RuleKind.RK_DYNAMIC_TERMINAL,
        matcher: isUpperAscii),
    Rule(name: "digit", kind: RuleKind.RK_DYNAMIC_TERMINAL,
        matcher: isDigit),
    Rule(name: "alphabet", kind: RuleKind.RK_NON_TERMINAL,
        productions: @[
          Production(symbols: @[Symbol(name: "lowercase_alphabet",
              kind: RegexKind.RK_EXACT_ONE)]),
          Production(symbols: @[Symbol(name: "uppercase_alphabet",
              kind: RegexKind.RK_EXACT_ONE)])]),
    Rule(name: "identifier", kind: RuleKind.RK_NON_TERMINAL,
      productions: @[
        Production(symbols: @[Symbol(name: "alphabet",
            kind: RegexKind.RK_AT_LEAST_ONE)])]),
    Rule(name: "integer", kind: RuleKind.RK_NON_TERMINAL,
      productions: @[
        Production(symbols: @[Symbol(name: "digit",
            kind: RegexKind.RK_AT_LEAST_ONE)])]),
    Rule(name: "statement", kind: RuleKind.RK_NON_TERMINAL,
      productions: @[Production(symbols: @[
            Symbol(name: "identifier", kind: RegexKind.RK_EXACT_ONE),
            Symbol(name: "space", kind: RegexKind.RK_ANY),
            Symbol(name: "equal", kind: RegexKind.RK_EXACT_ONE),
            Symbol(name: "space", kind: RegexKind.RK_ANY),
            Symbol(name: "integer", kind: RegexKind.RK_EXACT_ONE),
            Symbol(name: "space", kind: RegexKind.RK_ANY),
            Symbol(name: "new_line", kind: RegexKind.RK_EXACT_ONE)])]),
    Rule(name: "program", kind: RuleKind.RK_NON_TERMINAL,
      productions: @[Production(symbols: @[Symbol(name: "statement",
          kind: RegexKind.RK_AT_LEAST_ONE)])])
])

when isMainModule:
  grammar.match(content)
