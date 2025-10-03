module Status:
  struct Ok:
    U64 value
  struct Err:
    S64 code

  fn print(Status status): U64
    _ = match status:
      case Ok { value: value }:
        System.print_U64(value)
      case Err { code: code }:
        System.print_S64(code)

fn start(U8 seed): U8
  value = U64 0
  success = Status.Ok { value: value }
  Status.print(success)

  code = S64 -1
  failure = Status.Err { code: code }
  Status.print(failure)

  exit_success = U8 0