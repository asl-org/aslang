fn start(U8 seed): U8
  n = U64_init(100)

  a = U64_subtract(n, 1)
  b = U64_add(n, 1)

  c = U64_multiply(n, 3)
  d = U64_add(c, 2)

  e = U64_multiply(a, b)
  f = U64_multiply(e, d)
  g = U64_multiply(n, f)

  h = U64_quotient(g, 12)
  _ = System_print_U64(h)

  exit_success = U8_init(0)
