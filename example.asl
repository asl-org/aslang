module Status:
  union:
    Ok:
      U64 value
    Err:
      S64 error

  fn print(Status status): U64
    a = match status:
      case Ok { value: value }:
        System.print_U64(value)
      case Err { error: error }:
        System.print_S64(error)

fn start(U8 seed): U8
  exit_success = U8 0

  success = Status.Ok { value: exit_success }
  Status.print(success)

  failure_code = S64 -1
  failure = Status.Err { error: failure_code }
  Status.print(failure)

  exit_success