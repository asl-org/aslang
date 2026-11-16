# NEGATIVE TEST — import path starts with `..`, escaping to a
# parent directory. `toAbsPath` (parser/imports.nim) rejects it ("escapes
# to parent directory"). ASL imports must be from adjacent files or
# subdirectories only.
# TODO(parser-errors): the parser's backtracking swallows that message,
# so `asl build` reports "expected 'module' but found 'import'" instead.
# The target doesn't exist either, so this fixture fails even without the
# check; the loader test in tests/test_loader.nim is what proves it works.
import { X } from "../outside.asl"

module App:
  func start(): u8
    u8 0

public module Driver:
  public func start(): i32
    i32 0
