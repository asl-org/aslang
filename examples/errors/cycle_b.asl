# Other half of the cycle_a.asl / cycle_b.asl cyclic-import pair.
# Support file: test.sh doesn't build it on its own, so it has no
# entry module. Either file's import walk reaches back to itself.
import { A } from "./cycle_a.asl"

public module B:
  func start(): u8
    u8 0
