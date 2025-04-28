#include <stdio.h>

int main(int argc, char const *argv[])
{
  int a = 1;
  int b = 2;
  int c = 4000000;
  int d = 0;
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
  printf("%d\n", d);
  return 0;
}