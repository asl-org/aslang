
fn print(Array[U8] arr, U64 index): U64
  element = Array[U8].get(arr, index)
  match element:
    case Ok { value: value }:
      System.print(value)
      next_index = U64.add(index, 1)
      print(arr, next_index)
    else:
      arr.size

fn print(Array[U8] arr): U64
  print(arr, 0)

fn start(U8 seed): U8
  arr = Array[U8].init(8)
  size = arr.size
  System.print(size)
  Array[U8].set(arr, 0, 1)
  Array[U8].set(arr, 1, 2)
  print(arr)
  exit_success = U8 0