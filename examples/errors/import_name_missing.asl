# NEGATIVE TEST — imports `Ghost` from dep.asl, but dep.asl only
# defines `module X`. The resolver looks up each imported name in
# the target file's IndexedFile and fails if it's neither a
# module nor a generic there.
import { Ghost } from "./dep.asl"

module App:
  func start(): u8
    u8 0
