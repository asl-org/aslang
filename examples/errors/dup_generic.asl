# NEGATIVE TEST — two generics named Hashable in the same file.
# Fails with "duplicate type declaration encountered" pointing at
# the second `generic Hashable:` header. (Not `Key`: that name is
# already taken by the auto-imported `@std`.)
generic Hashable:
  func hash(key: Hashable): u64

generic Hashable:
  func eq(a: Hashable, b: Hashable): u8

public module Driver:
  public func start(): i32
    i32 0
