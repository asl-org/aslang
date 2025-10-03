module TestValue:
  struct:
    U64 value

  fn print(TestValue value): U64
    val = value.value
    System.print_S64(val)

module TestError:
  struct:
    S32 code

  fn code(TestError err): S32
    err.code

  fn print(TestError err): U64
    code = err.code
    System.print_S32(code)

module Status:
  generic Value:
    fn print(Value value): U64
  generic Error:
    fn code(Error err): S32
    fn print(Error err): U64

  struct Ok:
    Value value
  struct Err:
    Error error

  fn print(Status[Value, Error] status): U64
    a = match status:
      case Ok { value: value }:
        Value.print(value)
      case Err { error: error }:
        Error.print(error)

fn start(U8 seed): U8
  exit_success = U8 0

  success_code = U64 10
  test_value = TestValue { value: success_code }
  success = Status[TestValue, TestError].Ok { value: test_value }

  failure_code = S32 -12
  test_error = TestError { code: failure_code }
  failure = Status[TestValue, TestError].Err { error: test_error }

  exit_success