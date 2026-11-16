# NEGATIVE TEST — imports X with alias Y, then also defines a
# local `module Y`. The collision is on the aliased visible name, so
# it fails with "duplicate type declaration encountered" pointing at
# the local `module Y`, with "see previous declaration" pointing at the
# `Y` in `X as Y`.
import { X as Y } from "./dep.asl"

module Y:
  func a(y: i64): i64
    y

public module Driver:
  public func start(): i32
    i32 0
