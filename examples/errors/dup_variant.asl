# NEGATIVE TEST — union data block with two variants named `A`.
# Should fail validation with "union: duplicate variant 'A'"
# pointing at the second `A` line.
module Foo:
  union:
    A
    A

  func a(y: i64): i64
    y
