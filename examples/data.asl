module User:
  struct:
    name: str
    age: u32

  func new(n: str, a: u32): User
    User { name: n, age: a }

module Plan:
  union:
    Free { usage: u32 }
    Pro { users: u32, credits: u32 }

  func describe(plan: Plan): str
    free = Plan.Free { usage: u32 100 }
    match plan:
      case Free { usage: usage }:
        Str.from(usage)
      case Pro { credits: credits, days: days }:
        Str.concat(Str.from(credits), Str.from(days))
