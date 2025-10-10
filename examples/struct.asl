module User:
  struct:
    U64 id
    U64 age

  fn print(User user): U64
    user_id = user.id
    System.print(user_id)

    user_age = user.age
    System.print(user_age)

fn start(U8 seed): U8
  id = U64 1
  age = U64 25

  user = User { id: id, age: age }
  User.print(user)

  U8 0
