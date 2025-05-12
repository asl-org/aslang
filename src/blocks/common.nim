import results, strformat, strutils

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
