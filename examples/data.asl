
# Data blocks — one file with two modules, one backed by a struct
# data block (User { name, age }) and the other by a union data
# block (Plan with Free / Pro variants each carrying named fields).
# Also exercises struct initializer (User { name: n, age: a }),
# union initializer (Plan.Free { usage: u32 100 }), and variant
# patterns with field bindings inside a match expression.
module User:
  struct:
    name: string
    age: u32

  func new(n: string, a: u32): User
    User { name: n, age: a }

module Plan:
  union:
    Free { usage: u32 }
    Pro { users: u32, credits: u32 }

  func describe(plan: Plan): string
    free = Plan.Free { usage: u32 100 }
    match plan:
      case Free { usage: usage }:
        string.from(usage)
      case Pro { credits: credits, users: users }:
        string.concat(string.from(credits), string.from(users))

public module Driver:
  public func start(): i32
    i32 0