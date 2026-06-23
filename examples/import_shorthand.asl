# Exercises the import shorthand (`import "file.asl"`) alongside the
# explicit form. The shorthand brings every public defined type from
# base.asl into scope under its original name; the explicit form
# below adds an aliased binding for a single Solver from
# problem001.asl. Both forms coexist in one file.
import "base.asl"
import { Solver as Solution1 } from "./problem001.asl"

public module Caller:
  public func start(): u8
    # Names brought in by the shorthand — `u8`, `Status`, `Any`,
    # `Error`, `Array`, `Bitset` etc. — are all reachable without
    # any aliasing clause.
    _ = Solution1.start()
    u8 0
