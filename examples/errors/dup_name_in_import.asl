# NEGATIVE TEST — same name `X` appears twice in the brace list
# of a single import statement. Rejected by `newImport`.
# TODO(parser-errors): the parser's backtracking swallows that message,
# so `asl build` reports "expected 'module' but found 'import'" at the
# import line instead.
import { X, X } from "./dep.asl"

module App:
  func start(): u8
    u8 0

public module Driver:
  public func start(): i32
    i32 0
