#include <stdio.h>

int solve_recur(int a, int b, int c, int d)
{
  if (a > c)
  {
    return d;
  }
  int e = a & 1 ? d : d + a;
  return solve_recur(b, a + b, c, e);
}

int solve_iter(int a, int b, int c, int d)
{
  while (a <= c)
  {
    if ((a & 1) == 0)
    {
      d += a;
    }
    int e = a + b;
    a = b;
    b = e;
  }
  return d;
}

int main(int argc, char const *argv[])
{
  int a = 1;
  int b = 2;
  int c = 4000000;
  int d = 0;
  printf("%d\n", solve_iter(a, b, c, d));
  // printf("%d\n", solve_recur(a, b, c, d));
  return 0;
}