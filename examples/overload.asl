# Function overloading — two functions named `bar` in the same
# module with different parameter types (i64, str). Verifies the
# validator's Table[string, seq[int]] function index accepts
# same-name duplicates.
import "base.aslb"
module Foo:
  func bar(a: i64): i64
    a

  func bar(a: String): String
    a
