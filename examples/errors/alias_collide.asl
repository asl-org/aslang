# NEGATIVE TEST — imports X with alias Y, then also defines a
# local `module Y`. The collision is on the aliased visible name
# so should fail with "duplicate name 'Y'" pointing at the alias
# identifier in the import statement (column of the `Y` in `X as Y`).
import { X as Y } from "./dep.asl"

module Y:
  func a(y: i64): i64
    y
