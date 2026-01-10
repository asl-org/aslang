module TestValue:
  struct:
    U64 value

  fn print(TestValue value): U64
    val = value.value
    System.print(val)

fn start(U8 seed): U8
  exit_success = U8 0

  success_code = U64 10
  test_value = TestValue { value: success_code }
  success = Status[TestValue].Ok { value: test_value }
  TestValue.print(test_value)

  failure_code = S32 -12
  test_error = Error { code: failure_code, message: "Hello" }
  failure = Status[TestValue].Err { error: test_error }

  exit_success