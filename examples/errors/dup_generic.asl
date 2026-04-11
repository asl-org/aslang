# NEGATIVE TEST — two generics named Key in the same file.
# Should fail validation with "duplicate name 'Key'" pointing at
# the second `generic Key:` header.
generic Key:
  func hash(key: Key): u128

generic Key:
  func eq(a: Key, b: Key): bool
