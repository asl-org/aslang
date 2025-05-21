#include <stdio.h>
#include <string.h>

int *remove_non_primes(int primes[], int max_primes, int i, int j)
{
  if (j >= max_primes)
    return primes;
  primes[j] = 1;
  return remove_non_primes(primes, max_primes, i, j + i);
}

int solve_recur(int primes[], int max_primes, int i, int c)
{
  if (i >= max_primes)
    return 0;

  if (!primes[i])
  {
    if (c == 10000)
      return i;
    c += 1;
    primes = remove_non_primes(primes, max_primes, i, 2 * i);
  }
  return solve_recur(primes, max_primes, i + 1, c);
}

int solve_iter(int primes[])
{
  int cnt = 0;
  int i;
  for (i = 2; i < 1000001; i += 1)
  {
    if (!primes[i])
    {
      if (cnt == 10000)
        return i;

      cnt += 1;
      for (int j = 2 * i; j < 1000001; j += i)
      {
        primes[j] = 1;
      }
    }
  }
  return 0;
}

int main(int argc, char const *argv[])
{
  int prime[1000001];
  int cnt = 0;
  int ans = 0;
  memset(prime, 0, sizeof(prime));
  // printf("%d\n", solve_iter(prime));
  printf("%d\n", solve_recur(prime, 1000001, 2, 0));
  return 0;
}

// 600851475143