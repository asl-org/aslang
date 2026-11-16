# NEGATIVE TEST — imports `X` and then also defines a local
# `module X`. Both share the same file-level namespace, so it fails
# with "duplicate type declaration encountered" pointing at the local
# module, with "see previous declaration" pointing at the imported `X`.
import { X } from "./dep.asl"

module X:
  func a(y: i64): i64
    y

public module Driver:
  public func start(): i32
    i32 0
