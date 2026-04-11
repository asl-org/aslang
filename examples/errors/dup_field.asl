# NEGATIVE TEST — struct data block with two fields named `x`.
# Should fail validation with "struct: duplicate field 'x'"
# pointing at the second `x` line.
module Foo:
  struct:
    x: i64
    x: u32

  func a(y: i64): i64
    y
