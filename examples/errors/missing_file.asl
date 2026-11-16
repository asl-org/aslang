# NEGATIVE TEST — imports a file that does not exist on disk.
# The parser's readFileSafe checks fileExists first and returns
# a clean "file not found" error (previously crashed with an
# unhandled OSError from getFileSize).
import { Ghost } from "./does_not_exist.asl"

module App:
  func start(): u8
    u8 0

public module Driver:
  public func start(): i32
    i32 0
