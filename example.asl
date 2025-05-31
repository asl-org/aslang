module ValueStatus:
  union:
    Ok { value: U8 }
    Err { code: U8 }

module ArrayStatus:
  union:
    Ok { arr: Array }
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
  fn get(Array arr, U64 index) returns ValueStatus:
    op = U64.compare(index, arr.size)
    match op:
      case -1:
        target = Pointer.shift(arr.ptr, index)
        value = U8.from(target)
        ValueStatus.Ok { value: value }
      else:
        ValueStatus.Err { code: 1 }

  # unsafe
  fn set(Array arr, U64 index, U8 value) returns ArrayStatus:
    op = U64.compare(index, arr.size)
    match op:
      case -1:
        target = Pointer.shift(arr.ptr, index)
        Pointer.write(target, value)
        ArrayStatus.Ok { arr: arr }
      else:
        ArrayStatus.Err { code: 1 }

app Example:
  fn start(U8 seed) returns U8:
    exit_success = U8 0
    exit_failure = U8 1

    arr = Array.create(10)
    val0 = Array.get(arr, 0)

    Array.set(arr, 0, 1)
    val1 = Array.get(arr, 0)

    match val1:
      case ValueStatus.Ok { value: value }:
        System.print(value)
        Array.destroy(arr)
        exit_success
      else:
        Array.destroy(arr)
        exit_failure