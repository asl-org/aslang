# Project Euler #4 style exercise — palindrome loop. Exercises
# match on signed integer literals (case -1, case 1), tail-recursive
# loops via function recursion, and primitive literal initializers
# with named types (u8 1, u8 0).
public module Example:
  func is_palindrome_loop(original: u64, acc: u64, remaining: u64): Status[u8]
    match u64.compare(remaining, 0):
      case 1:
        match u64.multiply(acc, 10):
          case Ok { value: num_10x }:
            match u64.remainder(remaining, 10):
              case Ok { value: unit_digit }:
                match u64.add(num_10x, unit_digit):
                  case Ok { value: new_acc }:
                    match u64.quotient(remaining, 10):
                      case Ok { value: dividend }:
                        Example.is_palindrome_loop(original, new_acc, dividend)
                      case Err { error: err4 }:
                        Status[u8].Err { error: err4 }
                  case Err { error: err2 }:
                    Status[u8].Err { error: err2 }
              case Err { error: err3 }:
                Status[u8].Err { error: err3 }
          case Err { error: err1 }:
            Status[u8].Err { error: err1 }
      case _:
        match u64.compare(original, acc):
          case 0:
            Status.Ok { value: u8 1 }
          case _:
            Status.Ok { value: u8 0 }

  func is_palindrome(num: u64): Status[u8]
    Example.is_palindrome_loop(num, 0, num)

  func update_ans(value: u64, ans: u64): Status[u64]
    match Example.is_palindrome(value):
      case Ok { value: comparison }:
        new_ans = match comparison:
          case 1:
            u64.max(value, ans)
          case _:
            ans
        Status[u64].Ok { value: new_ans }
      case Err { error: err1 }:
        Status[u64].Err { error: err1 }

  func loop_inner(num: u64, j: u64, k: u64, l: u64): u64
    match u64.compare(j, l):
      case -1:
        match u64.multiply(num, j):
          case Ok { value: a }:
            match u64.add(j, 1):
              case Ok { value: next_j }:
                match Example.update_ans(a, k):
                  case Ok { value: next_k }:
                    Example.loop_inner(num, next_j, next_k, l)
                  case _:
                    k
              case _:
                k
          case _:
            k
      case _:
        k

  func loop_outer(num: u64, j: u64, k: u64, limit: u64): u64
    match u64.compare(num, limit):
      case -1:
        next_k = Example.loop_inner(num, j, k, limit)
        match u64.add(num, 1):
          case Ok { value: next_num }:
            Example.loop_outer(next_num, j, next_k, limit)
          case _:
            k
      case _:
        k

  public func start(): i32
    Example.loop_outer(100, 100, 0, 1000)
    i32 0
