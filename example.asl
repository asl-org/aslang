struct Bitset:
  fields:
    Pointer ptr
    U64 size

app Example:
  fn start(U8 seed) returns U8:
    exit_success = U8 127