import results, options, strformat, typetraits
import strutils, parseutils
import sets, tables

const TAB_SIZE = 2

proc validate_prefix*(spaces, level: int): Result[void, string] =
  let prefix = level * TAB_SIZE
  if spaces != prefix:
    return err(fmt"statement must be prefixed with {prefix} spaces but found {spaces}")
  return ok()

proc prefix*(spaces: int): string =
  " ".repeat(spaces)

proc child_prefix*(spaces: int): string =
  " ".repeat(spaces + TAB_SIZE)

type Stack*[T] = ref object of RootObj
  data: seq[T]
  limit: int = 1024

proc len*(stack: Stack): int = stack.data.len
proc empty*(stack: Stack): bool = stack.len == 0

# TODO: May error in case of stack overflow
proc push*[T](stack: Stack, asl_block: T): Result[void, string] =
  if stack.len == stack.limit:
    return err(fmt"stack overflow err")

  stack.data.add(asl_block)
  ok()

proc peek*[T](stack: Stack[T]): Result[T, string] =
  if stack.empty(): return err(fmt"Block stack is empty")
  let value = stack.data[^1]
  ok(value)

proc pop*[T](stack: Stack[T]): Result[T, string] =
  let value = ? stack.peek()
  stack.data.set_len(stack.data.len - 1)
  return ok(value)

proc new_stack*[T](data: seq[T]): Result[Stack[T], string] =
  var stack = Stack[T]()
  for row in data:
    ? stack.push(row)
  return ok(stack)

proc safe_parse*[T](input: string): Result[T, string] =
  when T is SomeSignedInt:
    var temp: BiggestInt
    let code = parseBiggestInt(input, temp)
    if code == 0 or code != input.len:
      return err("Failed to parse signed int from: " & input)
    if temp < T.low.BiggestInt or temp > T.high.BiggestInt:
      return err("Overflow: Value out of range for type " & $T)
    ok(T(temp))
  elif T is SomeUnsignedInt:
    var temp: BiggestUInt
    let code = parseBiggestUInt(input, temp)
    if code == 0 or code != input.len:
      return err("Failed to parse unsigned int from: " & input)
    if temp < T.low.BiggestUInt or temp > T.high.BiggestUInt:
      return err("Overflow: Value out of range for type " & $T)
    ok(T(temp))
  elif T is SomeFloat:
    var temp: BiggestFloat
    let code = parseBiggestFloat(input, temp)
    if code == 0 or code != input.len:
      return err("Failed to parse float from: " & input)
    let casted = T(temp)
    if BiggestFloat(casted) != temp:
      return err("Precision loss when converting to " & $T)
    ok(casted)
  else:
    err("safeParse only supports signed/unsigned integers and floating-point types")
