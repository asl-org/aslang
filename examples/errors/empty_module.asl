# NEGATIVE TEST — module with no data block and no functions.
# Rejected by `newModule` with "module must have at least 1
# struct/union/function block", pointing at the `module Foo:` line.
module Foo:

public module Driver:
  public func start(): i32
    i32 0
