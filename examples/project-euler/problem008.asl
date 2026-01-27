module S8:
  extern S8_byte_size:
    fn byte_size(U64 items): U64

  extern S8_read:
    fn read(Pointer ptr, U64 offset): S8

  extern S8_write:
    fn write(S8 value, Pointer ptr, U64 offset): Pointer

module S16:
  extern S16_byte_size:
    fn byte_size(U64 items): U64

  extern S16_read:
    fn read(Pointer ptr, U64 offset): S16

  extern S16_write:
    fn write(S16 value, Pointer ptr, U64 offset): Pointer

module S32:
  extern S32_byte_size:
    fn byte_size(U64 items): U64

  extern S32_read:
    fn read(Pointer ptr, U64 offset): S32

  extern S32_write:
    fn write(S32 value, Pointer ptr, U64 offset): Pointer

module S64:
  extern S64_byte_size:
    fn byte_size(U64 items): U64

  extern S64_read:
    fn read(Pointer ptr, U64 offset): S64

  extern S64_write:
    fn write(S64 value, Pointer ptr, U64 offset): Pointer

  extern S64_add_S64:
    fn add(S64 a, S64 b): S64

  extern S64_subtract_S64:
    fn subtract(S64 a, S64 b): S64

  extern S64_multiply_S64:
    fn multiply(S64 a, S64 b): S64

  extern S64_remainder_S64:
    fn remainder(S64 a, S64 b): S64

  extern S64_quotient_S64:
    fn quotient(S64 a, S64 b): S64

  extern S64_compare_S64:
    fn compare(S64 a, S64 b): S8

  extern S64_from_U8:
    fn from(U8 value): S64

  extern S64_from_U64:
    fn from(U64 value): S64

module U8:
  extern U8_byte_size:
    fn byte_size(U64 items): U64

  extern U8_read:
    fn read(Pointer ptr, U64 offset): U8

  extern U8_write:
    fn write(U8 value, Pointer ptr, U64 offset): Pointer

  extern U8_lshift_U8:
    fn lshift(U8 value, U64 offset): U8

  extern U8_rshift_U8:
    fn rshift(U8 value, U64 offset): U8

  extern U8_and_U8:
    fn and(U8 a, U8 b): U8

  extern U8_or_U8:
    fn or(U8 a, U8 b): U8

  extern U8_not:
    fn not(U8 a): U8

  extern U8_from_U64:
    fn from(U64 value): U8

  extern U8_subtract_U8:
    fn subtract(U8 a, U8 b): U8

module U16:
  extern U16_byte_size:
    fn byte_size(U64 items): U64

  extern U16_read:
    fn read(Pointer ptr, U64 offset): U16

  extern U16_write:
    fn write(U16 value, Pointer ptr, U64 offset): Pointer

module U32:
  extern U32_byte_size:
    fn byte_size(U64 items): U64

  extern U32_read:
    fn read(Pointer ptr, U64 offset): U32

  extern U32_write:
    fn write(U32 value, Pointer ptr, U64 offset): Pointer

  extern U32_add_U32:
    fn add(U32 a, U32 b): U32

  extern U32_subtract_U32:
    fn subtract(U32 a, U32 b): U32

  extern U32_multiply_U32:
    fn multiply(U32 a, U32 b): U32

  extern U32_compare_U32:
    fn compare(U32 a, U32 b): S8

module U64:
  extern U64_byte_size:
    fn byte_size(U64 items): U64

  extern U64_read:
    fn read(Pointer ptr, U64 offset): U64

  extern U64_write:
    fn write(U64 value, Pointer ptr, U64 offset): Pointer

  extern U64_add_U64:
    fn add(U64 a, U64 b): U64

  extern U64_subtract_U64:
    fn subtract(U64 a, U64 b): U64

  extern U64_multiply_U64:
    fn multiply(U64 a, U64 b): U64

  extern U64_quotient_U64:
    fn quotient(U64 a, U64 b): U64

  extern U64_remainder_U64:
    fn remainder(U64 a, U64 b): U64

  extern U64_compare_U64:
    fn compare(U64 a, U64 b): S8

  extern U8_lshift_U8:
    fn lshift(U8 value, U64 offset): U8

  extern U64_rshift_U64:
    fn rshift(U64 value, U64 offset): U64

  extern U64_and_U64:
    fn and(U64 a, U64 b): U64

  extern U64_or_U64:
    fn or(U64 a, U64 b): U64

  extern U64_not:
    fn not(U64 a): U64

  extern U64_from_U8:
    fn from(U8 value): U64

module F32:
  extern F32_byte_size:
    fn byte_size(U64 items): U64

  extern F32_read:
    fn read(Pointer ptr, U64 offset): F32

  extern F32_write:
    fn write(F32 value, Pointer ptr, U64 offset): Pointer

module F64:
  extern F64_byte_size:
    fn byte_size(U64 items): U64

  extern F64_read:
    fn read(Pointer ptr, U64 offset): F64

  extern F64_write:
    fn write(F64 value, Pointer ptr, U64 offset): Pointer

module String:
  extern String_byte_size:
    fn byte_size(U64 items): U64

  extern String_read:
    fn read(Pointer ptr, U64 offset): String

  extern String_write:
    fn write(String value, Pointer ptr, U64 offset): Pointer

  extern String_get:
    fn get(String value, U64 index): Status[U8]

module Pointer:
  extern Pointer_byte_size:
    fn byte_size(U64 items): U64

  extern Pointer_read:
    fn read(Pointer ptr, U64 offset): Pointer

  extern Pointer_write:
    fn write(Pointer value, Pointer ptr, U64 offset): Pointer

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
  generic Item
  struct:
    U64 size

  extern Array_init:
    fn init(U64 size): Array[Item]

  extern Array_set:
    fn set(Array[Item] arr, U64 index, Item value): Status[Array[Item]]

  extern Array_get:
    fn get(Array[Item] arr, U64 index): Status[Item]

module System:
  extern System_allocate:
    fn allocate(U64 bytes): Pointer

  extern System_free:
    fn free(Pointer ptr): U64

  extern System_box_U8:
    fn box(U8 value): Pointer

  extern System_box_U64:
    fn box(U64 value): Pointer

  extern System_box_S32:
    fn box(S32 value): Pointer

  extern System_box_S64:
    fn box(S64 value): Pointer

  extern System_box_Pointer:
    fn box(Pointer value): Pointer

  extern System_print_U8:
    fn print(U8 value): U64

  extern System_print_U16:
    fn print(U16 value): U64

  extern System_print_U32:
    fn print(U32 value): U64

  extern System_print_U64:
    fn print(U64 value): U64

  extern System_print_S8:
    fn print(S8 value): U64

  extern System_print_S16:
    fn print(S16 value): U64

  extern System_print_S32:
    fn print(S32 value): U64

  extern System_print_S64:
    fn print(S64 value): U64

  extern System_print_F32:
    fn print(F32 value): U64

  extern System_print_F64:
    fn print(F64 value): U64

  extern System_print_String:
    fn print(String value): U64

fn max(U64 a, U64 b): U64
  cmp = U64.compare(a, b)
  match cmp:
    case 1:
      a
    else:
      b

fn solve(String str, U64 index, U64 count, U64 ans): U64
  cmp = U64.compare(count, 0)
  match cmp:
    case 1:
      status = String.get(str, index)
      match status:
        case Ok { value: ascii }:
          digit = U8.subtract(ascii, 48)
          digit_u64 = U64.from(digit)
          next_ans = U64.multiply(ans, digit_u64)
          next_index = U64.add(index, 1)
          next_count = U64.subtract(count, 1)
          solve(str, next_index, next_count, next_ans)
        else:
          U64 1
    else:
      ans

fn solve(String str, U64 index, U64 ans): U64
  status = String.get(str, index)
  match status:
    case Ok { value: ascii }:
      result = solve(str, index, 13, 1)
      max_ans = max(ans, result)
      next_index = U64.add(index, 1)
      solve(str, next_index, max_ans)
    case Err { error: error }:
      ans

fn solve(String value, U64 ans): U64
  solve(value, 0, ans)

fn start(U8 seed): U8
  value = String "7316717653133062491922511967442657474235534919493496983520312774506326239578318016984801869478851843858615607891129494954595017379583319528532088055111254069874715852386305071569329096329522744304355766896648950445244523161731856403098711121722383113622298934233803081353362766142828064444866452387493035890729629049156044077239071381051585930796086670172427121883998797908792274921901699720888093776657273330010533678812202354218097512545405947522435258490771167055601360483958644670632441572215539753697817977846174064955149290862569321978468622482839722413756570560574902614079729686524145351004748216637048440319989000889524345065854122758866688116427171479924442928230863465674813919123162824586178664583591245665294765456828489128831426076900422421902267105562632111110937054421750694165896040807198403850962455444362981230987879927244284909188845801561660979191338754992005240636899125607176060588611646710940507754100225698315520005593572972571636269561882670428252483600823257530420752963450"
  ans = solve(value, 1)
  System.print(ans)

  U8 0