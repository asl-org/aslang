# NEGATIVE TEST — cycle_a imports cycle_b which imports cycle_a.
# The topological sort in parser.parse* detects the cycle via
# DFS path-tracking and reports the full dependency chain.
import { B } from "./cycle_b.asl"

module A:
  func start(): u8
    u8 0
