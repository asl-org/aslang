# NEGATIVE TEST — two modules named Foo in the same file.
# Should fail validation with "duplicate name 'Foo'" pointing at
# the second `module Foo:` header.
module Foo:
  func a(x: i64): i64
    x

module Foo:
  func b(x: i64): i64
    x
