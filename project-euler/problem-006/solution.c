#include <stdio.h>

int docas(int n)
{
  return (n - 1) * n * (n + 1) * (3 * n + 2) / 12;
}

int main(int argc, char const *argv[])
{
  int n = 100;
  printf("%d\n", docas(n));
  return 0;
}
