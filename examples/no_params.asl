# Zero-argument function — exercises `func name(): ReturnType`
# with an empty argument-definition list. The parser's
# argumentDefinitionListSpec must accept `()` with no entries.

import "base.asl"
module Foo:
  func start(): u8
    u8 0
