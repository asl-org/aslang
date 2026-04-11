# NEGATIVE TEST — imports `X` and then also defines a local
# `module X`. Both share the same file-level namespace so should
# fail with "duplicate name 'X'" pointing at the local module.
import { X } from "./dep.asl"

module X:
  func a(y: i64): i64
    y
