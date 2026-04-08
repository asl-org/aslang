module User:
  struct:
    name: str
    age: u32

  func new(n: str, a: u32): User
    User.init(n, a)

module Plan:
  union:
    Free { usage: u32 }
    Pro { users: u32, credits: u32 }

  func describe(plan: Plan): str
    Plan.name(plan)
