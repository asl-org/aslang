module Status:
  generic Value

  struct Ok:
    Value value
  struct Err:
    S32 code
    String message

module Array:
  generic Item:
    fn byte_size(U64 items): U64
    fn read(Pointer ptr): Item
    fn write(Pointer ptr, Item item): Pointer

  struct:
    U64 size
    Pointer ptr

  fn init(U64 size): Array
    byte_size = Item.byte_size(size)
    ptr = System.allocate(byte_size)
    Array { ptr: ptr, size: size }

  fn get(Array arr, U64 index): Status[Item, Error]
    size = arr.size
    comparison = U64.compare(index, size)
    match comparison:
      case -1:
        offset = Item.byte_size(index)
        ptr = arr.ptr
        shifted_ptr = Pointer.shift(ptr, offset)
        value = Item.read(shifted_ptr)
        Status.Ok { value: value }
      else:
        error = Error { code: 1, message: "Index out of bound" }
        Status.Err { error: error }

  fn set(Array arr, U64 index, Item item): Status[Array, Error]
    size = arr.size
    comparison = U64.compare(index, size)
    match comparison:
      case -1:
        offset = Item.byte_size(index)
        ptr = arr.ptr
        shifted_ptr = Pointer.shift(ptr, offset)
        _ = Item.write(shifted_ptr, item)
        Status.Ok { arr: arr }
      else:
        error = Error { code: 1, message: "Index out of bound" }
        Status.Err { error: error }

fn print(Array[U8] arr, U64 index): U64
  size = arr.size
  comparison = U64.compare(index, size)
  match comparison:
    case -1:
      value = Array.get(arr, index)
      System.print(value)
      next_index = U64.add(index, 1)
      print(arr, next_index)
    else:
      arr.size

fn start(U8 seed): U8
  exit_success = U8 0

  arr = Array[U8] { size: 8 }
  arr = Array.set(arr, 0, 1)
  arr = Array.set(arr, 1, 2)

  print(arr)

  exit_success