#include <stdio.h>
#include <string.h>

int main(int argc, char const *argv[])
{
  int prime[1000001];
  int cnt = 0;
  int ans = 0;
  memset(prime, 0, sizeof(prime));
  for (int i = 2; i < 1000001; i += 1)
  {
    if (!prime[i])
    {
      cnt += 1;
      if (cnt == 10001)
      {
        ans = i;
      }
      for (int j = 2 * i; j < 1000001; j += i)
      {
        prime[j] = 1;
      }
    }
  }
  printf("%d\n", ans);
  return 0;
}

// 600851475143