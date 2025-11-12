module Error:
  struct:
    S32 code
    String message

module Status:
  generic Value

  struct Ok:
    Value value
  struct Err:
    Error error

module Array:
  generic Item:
    fn byte_size(U64 items): U64
    fn read(Pointer ptr, U64 offset): Item
    fn write(Item item, Pointer ptr, U64 offset): Pointer

  struct:
    U64 size
    Pointer ptr

  fn init(U64 size): Array[Item]
    bytes = Item.byte_size(size)
    ptr = System.allocate(bytes)
    Array[Item] { ptr: ptr, size: size }

  fn get(Array[Item] arr, U64 index): Status[Item]
    size = arr.size
    comparison = U64.compare(index, size)
    match comparison:
      case -1:
        offset = Item.byte_size(index)
        ptr = arr.ptr
        value = Item.read(ptr, offset)
        Status[Item].Ok { value: value }
      else:
        error = Error { code: 1, message: "Index out of bound" }
        Status[Item].Err { error: error }

  fn set(Array[Item] arr, U64 index, Item item): Status[Array[Item]]
    size = arr.size
    comparison = U64.compare(index, size)
    match comparison:
      case -1:
        offset = Item.byte_size(index)
        ptr = arr.ptr
        _ = Item.write(item, ptr, offset)
        Status[Array[Item]].Ok { value: arr }
      else:
        error = Error { code: 1, message: "Index out of bound" }
        Status[Array[Item]].Err { error: error }

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
  exit_success = U8 0

  arr = Array[U8].init(8)
  Array[U8].set(arr, 0, 1)
  Array[U8].set(arr, 1, 2)

  print(arr)

  exit_success