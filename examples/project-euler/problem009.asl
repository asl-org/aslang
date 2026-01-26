fn is_triplet(U32 a, U32 b, U32 c): U32
  a_square = U32.multiply(a, a)
  b_square = U32.multiply(b, b)
  c_square = U32.multiply(c, c)
  left = U32.add(a_square, b_square)
  cmp = U32.compare(left, c_square)
  match cmp:
    case 0:
      d = U32.multiply(a, b)
      U32.multiply(c, d)
    case 1:
      U32 0

fn solve(U32 a, U32 b): U32
  total = U32.add(a, b)
  c = U32.subtract(1000, total)
  cmp = U32.compare(c, b)
  match cmp:
    case 1: # c > b
      result = is_triplet(a, b, c)
      match result:
        case 0:
          next_b = U32.add(b, 1)
          solve(a, next_b)
        else:
          d = U32.multiply(a, b)
          U32.multiply(c, d)
    else: # c <= b
      U32 0

fn solve(U32 a): U32
  # since a < b < c
  # for min sum; b = a + 1 and c = b + 1 = a + 2
  # min_sum = (a) + (a + 1) + (a + 2) = 3 * (a + 1)
  next_a = U32.add(a, 1)
  min_sum = U32.multiply(3, next_a)

  cmp = U32.compare(min_sum, 1000)
  match cmp:
    case 1:
      U32 0
    else:
      result = solve(a, next_a)
      match result:
        case 0:
          solve(next_a)
        else:
          result

fn start(U8 seed): U8
  ans = solve(1)
  System.print(ans)
  U8 0
