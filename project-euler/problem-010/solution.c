#include <stdio.h>
#include <string.h>

int main(int argc, char const *argv[])
{
  int max = 2000000;
  int prime[max];
  long long int ans = 0;
  memset(prime, 0, sizeof(prime));
  for (int i = 2; i < max; i += 1)
  {
    if (!prime[i])
    {
      ans += i;
      for (int j = 2 * i; j < max; j += i)
      {
        prime[j] = 1;
      }
    }
  }
  printf("%lld\n", ans);
  return 0;
}

// 600851475143