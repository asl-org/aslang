# NEGATIVE TEST — struct field references a type that is neither
# a built-in, a module/generic in the current file, nor an
# imported name. resolveArgumentType fails with "unknown type".
module Foo:
  struct:
    value: NotAType

  func noop(): u8
    u8 0
