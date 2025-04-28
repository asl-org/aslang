#include <stdio.h>

int is_triplet(int a, int b, int c)
{
  return (a * a) + (b * b) == (c * c);
}

int main(int argc, char const *argv[])
{
  for (int a = 1; a < 1000; a++)
    for (int b = a + 1; b < 1000 - a; b++)
      if (is_triplet(a, b, 1000 - a - b))
      {
        printf("%d\n", a * b * (1000 - a - b));
      }
  return 0;
}
