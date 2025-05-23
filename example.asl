struct Array:
  fields:
    Pointer ptr
    U64 size

  fn create(U64 size) returns Array:
    ptr = System.allocate(size)
    Array { ptr: ptr, size: size }

  fn destroy(Array arr) returns U8:
    System.free(arr.ptr)

app Example:
  fn start(U8 seed) returns U8:
    exit_success = U8 0

    arr = Array.create(10)
    res = Array.destroy(arr)
    U8.print(res)

    exit_success