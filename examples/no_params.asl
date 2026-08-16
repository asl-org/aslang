# Zero-argument function — exercises `func name(): ReturnType`
# with an empty argument-definition list. The parser's
# argumentDefinitionListSpec must accept `()` with no entries.

module Foo:
  func start(): u8
    u8 0

public module Driver:
  public func start(): i32
    i32 0