#include <stdio.h>

int sum(int x)
{
  return (x * (x + 1)) >> 1;
}

int count(int n, int x)
{
  return x * sum(n / x);
}

int main(int argc, char const *argv[])
{
  int n = 999; // below 100
  int a = count(n, 3);
  int b = count(n, 5);
  int c = count(n, 15);
  printf("%d\n", a + b - c);
  return 0;
}
