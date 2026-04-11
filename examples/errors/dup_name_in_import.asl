# NEGATIVE TEST — same name `X` appears twice in the brace list
# of a single import statement. Should fail with "duplicate name
# 'X'" pointing at the second `X` inside `{ X, X }`.
import { X, X } from "./dep.asl"

module App:
  func start(): u8
    u8 0
