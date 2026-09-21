# Nested generic type parameters — exercises recursive
# argumentTypeSpec handling (Map[str, Array[u64]]) in struct
# fields and function signatures.
module Cache:
  struct:
    entries: Map[string, Array[u64]]

  func get(c: Cache): Map[string, Array[u64]]
    c.entries

public module Driver:
  public func start(): i32
    i32 0