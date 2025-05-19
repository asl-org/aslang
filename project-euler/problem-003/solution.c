#include <stdio.h>
#include <string.h>

/**
 * This simple implementation of prime calculation is actually a pretty great
 * example of how poor C compiler is in handling tail call recursive function
 * while caculating answer using recursive implementation if we compile this file
 * with no optimization the code ends up failing with segmentation fault.
 * But if you compile same code with `-O3` flag to enable optimization the code
 * will not only run properly but also it is blazingly fast.
 */

void remove_non_primes(int prime[], int j, int n, int i)
{
  if (j > n)
    return;

  prime[j] = 1;
  remove_non_primes(prime, j + i, n, i);
}

int solve_recur_impl(int prime[], int i, int n, int ans)
{
  if (i > n)
    return ans;

  if (prime[i])
    return solve_recur_impl(prime, i + 1, n, ans);

  remove_non_primes(prime, 2 * i, n, i);
  int new_ans = (600851475143 % i == 0) ? (ans > i ? ans : i) : ans;
  return solve_recur_impl(prime, i + 1, n, new_ans);
}

int solve_recur(int prime[], int n)
{
  return solve_recur_impl(prime, 2, n, 0);
}

int solve_iter(int prime[], int n)
{
  int ans = 0;

  for (int i = 2; i <= n; i += 1)
  {
    if (!prime[i])
    {
      for (int j = 2 * i; j <= n; j += i)
      {
        prime[j] = 1;
      }

      if (600851475143 % i == 0)
      {
        ans = ans > i ? ans : i;
      }
    }
  }
  return ans;
}

int main(int argc, char const *argv[])
{
  int n = 1000000;
  int prime[n + 1];
  memset(prime, 0, sizeof(prime));
  // printf("%d\n", solve_re cur(prime, n));
  printf("%d\n", solve_iter(prime, n));
  return 0;
}

// 600851475143