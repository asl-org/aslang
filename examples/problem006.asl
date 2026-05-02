import { u8, u64, Array, Status, Any, Error, Bitset, System } from "base.asl"
# Project Euler #6 style exercise — closed-form arithmetic. The
# simplest example that exercises only primitive literal
# initializers (u64 100) and primitive method calls without any
# match, data blocks, or recursion.
public module Solver:
  func start(): u8
    exit_success = u8 0
    n = u64 100

    a = u64.subtract(n, 1)
    b = u64.add(n, 1)

    c = u64.multiply(n, 3)
    d = u64.add(c, 2)

    e = u64.multiply(a, b)
    f = u64.multiply(e, d)
    g = u64.multiply(n, f)

    h = u64.quotient(g, 12)
    System.print(h)

    exit_success
