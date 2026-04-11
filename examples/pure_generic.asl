# File with only a generic block, no modules. Verifies that
# rule #2 (file must have ≥1 module or generic) is satisfied by
# generics alone — previously only exercised via hello.asl which
# also has a module.
generic Eq:
  func eq(a: Eq, b: Eq): bool
  func hash(a: Eq): u128
