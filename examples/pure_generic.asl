# File with only a generic block, no modules. Verifies that
# rule #2 (file must have ≥1 module or generic) is satisfied by
# generics alone — previously only exercised via hello.asl which
# also has a module.
import "base.asl"
generic Eq:
  func eq(a: Eq, b: Eq): u8
  func hash(a: Eq): u64
