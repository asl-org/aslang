import "base.asl"
# Match expression forms — exercises standalone match statement,
# integer-literal case patterns (case 0, case 1), variable binding
# patterns (case other, case n), and match-as-assignment
# (y = match x: ...). Both functions here are body-only; no calls
# from outside.
module App:
  func classify(x: i64): String
    match x:
      case 0:
        System.println("zero")
      case 1:
        System.println("one")
      case other:
        System.println("something else")

  func label(x: i64): String
    y = match x:
      case 0:
        String.from("zero")
      case n:
        String.from(n)
