import results, strutils

import common
import scope
import builtins

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
    """#include "asl.h"""",
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

