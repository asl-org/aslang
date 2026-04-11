# Nested generic type parameters — exercises recursive
# argumentTypeSpec handling (Map[str, Array[u64]]) in struct
# fields and function signatures.
module Cache:
  struct:
    entries: Map[str, Array[u64]]

  func get(c: Cache): Map[str, Array[u64]]
    c.entries
