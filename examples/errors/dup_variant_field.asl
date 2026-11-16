# NEGATIVE TEST — union variant `A` has two fields both named `x`.
# Fails with "duplicate field encountered" pointing at the second `x`
# inside the braces.
module Foo:
  union:
    A { x: i64, x: u32 }
    B {}

  func a(y: i64): i64
    y

public module Driver:
  public func start(): i32
    i32 0
