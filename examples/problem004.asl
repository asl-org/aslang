import { u8, u64, Array, Status, Any, Error, Bitset, System } from "base.asl"
# Project Euler #4 style exercise — palindrome loop. Exercises
# match on signed integer literals (case -1, case 1), tail-recursive
# loops via function recursion, and primitive literal initializers
# with named types (u8 1, u8 0).
public module Example:
  func max(a: u64, b: u64): u64
    op = u64.compare(a, b)
    _a = match op:
      case 1:
        a
      case _:
        b

  func eq(a: u64, b: u64): u8
    op = u64.compare(a, b)
    _a = match op:
      case 0:
        u8 1
      case _:
        u8 0

  func is_palindrome_loop(a: u64, b: u64, c: u64): u8
    op = u64.compare(c, 0)
    _a = match op:
      case 1:
        b1 = u64.multiply(b, 10)
        b2 = u64.remainder(c, 10)
        b3 = u64.add(b1, b2)

        c1 = u64.quotient(c, 10)
        Example.is_palindrome_loop(a, b3, c1)
      case _:
        Example.eq(a, b)

  func is_palindrome(a: u64): u8
    Example.is_palindrome_loop(a, 0, a)

  func update_ans(a: u64, k: u64): u64
    op = Example.is_palindrome(a)
    _a = match op:
      case 1:
        Example.max(a, k)
      case _:
        k

  func loop_inner(i: u64, j: u64, k: u64, l: u64): u64
    op = u64.compare(j, l)
    _a = match op:
      case -1:
        a = u64.multiply(i, j)
        next_k = Example.update_ans(a, k)
        next_j = u64.add(j, 1)
        Example.loop_inner(i, next_j, next_k, l)
      case _:
        k

  func loop_outer(i: u64, j: u64, k: u64, l: u64): u64
    op = u64.compare(i, l)
    _a = match op:
      case -1:
        next_k = Example.loop_inner(i, j, k, l)
        next_i = u64.add(i, 1)
        Example.loop_outer(next_i, j, next_k, l)
      case _:
        k

  func start(): u8
    exit_success = u8 0
    ans = Example.loop_outer(100, 100, 0, 1000)
    System.print(ans)

    exit_success
