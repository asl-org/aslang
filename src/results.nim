type
  Result*[T, E] = object
    case isOk*: bool
    of true:
      val*: T
    of false:
      err*: E

proc ok*[T, E](val: T): Result[T, E] =
  Result[T, E](isOk: true, val: val)

proc ok*[E](): Result[void, E] =
  Result[void, E](isOk: true)

proc err*[T, E](err: E): Result[T, E] =
  Result[T, E](isOk: false, err: err)

proc is_ok*[T, E](res: Result[T, E]): bool = res.isOk
proc is_err*[T, E](res: Result[T, E]): bool = not res.isOk
proc get*[T, E](res: Result[T, E]): T = res.val
proc error*[T, E](res: Result[T, E]): E = res.err
