# import results, strformat, strutils

# type
#   RegexKind = enum
#     RK_EXACT_ONE, RK_ANY, RK_AT_LEAST_ONE, RK_AT_MOST_ONE

#   Symbol = ref object of RootObj
#     name: string
#     kind: RegexKind

#   Production = ref object of RootObj
#     symbols: seq[Symbol]

#   RuleKind = enum
#     RK_STATIC_TERMINAL, RK_DYNAMIC_TERMINAL, RK_NON_TERMINAL

#   Rule = ref object of RootObj
#     name: string
#     case kind: RuleKind
#     of RK_STATIC_TERMINAL: terminal: string
#     of RK_DYNAMIC_TERMINAL: matcher: proc(x: char): bool
#     of RK_NON_TERMINAL: productions: seq[Production]

#   Grammar = ref object of RootObj
#     entry: string
#     rules: seq[Rule]

# proc find(grammar: Grammar, rule: string): Result[Rule, string] =
#   for r in grammar.rules:
#     if r.name == rule:
#       return ok(r)
#   return err(fmt"failed to find rule {rule}")

# proc match(rule: Rule, grammar: Grammar, content: string, index: int = 0): (
#     bool, int) =
#   case rule.kind:
#   of RuleKind.RK_STATIC_TERMINAL:
#     let endpoint = index + rule.terminal.len
#     if endpoint >= content.len: return(false, index)
#     let matched = rule.terminal == content[index..<endpoint].join("")
#     return (matched, endpoint)
#   of RuleKind.RK_DYNAMIC_TERMINAL:
#     if index >= content.len: return(false, index)
#     let matched = rule.matcher(content[index])
#     return (matched, index + int(matched))
#   of RuleKind.RK_NON_TERMINAL:
#     for p in rule.productions:
#       var head: int = index
#       for s in p.symbols:
#         let maybe_rule = grammar.find(s.name)
#         if maybe_rule.is_err:
#           echo maybe_rule.error
#           head = index
#           break

#         case s.kind:
#         of RegexKind.RK_AT_MOST_ONE:
#           let (matched, new_head) = maybe_rule.get.match(grammar, content, head)
#           discard matched
#           head = new_head
#         of RegexKind.RK_EXACT_ONE:
#           let (matched, new_head) = maybe_rule.get.match(grammar, content, head)
#           if matched: head = new_head
#           else: head = index; break
#         of RegexKind.RK_AT_LEAST_ONE:
#           var (matched, new_head) = maybe_rule.get.match(grammar, content, head)
#           if matched: head = new_head
#           else: head = index; break
#           (matched, new_head) = maybe_rule.get.match(grammar, content, head)
#           while matched:
#             head = new_head
#             (matched, new_head) = maybe_rule.get.match(grammar, content, head)
#           head = new_head
#         of RegexKind.RK_ANY:
#           var (matched, new_head) = maybe_rule.get.match(grammar, content, head)
#           while matched:
#             head = new_head
#             (matched, new_head) = maybe_rule.get.match(grammar, content, head)
#           head = new_head
#       if head > index:
#         return (true, head)
#   (false, index)

# proc match(grammar: Grammar, content: string): void =
#   let maybe_rule = grammar.find(grammar.entry)
#   if maybe_rule.is_err:
#     echo maybe_rule.error
#   echo "Rule Matched: ", maybe_rule.get.match(grammar, content)

import results, strformat, strutils

# ================== TYPES ==================
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
    nextIndex: int
    matchedText: string

# ================== UTILITY ==================
proc find(grammar: Grammar, rule: string): Result[Rule, string] =
  for r in grammar.rules:
    if r.name == rule:
      return ok(r)
  return err(fmt"Failed to find rule: {rule}")

# ================== MATCHER ==================
proc match(rule: Rule, grammar: Grammar, content: string,
    index: int = 0): Result[MatchResult, string] =
  case rule.kind:
  of RK_TERMINAL:
    case rule.terminal.kind:
    of TK_STATIC:
      let endpoint = index + rule.terminal.value.len
      if endpoint > content.len:
        return err(fmt"Expected '{rule.terminal.value}' but reached end of input at position {index}")
      let segment = content[index..<endpoint]
      if segment == rule.terminal.value:
        return ok(MatchResult(nextIndex: endpoint, matchedText: segment))
      else:
        return err(fmt"Expected '{rule.terminal.value}' at position {index}, got '{segment}'")

    of TK_DYNAMIC:
      if index >= content.len:
        return err(fmt"Expected dynamic terminal at {index}, but input ended")
      let ch = content[index]
      if rule.terminal.matcher(ch):
        return ok(MatchResult(nextIndex: index + 1, matchedText: $ch))
      else:
        return err(fmt"Dynamic matcher failed at position {index} for char '{ch}'")

  of RK_NON_TERMINAL:
    for prod in rule.productions:
      var currentIndex = index
      var matchedText = ""
      var failed = false
      for sym in prod.symbols:
        let ruleResult = grammar.find(sym.name)
        if ruleResult.isErr:
          return err(ruleResult.error)
        let subRule = ruleResult.get
        var matchedOnce = false
        var collected = ""
        case sym.kind:
        of RK_EXACT_ONE:
          let matched = subRule.match(grammar, content, currentIndex)
          if matched.isErr: failed = true; break
          currentIndex = matched.get.nextIndex
          collected.add matched.get.matchedText
        of RK_AT_MOST_ONE:
          let matched = subRule.match(grammar, content, currentIndex)
          if matched.isOk:
            currentIndex = matched.get.nextIndex
            collected.add matched.get.matchedText
        of RK_AT_LEAST_ONE:
          while true:
            let matched = subRule.match(grammar, content, currentIndex)
            if matched.isErr: break
            currentIndex = matched.get.nextIndex
            collected.add matched.get.matchedText
            matchedOnce = true
          if not matchedOnce:
            failed = true
            break
        of RK_ANY:
          while true:
            let matched = subRule.match(grammar, content, currentIndex)
            if matched.isErr: break
            currentIndex = matched.get.nextIndex
            collected.add matched.get.matchedText
        matchedText.add collected
      if not failed:
        return ok(MatchResult(nextIndex: currentIndex,
            matchedText: matchedText))
    return err(fmt"Failed to match any production of <{rule.name}> at position {index}")

# ================== TOP-LEVEL ==================
proc match(grammar: Grammar, content: string): Result[MatchResult, string] =
  let entryRule = ? grammar.find(grammar.entry)
  return entryRule.match(grammar, content)


#### USER CODE ####

let content = @[
  "x = 1",
  "dsdf=2",
  "dkhjk    =2",
  "erb=   2",
  "dsxvc    =   2",
].join("\n")


let grammar = Grammar(
  entry: "program",
  rules: @[
    Rule(name: "new_line", kind: RuleKind.RK_TERMINAL, terminal: Terminal(
        kind: TK_STATIC, value: "\n")),
    Rule(name: "space", kind: RuleKind.RK_TERMINAL, terminal: Terminal(
        kind: TK_STATIC, value: " ")),
    Rule(name: "equal", kind: RuleKind.RK_TERMINAL, terminal: Terminal(
        kind: TK_STATIC, value: "=")),
    Rule(name: "lowercase_alphabet", kind: RuleKind.RK_TERMINAL,
        terminal: Terminal(kind: TK_DYNAMIC, matcher: isLowerAscii)),
    Rule(name: "uppercase_alphabet", kind: RuleKind.RK_TERMINAL,
        terminal: Terminal(kind: TK_DYNAMIC, matcher: isUpperAscii)),
    Rule(name: "digit", kind: RuleKind.RK_TERMINAL,
        terminal: Terminal(kind: TK_DYNAMIC, matcher: isDigit)),
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
  let maybe_match = grammar.match(content)
  if maybe_match.isErr: echo maybe_match.error
  echo maybe_match.get
