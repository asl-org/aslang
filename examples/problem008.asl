# Project Euler #8 style exercise — exercises function overloading
# (three solve functions with different arity/types in the same
# module), long string literals spanning a single source line, and
# u8.subtract / u32.from primitive conversions.
public module Solver:
  func max(a: u32, b: u32): u32
    cmp = u32.compare(a, b)
    match cmp:
      case 1:
        a
      case _:
        b

  func solve(str: String, index: u32, count: u32, ans: u32): Status[u32]
    match u32.compare(count, 0):
      case 1:
        match String.get(str, index):
          case Ok { value: ascii }:
            match u8.subtract(ascii, 48):
              case Ok { value: digit }:
                digit_u32 = u32.from(digit)
                match u32.multiply(ans, digit_u32):
                  case Ok { value: next_ans }:
                    match u32.add(index, 1):
                      case Ok { value: next_index }:
                        match u32.subtract(count, 1):
                          case Ok { value: next_count }:
                            Solver.solve(str, next_index, next_count, next_ans)
                          case Err { error: err1 }:
                            Status[u32].Err { error: err1 }
                      case Err { error: err2 }:
                        Status[u32].Err { error: err2 }
                  case Err { error: err3 }:
                    Status[u32].Err { error: err3 }
              case Err { error: err4 }:
                Status[u32].Err { error: err4 }
          case Err { error: err5 }:
            Status[u32].Err { error: err5 }
      case _:
        Status[u32].Ok { value: ans }

  func solve(str: String, index: u32, ans: u32): Status[u32]
    match String.get(str, index):
      case Ok { value: ascii }:
        match Solver.solve(str, index, 13, 1):
          case Ok { value: result }:
            max_ans = u32.max(ans, result)
            match u32.add(index, 1):
              case Ok { value: next_index }:
                Solver.solve(str, next_index, max_ans)
              case Err { error: err2 }:
                Status[u32].Err { error: err2 }
          case Err { error: err1 }:
            Status[u32].Err { error: err1 }
      case _:
        Status[u32].Ok { value: ans }

  func solve(value: String, ans: u32): Status[u32]
    Solver.solve(value, 0, ans)

  public func start(): u8
    value = String "7316717653133062491922511967442657474235534919493496983520312774506326239578318016984801869478851843858615607891129494954595017379583319528532088055111254069874715852386305071569329096329522744304355766896648950445244523161731856403098711121722383113622298934233803081353362766142828064444866452387493035890729629049156044077239071381051585930796086670172427121883998797908792274921901699720888093776657273330010533678812202354218097512545405947522435258490771167055601360483958644670632441572215539753697817977846174064955149290862569321978468622482839722413756570560574902614079729686524145351004748216637048440319989000889524345065854122758866688116427171479924442928230863465674813919123162824586178664583591245665294765456828489128831426076900422421902267105562632111110937054421750694165896040807198403850962455444362981230987879927244284909188845801561660979191338754992005240636899125607176060588611646710940507754100225698315520005593572972571636269561882670428252483600823257530420752963450"
    match Solver.solve(value, 1):
      case Ok { value: _ }:
        u8 1
      case Err { error: _ }:
        u8 0