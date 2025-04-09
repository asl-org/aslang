import results, strutils

import common
import scope

import builtins/unsafe_print
import builtins/unsafe_add
import builtins/unsafe_subtract
import builtins/unsafe_multiply
import builtins/unsafe_division
import builtins/unsafe_modulo
import builtins/bitwise_and
import builtins/bitwise_or
import builtins/bitwise_xor

proc builtin_functions*(): seq[Function] = @[
  print_fn,
  add_fn,
  subtract_fn,
  multiply_fn,
  division_fn,
  modulo_fn,
  bitwise_and_fn,
  bitwise_or_fn,
  bitwise_xor_fn,
]

proc compile(scope: var Scope, s: Statement): Result[string, string] =
  case s.kind:
    of StatementKind.SK_INIT: scope.init(s.initializer)
    of StatementKind.SK_FNCALL: scope.call(s.fncall)

proc generate*(statements: seq[Statement]): Result[string, string] =
  var c_statements: seq[string] = @[]
  var scope = Scope(functions: builtin_functions())

  for s in statements:
    c_statements.add( ? scope.compile(s))

  let context = @[
    """#include "runtime/asl.h"""",
    "",
    "c_int main(c_int argc, c_char **argv)",
    "{",
    "",
    c_statements.join("\n"),
    "",
    "return 0;",
    "}",
  ]

  ok(context.join("\n"))

