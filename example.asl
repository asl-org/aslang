app Example:

  fn start(U8 seed) returns U8:
    exit_success = U8 0
    exit_failure = U8 1

    ptr = System.allocate(64)
    Pointer.print(ptr)

    Pointer.write_U8(ptr, 255)
    val = Pointer.read_U8(ptr)
    U8.print(val)

    ptr1 = Pointer.shift(ptr, 1)
    Pointer.print(ptr1)
    Pointer.write_U8(ptr1, 255)
    val1 = Pointer.read_U8(ptr1)
    U8.print(val1)

    # ptr6 = Pointer.write_U64(ptr5, 4)
    val2 = Pointer.read_U64(ptr)
    U64.print(val2)

    System.free(ptr)