module App:
  func classify(x: i64): str
    match x:
      case 0:
        System.println("zero")
      case 1:
        System.println("one")
      case other:
        System.println("something else")

  func label(x: i64): str
    y = match x:
      case 0:
        Str.from("zero")
      case n:
        Str.from(n)
