import results, strformat, sequtils, strutils

import grammar/rule, grammar/symbol, grammar/production
export rule, symbol, production

type Grammar*[State, Output] = ref object of RootObj
  rules: seq[Rule[State, Output]]

proc find_rule*[State, Output](grammar: Grammar[State, Output],
    rule_name: string): Result[Rule[State, Output], string] =
  for rule in grammar.rules:
    if rule.name == rule_name:
      return ok(rule)
  return err(fmt"Failed to find rule: {rule_name}")

# Ensure that rule's dependency rules are also present in the grammar
proc validate_rule_deps[State, Output](grammar: Grammar[State, Output],
    rule: Rule[State, Output]): Result[void, string] =
  case rule.kind
  of RK_RECURSIVE:
    for prod in rule.productions:
      for symbol in prod.symbols:
        # rule with cyclical deps
        if rule.name == symbol.name: return err(fmt"Rule {rule.name} is cyclic")
        # ensure dependency is present in the grammar
        discard ? grammar.find_rule(symbol.name)
  else:
    discard

  return ok()

proc add_rule*[State, Output](grammar: Grammar[State, Output], rule: Rule[State,
    Output]): Result[Grammar[State, Output], string] =
  let maybe_rule = grammar.find_rule(rule.name)
  if maybe_rule.is_ok: return err(fmt"Rule {rule.name} already exists")

  ? grammar.validate_rule_deps(rule)
  grammar.rules.add(rule)
  ok(grammar)

proc new_grammar*[State, Output](rules: seq[Rule[State, Output]]): Result[
    Grammar[State, Output], string] =
  var grammar = Grammar[State, Output](rules: @[])
  for rule in rules:
    grammar = ? grammar.add_rule(rule)
  return ok(grammar)

proc `$`*[State, Output](grammar: Grammar[State, Output]): string =
  grammar.rules.map(proc(r: Rule[State, Output]): string = $(r)).join("\n\n")
