# Minimal "Hello, world" — exercises import-from aggregator file,
# @export decorators on module and function, a generic with a single
# func def, and a call to System.println.
import { Sample } from "./sample.asl"

generic Key:
  func hash(key: Key): u64

@export
module App:
  @export
  func start(sys: System): u8
    arr = Array[u32] { name: "test", allocator: sys.allocator }
    System.println("Hello, world!")
