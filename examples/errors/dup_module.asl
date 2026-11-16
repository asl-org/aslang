# NEGATIVE TEST — two modules named Foo in the same file.
# Fails with "duplicate type declaration encountered" pointing at
# the second `module Foo:` header.
module Foo:
  func a(x: i64): i64
    x

module Foo:
  func b(x: i64): i64
    x

public module Driver:
  public func start(): i32
    i32 0
