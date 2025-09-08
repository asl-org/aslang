module Array:
  generic Value:
    fn byte_size(U64 items): U64
    fn from_Pointer(Pointer ptr): Value
    fn write_Pointer(Pointer ptr, Value val): Pointer

  struct:
    U64 size
    Pointer ptr

  fn new(U64 size): Array[Value]
    bytes = U64.multiply(size, 8)
    ptr = System.allocate(bytes)
    arr = Array[Value] { ptr: ptr, size: size }

  fn set(Array[Value] arr, U64 index, Value val): Array[Value]
    ptr = arr.ptr
    offset = Value.byte_size(index)
    addr = Pointer.shift(ptr, offset)
    _updated = Value.write_Pointer(addr, val) # generic
    arr

  fn get(Array[Value] arr, U64 index): Value
    ptr = arr.ptr
    offset = Value.byte_size(index)
    addr = Pointer.shift(ptr, offset)
    ans = Value.from_Pointer(addr) # generic


fn start(U8 seed): U8
  exit_success = U8 0

  arr = Array[U64].new(8)
  size = arr.size

  System.print_U64(size)
  val1 = U64 1
  Array.set(arr, 0, val1)
  val2 = U64 2
  Array.set(arr, 1, val2)

  first = Array.get(arr, 0)
  System.print_U64(first)

  second = Array.get(arr, 1)
  System.print_U64(second)

  third = Array.get(arr, 2)
  System.print_U64(third)

  ninth = Array.get(arr, 8)
  System.print_U64(ninth)

  # Array.print(arr)

  exit_success