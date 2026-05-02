import { u8, u64, Array, Status, Any, Error, Bitset, System } from "base.asl"
# Project Euler #5 style exercise — gcd/lcm via Euclidean recursion.
# Exercises integer comparison with signed literal patterns
# (case -1), mutually-calling functions within a module, and
# tail-recursive loops.
public module Example:
  func gcd(a: u64, b: u64): u64
    op = u64.compare(b, 0)
    _ = match op:
      case 0:
        a
      case _:
        c = u64.remainder(a, b)
        Example.gcd(b, c)

  func lcm(a: u64, b: u64): u64
    c = u64.multiply(a, b)
    d = Example.gcd(a, b)
    u64.quotient(c, d)

  func solve(i: u64, n: u64, j: u64): u64
    op = u64.compare(i, n)
    _ = match op:
      case -1:
        next_i = u64.add(i, 1)
        next_j = Example.lcm(i, j)
        Example.solve(next_i, n, next_j)
      case _:
        j

  func start(): u8
    exit_success = u8 0
    ans = Example.solve(2, 20, 1)
    System.print(ans)
    exit_success
