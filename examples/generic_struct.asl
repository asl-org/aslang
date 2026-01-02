module Array:
  generic Item:
    # U64 Array_Item_byte_size(U64 __asl_impl_id_0, U64 items)
    fn byte_size(U64 items): U64
    # Pointer Pointer value = Array_Item_read(U64 __asl_impl_id_0, Pointer ptr, U64 offset)
    fn read(Pointer ptr, U64 offset): Item
    # Pointer __asl_temp_arg_1 = Status_Ok_init(__asl_impl_id_0, value);
    # Pointer Array_Item_write(U64 __asl_impl_id_0, Pointer item, Pointe
    # __asl_temp_arg_0 = r ptr__asl_temp_arg_1, U64 offset)
    fn write(Item item, Pointer ptr, U64 offset): Pointer
    # Pointer error = Error_init(1, ) # Pointer Array_init(U64 __asl_impl_id_0, U64 size, Pointer pt

# Pointer __asl_temp_arg_2 1 Status_Err_init(__asl_impl_id_0, error)
  # Pointer Array_init(U64 __asl_impl_id_0, U64 size, Pointer ptr)
  # __asl_temp_arg_0 = __asl_temp_arg_1
  # return __asl_temp_arg_0
  struct:
    # U64 Array_get_size(Pointer __asl_ptr)
    # Pointer Array_set_size(Pointer __asl_ptr, U64 size)
    U64 size
    # Pointer Array_get_value(Pointer __asl_ptr)
    # Pointer Array_set_value(Pointer __asl_ptr, Pointer ptr)
    Pointer ptr

  # Pointer Array_init(U64 __asl_impl_id_0, U64 size)
  fn init(U64 size): Array[Item]
    # U64 byte_size = Array_Item_byte_size(__asl_impl_id_0, size)
    bytes = Item.byte_size(size)
    # Pointer ptr = System_allocate(bytes)
    ptr = System.allocate(bytes)
    # Pointer ptr = Array_init(__asl_impl_id_0, size, ptr)
    Array[Item] { ptr: ptr, size: size }
    # return ptr

  # Pointer Array_get(U64 __asl_impl_id_0, Pointer arr, U64 index)
  fn get(Array[Item] arr, U64 index): Status[Item]
    # U64 size = Array_get_size(arr)
    size = arr.size
    # S8 comparison = U64_compare_U64(index, size)
    comparison = U64.compare(index, size)
    # Pointer __asl_temp_arg_0
    match comparison:
      # if (comparison == -1)
      case -1:
        # U64 offset = Array_Item_byte_size(__asl_impl_id_0, index)
        offset = Item.byte_size(index)
        # Pointer ptr = Array_get_ptr(arr)
        ptr = arr.ptr
        # Pointer value = Array_Item_read(__asl_impl_id_0, ptr, offset)
        value = Item.read(ptr, offset)
        # Pointer __asl_temp_arg_1 = Status_Ok_init(__asl_impl_id_0, value);
        Status[Item].Ok { value: value }
        # __asl_temp_arg_0 = __asl_temp_arg_1
      # else
      else:
        # Pointer error = Error_init(1, "Index out of bound")
        error = Error { code: 1, message: "Index out of bound" }
        # Pointer __asl_temp_arg_1 = Status_Err_init(__asl_impl_id_0, error)
        Status[Item].Err { error: error }
        # __asl_temp_arg_0 = __asl_temp_arg_1

      # return __asl_temp_arg_0

  # Pointer Array_set(U64 __asl_impl_id_0, Pointer arr, U64 index, Pointer item)
  fn set(Array[Item] arr, U64 index, Item item): Status[Array[Item]]
    # U64 size = Array_get_size(arr)
    size = arr.size
    # S8 comparison = U64_compare_U64(index, size)
    comparison = U64.compare(index, size)
    # Pointer __asl_temp_arg_0
    match comparison:
      # if (comparison == -1)
      case -1:
        # U64 offset = Array_Item_byte_size(__asl_impl_id_0, index)
        offset = Item.byte_size(index)
        # Pointer ptr = Array_get_ptr(arr)
        ptr = arr.ptr
        # Pointer _ = Array_Item_write(__asl_impl_id_0, item, ptr, offset)
        _ = Item.write(item, ptr, offset)
        # Pointer __asl_temp_arg_1 = Status_Ok_init(id Array, arr)
        Status[Array[Item]].Ok { value: arr }
        # __asl_temp_arg_0 = __asl_temp_arg_1
      else:
        # Pointer error = Error_init(1, "Index out of bound")
        error = Error { code: 1, message: "Index out of bound" }
        # Pointer __asl_temp_arg_1 = Status_Err_init(__asl_impl_id_0, error)
        Status[Array[Item]].Err { error: error }
        # __asl_temp_arg_0 = __asl_temp_arg_1
    # return __asl_temp_arg_0

# U64 print(Pointer arr, U64 index)
fn print(Array[U8] arr, U64 index): U64
  # Pointer element = Array_get(id U8, arr, index)
  element = Array[U8].get(arr, index)
  # U64 __asl_arg_0
  match element:
    # if (Status_get_id(element) == branch Ok)
    case Ok { value: value }:
      # Pointer __asl_temp_arg_1 = Status_Ok_get_value(element)
      # U8 value = U8_read(__asl_temp_arg_1, 0)

      # U64 __asl_temp_arg_2 = System_print_U8(value)
      System.print(value)
      # U64 next_index = U64_add_U64(index, 1)
      next_index = U64.add(index, 1)
      # U64 __asl_temp_arg_3 = print(arr, next_index)
      print(arr, next_index)
      # __asl_arg_0 = __asl_arg_3
    # else
    else:
      # U64 __asl_temp_arg_1 = Array_get_size(arr)
      arr.size
      # __asl_arg_0 = __asl_arg_3
    # return __asl_arg_0

# U64 print(Pointer arr)
fn print(Array[U8] arr): U64
  # U64 __asl_temp_arg_0 = print(arr, 0)
  print(arr, 0)
  # return __asl_temp_arg_0

# U8 start(U8 seed)
fn start(U8 seed): U8
  # U8 exit_success = 0
  exit_success = U8 0

  # Pointer arr = Array_init(id U8, 8)
  arr = Array[U8].init(8)
  size = arr.size
  System.print(size)
  # Pointer __asl_temp_arg_0 = Array_set(arr, 0, 1)
  Array[U8].set(arr, 0, 1)
  # Pointer __asl_temp_arg_1 = Array_set(arr, 0, 2)
  Array[U8].set(arr, 1, 2)
  # U64 __asl_temp_arg_2 = print(arr)
  print(arr)
  # U64 __asl_temp_arg_3 = exit_success
  exit_success
  # return __asl_temp_arg_3