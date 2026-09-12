# Project Euler #5 style exercise — gcd/lcm via Euclidean recursion.
# Exercises integer comparison with signed literal patterns
# (case -1), mutually-calling functions within a module, and
# tail-recursive loops.
public module Example:
  func gcd(a: u64, b: u64): u64!
    match u64.compare(b, 0):
      case 0:
        u64!.Ok { value: a }
      case _:
        c = try u64.remainder(a, b)
        Example.gcd(b, c)

  func lcm(a: u64, b: u64): u64!
    c = try u64.multiply(a, b)
    d = try Example.gcd(a, b)
    u64.quotient(c, d)

  func solve(i: u64, n: u64, j: u64): u64!
    op = u64.compare(i, n)
    _ = match op:
      case -1:
        next_i = try u64.add(i, 1)
        next_j = try Example.lcm(i, j)
        Example.solve(next_i, n, next_j)
      case _:
        u64!.Ok { value: j }

  public func start(): i32
    Example.solve(2, 20, 1)
    i32 0
