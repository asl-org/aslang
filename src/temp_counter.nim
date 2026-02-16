var counter: int = 0

proc reset_temp_counter*() =
  counter = 0

proc next_temp*(): string =
  result = "__asl_" & $counter
  counter += 1
