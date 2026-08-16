# Function overloading — two functions named `bar` in the same
# module with different parameter types (i64, str). Verifies the
# validator's Table[string, seq[int]] function index accepts
# same-name duplicates.
module Foo:
  func bar(a: i64): i64
    a

  func bar(a: String): String
    a

public module Driver:
  public func start(): i32
    i32 0