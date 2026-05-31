import {u8} from "base.asl"
# Aggregator file — exercises import aliasing ("as Solution1"),
# multiple import statements from different files, and cross-file
# module references (Solution1.start through Solution10.start).
# This is the file referenced by examples/hello.asl.
import { Solver as Solution1 } from "./problem001.asl"
import { Solver   as Solution2 } from "./problem002.asl"
import { Solver   as Solution3 } from "./problem003.asl"
import { Example  as Solution4 } from "./problem004.asl"
import { Example  as Solution5 } from "./problem005.asl"
import { Solver   as Solution6 } from "./problem006.asl"
import { Example  as Solution7 } from "./problem007.asl"
import { Solver   as Solution8 } from "./problem008.asl"
import { Solver   as Solution9 } from "./problem009.asl"
import { Solver   as Solution10 } from "./problem010.asl"


public module Sample:
  func start(): u8
    Solution1.start()
    Solution2.start()
    Solution3.start()
    Solution4.start()
    Solution5.start()
    Solution6.start()
    Solution7.start()
    Solution8.start()
    Solution9.start()
    Solution10.start()
    u8 0