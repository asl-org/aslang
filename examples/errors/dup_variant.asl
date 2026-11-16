# NEGATIVE TEST — union data block with two variants named `A`.
# Rejected by `newUnionDef` ("duplicate variant encountered").
# TODO(parser-errors): the parser's backtracking swallows that message,
# so `asl build` reports "module must have at least 1
# struct/union/function block" at the `module` line instead.
module Foo:
  union:
    A {}
    A {}

  func a(y: i64): i64
    y

public module Driver:
  public func start(): i32
    i32 0
