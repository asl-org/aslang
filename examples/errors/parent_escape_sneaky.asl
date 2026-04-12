# NEGATIVE TEST — import path uses ./sub/../../ to escape the parent
# directory without starting with "..". The old check (startsWith(".."))
# would miss this. The fixed check normalizes the resolved absolute
# path and verifies it still falls within the importing file's directory.
import { X } from "./sub/../../escape.asl"

module App:
  func start(): u8
    u8 0
