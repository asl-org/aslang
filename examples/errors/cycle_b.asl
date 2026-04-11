# Other half of the cycle_a.asl / cycle_b.asl cyclic-import pair.
# Neither file is valid on its own as an entry point — either one
# starts a BFS that reaches back to itself.
import { A } from "./cycle_a.asl"

module B:
  func start(): u8
    u8 0
