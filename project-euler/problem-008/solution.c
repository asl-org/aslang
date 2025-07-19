#include <stdio.h>
#include <string.h>

long long int solve_recur_inner(const char *str, int window, int i, int j, long long int k)
{
  if (j == window)
  {
    return k;
  }

  long long int next_k = k * (str[i + j] - '0');
  return solve_recur_inner(str, window, i, j + 1, next_k);
}

long long int solve_recur_outer(const char *str, int window, int length, int i, long long int ans)
{
  if (i + window == length)
  {
    return ans;
  }
  long long int sub_ans = solve_recur_inner(str, window, i, /*j=*/0, /*k=*/1);
  long long int next_ans = ans > sub_ans ? ans : sub_ans;
  return solve_recur_outer(str, window, length, i + 1, next_ans);
}

long long int solve_recur(const char *str, int window)
{
  int length = strlen(str);
  return solve_recur_outer(str, window, length, /*i=*/0, /*ans=*/0);
}

long long int solve_iter(const char *str, int window)
{
  long long int ans = 0;
  for (int i = 0; i < strlen(str) - window; i++)
  {
    long long int k = 1;
    for (int j = 0; j < window; j++)
    {
      k = k * (str[i + j] - '0');
    }
    ans = ans > k ? ans : k;
  }
  return ans;
}

int main(int argc, char const *argv[])
{
  long long int ans = 0;
  const char *str = "7316717653133062491922511967442657474235534919493496983520312774506326239578318016984801869478851843858615607891129494954595017379583319528532088055111254069874715852386305071569329096329522744304355766896648950445244523161731856403098711121722383113622298934233803081353362766142828064444866452387493035890729629049156044077239071381051585930796086670172427121883998797908792274921901699720888093776657273330010533678812202354218097512545405947522435258490771167055601360483958644670632441572215539753697817977846174064955149290862569321978468622482839722413756570560574902614079729686524145351004748216637048440319989000889524345065854122758866688116427171479924442928230863465674813919123162824586178664583591245665294765456828489128831426076900422421902267105562632111110937054421750694165896040807198403850962455444362981230987879927244284909188845801561660979191338754992005240636899125607176060588611646710940507754100225698315520005593572972571636269561882670428252483600823257530420752963450";
  // printf("%lld\n", solve_iter(str, 13));
  printf("%lld\n", solve_recur(str, 13));
  return 0;
}
