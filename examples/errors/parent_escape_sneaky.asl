# NEGATIVE TEST — import path uses ./sub/../../ to escape the parent
# directory without starting with "..". The old check (startsWith(".."))
# would miss this. The fixed check normalizes the resolved absolute
# path and verifies it still falls within the importing file's directory.
# TODO(parser-errors): the parser's backtracking swallows that message,
# so `asl build` reports "expected 'module' but found 'import'" instead.
# The target doesn't exist either, so this fixture fails even without the
# check; the loader test in tests/test_loader.nim is what proves it works.
import { X } from "./sub/../../escape.asl"

module App:
  func start(): u8
    u8 0

public module Driver:
  public func start(): i32
    i32 0
