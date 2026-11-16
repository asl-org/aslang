# NEGATIVE TEST — file imports itself. The parser's `newAslFile`
# constructor checks if any import's absolute path matches the
# file's own path and rejects it with "importing the source file in
# itself is disallowed".
import { App } from "./self_import.asl"

module App:
  func start(): u8
    u8 0

public module Driver:
  public func start(): i32
    i32 0
