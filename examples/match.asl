module App:
  func classify(x: i64): u64
    match x:
      case 0:
        System.println("zero")
      case 1:
        System.println("one")
      case other:
        System.println("something else")

  func label(x: i64): string
    y = match x:
      case 0:
        "zero"
      case n:
        string.from(n)

public module Driver:
  public func start(): i32
    i32 0