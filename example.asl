module Array:
  generic Value:
    fn byte_size(U64 items): U64
    fn from_Pointer(Pointer ptr): Value
    fn write_Pointer(Pointer ptr, Value val): Pointer
    fn print(Value value): U64

  struct:
    U64 size
    Pointer ptr

  fn new(U64 size): Array
    byte_size = Value.byte_size(size)
    ptr = System.allocate(byte_size)
    arr = Array { ptr: ptr, size: size }

  fn set(Array arr, U64 index, Value val): Array
    ptr = arr.ptr
    offset = Value.byte_size(index)
    addr = Pointer.shift(ptr, offset)
    _updated = Value.write_Pointer(addr, val) # generic
    arr

  fn get(Array arr, U64 index): Value
    ptr = arr.ptr
    offset = Value.byte_size(index)
    addr = Pointer.shift(ptr, offset)
    ans = Value.from_Pointer(addr) # generic

  fn print(Array arr): U64
    Array._print(arr, 0)

  fn _print(Array arr, U64 index): U64
    size = arr.size
    c = U64.compare(index, size)
    _ = match c:
      case -1:
        item = Array.get(arr, index)
        item_bytes = Value.print(item)
        next_index = U64.add(index, 1)
        rest_bytes = Array._print(arr, next_index)
        U64.add(item_bytes, rest_bytes)
      else:
        U64 0


fn start(U8 seed): U8
  exit_success = U8 0

  arr = Array.new(8)
  size = arr.size

  System.print_U64(size)
  Array.set(arr, 0, 1)
  Array.set(arr, 1, 2)

  first = Array.get(arr, 0)
  System.print_U64(first)

  second = Array.get(arr, 1)
  System.print_U64(second)

  third = Array.get(arr, 2)
  System.print_U64(third)

  ninth = Array.get(arr, 8)
  System.print_U64(ninth)

  Array.print(arr)

  exit_success