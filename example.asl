struct Bitset:
  fields:
    Pointer ptr
    U64 bits

app Example:
  fn start(U8 seed) returns U8:
    exit_success = U8 0

    bits = U64 64
    ptr = System.allocate(bits)

    primes = Bitset { ptr: ptr, bits: 64 }
    U64.print(primes.bits)

    System.free(ptr)

    exit_success