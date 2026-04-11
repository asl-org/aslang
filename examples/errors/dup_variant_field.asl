# NEGATIVE TEST — union variant `A` has two fields both named `x`.
# Should fail validation with "variant 'A': duplicate field 'x'"
# pointing at the second `x` inside the braces.
module Foo:
  union:
    A { x: i64, x: u32 }
    B

  func a(y: i64): i64
    y
