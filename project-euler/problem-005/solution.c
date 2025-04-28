#include <stdio.h>

int gcd(int a, int b)
{
  return b == 0 ? a : gcd(b, a % b);
}

int lcm(int a, int b)
{
  return (a * b) / gcd(a, b);
}

int main(int argc, char const *argv[])
{
  int j = 1;
  for (int i = 2; i < 20; i += 1)
  {
    j = lcm(j, i);
  }
  printf("%d\n", j);
  return 0;
}
