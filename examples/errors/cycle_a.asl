# NEGATIVE TEST — cycle_a imports cycle_b which imports cycle_a.
# `parse*`'s depth-first import walk detects the cycle (its `visiting`
# stack) and reports the full chain: "cyclic dependency detected:
# .../cycle_a.asl -> .../cycle_b.asl -> .../cycle_a.asl".
import { B } from "./cycle_b.asl"

module A:
  func start(): u8
    u8 0

public module Driver:
  public func start(): i32
    i32 0
