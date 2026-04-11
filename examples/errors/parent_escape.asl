# NEGATIVE TEST — import path starts with `..`, escaping to a
# parent directory. The parser's resolveImportPath rejects these
# before the BFS enqueues them. ASL imports must be from adjacent
# files or subdirectories only.
import { X } from "../outside.asl"

module App:
  func start(): u8
    u8 0
