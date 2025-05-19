app Example:
  fn gcd(U64 a, U64 b) returns U64:
    op = U64.compare(b, 0)
    match op:
      case 0:
        a
      else:
        c = U64.remainder(a, b)
        MODULE.gcd(b, c)

  fn lcm(U64 a, U64 b) returns U64:
    c = U64.multiply(a, b)
    d = MODULE.gcd(a, b)
    U64.quotient(c, d)

  fn solve(U64 i, U64 n, U64 j) returns U64:
    op = U64.compare(i, n)
    match op:
      case -1:
        next_i = U64.add(i, 1)
        next_j = MODULE.lcm(i, j)
        MODULE.solve(next_i, n, next_j)
      else:
        j

  fn start(U8 seed) returns U8:
    exit_success = U8 0
    ans = MODULE.solve(2, 20, 1)
    U64.print(ans)
    exit_success

# #include <stdio.h>

# int gcd(int a, int b)
# {
#   return b == 0 ? a : gcd(b, a % b);
# }

# int lcm(int a, int b)
# {
#   return (a * b) / gcd(a, b);
# }

# int main(int argc, char const *argv[])
# {
#   int j = 1;
#   for (int i = 2; i < 20; i += 1)
#   {
#     j = lcm(j, i);
#   }
#   printf("%d\n", j);
#   return 0;
# }
