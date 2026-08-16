# Minimal "Hello, world" — exercises import-from aggregator file,
# public keyword on module and function, a generic with a single
# func def, and a call to System.println.

import { Sample } from "./sample.asl"

generic Key:
  func hash(key: Key): u64

public module App:
  public func start(): u8
    arr = Array[u32] { size: 100 }
    u8 0

public module Driver:
  public func start(): i32
    i32 0