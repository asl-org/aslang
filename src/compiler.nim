import results

proc compile*(filename: string, output: string): Result[void, string] =
  echo filename
  echo output
  ok()
