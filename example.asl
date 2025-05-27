module Status:
  union:
    Ok { value: U8 }
    Err { code: U8 }

module Array:
  struct:
    Pointer ptr
    U64 size

  fn create(U64 size) returns Array:
    ptr = System.allocate(size)
    Array { ptr: ptr, size: size }

  fn destroy(Array arr) returns U8:
    System.free(arr.ptr)

  # unsafe
  fn get(Array arr, U64 index) returns Status:
    op = U64.compare(index, arr.size)
    match op:
      case -1:
        target = Pointer.shift(arr.ptr, index)
        value = Pointer.read_U8(target)
        Status.Ok { value: value }
      else:
        Status.Err { code: 1 }

  # unsafe
  fn set(Array arr, U64 index, U8 value) returns Array:
    target = Pointer.shift(arr.ptr, index)
    Pointer.write(target, value)
    arr

app Example:
  fn start(U8 seed) returns U8:
    exit_success = U8 0

    arr = Array.create(10)
    val = Array.get(arr, 0)
    # U8.print(val)

    # Array.set(arr, 0, 1)
    # val1 = Array.get(arr, 0)
    # U8.print(val1)

    Array.destroy(arr)
    exit_success