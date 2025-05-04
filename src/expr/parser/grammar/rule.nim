import results, strutils
import production, symbol

type
  RuleKind* = enum RK_STATIC, RK_MATCHER, RK_RECURSIVE
  RuleMatcher* = proc(x: char): bool
  RuleReducer*[State, Output] = proc(state: State, value: string): (State, Output)
  RecursiveRuleReducer*[State, Output] = proc(state: State, parts: seq[seq[seq[
      Output]]]): (State, Output)

  Rule*[State, Output] = ref object of RootObj
    name: string
    desc: string
    case kind: RuleKind
    of RK_STATIC:
      value: string
      static_reducer: RuleReducer[State, Output]
    of RK_MATCHER:
      matcher: RuleMatcher
      match_reducer: RuleReducer[State, Output]
    of RK_RECURSIVE:
      productions: seq[Production]
      recursive_reducer: RecursiveRuleReducer[State, Output]

proc name*(rule: Rule): string = rule.name
proc kind*(rule: Rule): RuleKind = rule.kind

proc value*(rule: Rule): string = rule.value
proc matcher*(rule: Rule): RuleMatcher = rule.matcher
proc productions*(rule: Rule): seq[Production] = rule.productions

proc reduce_static*[State, Output](rule: Rule[State, Output], state: State,
    value: string): (State, Output) = rule.static_reducer(state, value)
proc reduce_match*[State, Output](rule: Rule[State, Output], state: State,
    value: string): (State, Output) = rule.match_reducer(state, value)
proc reduce_recursive*[State, Output](rule: Rule[State, Output], state: State,
    parts: seq[seq[seq[Output]]]): (State, Output) = rule.recursive_reducer(
        state, parts)

proc static_rule*[State, Output](name, desc, value: string,
    reducer: RuleReducer[State, Output]): Rule[State, Output] =
  Rule[State, Output](kind: RK_STATIC, name: name, desc: desc, value: value,
      static_reducer: reducer)

proc matcher_rule*[State, Output](name, desc: string, matcher: RuleMatcher,
    reducer: RuleReducer[State, Output]): Rule[State, Output] =
  Rule[State, Output](kind: RK_MATCHER, name: name, desc: desc,
      matcher: matcher, match_reducer: reducer)

proc non_terminal_rule*[State, Output](name: string, productions: seq[
    Production], reducer: RecursiveRuleReducer[State, Output]): Rule[State, Output] =
  Rule[State, Output](name: name, kind: RuleKind.RK_RECURSIVE,
      productions: productions, recursive_reducer: reducer)

proc any*(rule: Rule): Symbol = new_symbol_any(rule.name)
proc at_most_one*(rule: Rule): Symbol = new_symbol_at_most_one(rule.name)
proc exact_one*(rule: Rule): Symbol = new_symbol_exact_one(rule.name)
proc at_least_one*(rule: Rule): Symbol = new_symbol_at_least_one(rule.name)

proc `$`*(rule: Rule): string =
  case rule.kind:
  of RK_STATIC, RK_MATCHER: rule.name & " ::= " & rule.desc
  of RK_RECURSIVE:
    let prefix = rule.name & " ::= "
    var lines = @[prefix & $(rule.productions[0])]
    for prod in rule.productions[1..^1]:
      lines.add((" ".repeat(prefix.len - 2)) & "| " & $(prod))
    lines.join("\n")
