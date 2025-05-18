app Example:
  fn loop(Bitset primes, U64 i, U64 n) returns U64:
    op = U64.compare(i, n)
    match op:
      case 0:
        i
      case 1:
        i
      else:
        byte = Bitset.get(primes, i)
        Byte.print(byte)
        next_i = U64.add(i, 1)
        MODULE.loop(primes, next_i, n)

  fn start(Byte seed) returns Byte:
    exit_success = Byte 0

    primes0 = Bitset { bits: 100 }
    Bitset.print(primes0)

    # set 0th bit
    primes1 = Bitset.set(primes0, 0)
    Bitset.print(primes1)

    MODULE.loop(primes1, 0, 8)

    free_bits = Bitset.free(primes1)
    U64.print(free_bits)


    # unset 0th bit
    # primes2 = Bitset.unset(primes1, 0)
    # Bitset.print(primes2)

    # toggle 0th bit
    # primes3 = Bitset.toggle(primes2, 0)
    # Bitset.print(primes3)

    exit_success