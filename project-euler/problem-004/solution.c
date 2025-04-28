#include <stdio.h>

int is_palindrome(int k)
{
  int l = 0;
  int m = k;
  while (m > 0)
  {
    l = (10 * l) + (m % 10);
    m = m / 10;
  }

  return l == k;
}

int main(int argc, char const *argv[])
{
  int k = 0;
  for (int i = 100; i < 1000; i += 1)
    for (int j = 100; j < 1000; j += 1)
      if (is_palindrome(i * j))
        k = k > (i * j) ? k : (i * j);

  printf("%d\n", k);
  return 0;
}
