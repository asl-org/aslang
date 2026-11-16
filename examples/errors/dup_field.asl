# NEGATIVE TEST — struct data block with two fields named `x`.
# Fails with "duplicate field encountered" pointing at the second `x`
# line, with "see previous declaration" pointing at the first.
module Foo:
  struct:
    x: i64
    x: u32

  func a(y: i64): i64
    y

public module Driver:
  public func start(): i32
    i32 0
