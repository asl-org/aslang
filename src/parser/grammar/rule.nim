import results, strutils, strformat
import production, symbol

type Location* = object
  file: string
  line*: int = 1
  col*: int = 1
  index*: int = 0

proc `$`*(location: Location): string = fmt"{location.file}({location.line},{location.col})"
proc `<`*(a: Location, b: Location): bool = a.index < b.index
proc `>`*(a: Location, b: Location): bool = a.index > b.index
proc `==`*(a: Location, b: Location): bool = a.index == b.index

proc new_location*(filename: string): Location =
  Location(file: filename)

type
  RuleKind* = enum RK_STATIC, RK_MATCHER, RK_RECURSIVE
  RuleMatcher* = proc(x: char): bool
  RuleReducer*[Output] = proc(loc: Location, value: string): Output
  RecursiveRuleReducer*[Output] = proc(loc: Location, parts: seq[seq[seq[
      Output]]]): Output

  Rule*[Output] = ref object of RootObj
    name: string
    desc: string
    case kind: RuleKind
    of RK_STATIC:
      value: string
      static_reducer: RuleReducer[Output]
    of RK_MATCHER:
      matcher: RuleMatcher
      match_reducer: RuleReducer[Output]
    of RK_RECURSIVE:
      productions: seq[Production]
      recursive_reducer: RecursiveRuleReducer[Output]

proc name*(rule: Rule): string = rule.name
proc kind*(rule: Rule): RuleKind = rule.kind

proc value*(rule: Rule): string = rule.value
proc matcher*(rule: Rule): RuleMatcher = rule.matcher
proc productions*(rule: Rule): seq[Production] = rule.productions

proc reduce_static*[Output](rule: Rule[Output], loc: Location,
    value: string): Output = rule.static_reducer(loc, value)
proc reduce_match*[Output](rule: Rule[Output], loc: Location,
    value: string): Output = rule.match_reducer(loc, value)
proc reduce_recursive*[Output](rule: Rule[Output], loc: Location,
    parts: seq[seq[seq[Output]]]): Output = rule.recursive_reducer(
        loc, parts)

proc static_rule*[Output](name, desc, value: string,
    reducer: RuleReducer[Output]): Rule[Output] =
  Rule[Output](kind: RK_STATIC, name: name, desc: desc, value: value,
      static_reducer: reducer)

proc matcher_rule*[Output](name, desc: string, matcher: RuleMatcher,
    reducer: RuleReducer[Output]): Rule[Output] =
  Rule[Output](kind: RK_MATCHER, name: name, desc: desc,
      matcher: matcher, match_reducer: reducer)

proc non_terminal_rule*[Output](name: string, productions: seq[
    Production], reducer: RecursiveRuleReducer[Output]): Rule[Output] =
  Rule[Output](name: name, kind: RuleKind.RK_RECURSIVE,
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
