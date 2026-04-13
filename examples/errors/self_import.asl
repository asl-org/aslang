# NEGATIVE TEST — file imports itself. The parser's newFile
# constructor checks if any import's absolute path matches the
# file's own path and rejects it.
import { App } from "./self_import.asl"

module App:
  func start(): u8
    u8 0
