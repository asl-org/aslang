import { Solution as Solution1 } from "./problem001.asl"
import { Solution as Solution2 } from "./problem002.asl"
import { Solution as Solution3 } from "./problem003.asl"
import { Solution as Solution4 } from "./problem004.asl"
import { Solution as Solution5 } from "./problem005.asl"
import { Solution as Solution6 } from "./problem006.asl"
import { Solution as Solution7 } from "./problem007.asl"
import { Solution as Solution8 } from "./problem008.asl"
import { Solution as Solution9 } from "./problem009.asl"
import { Solution as Solution10 } from "./problem010.asl"


module Sample:
  func greet(): str
    Str.from("hello from sample")

  func start(sys: System): u8
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