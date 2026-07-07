# Package

version       = "0.1.0"
author        = "Shubham Singh"
description   = "A software language for mission critical systems"
license       = "MIT"
srcDir        = "src"
bin           = @["asl"]

# Dependencies

requires "nim >= 2.2.0"
requires "results == 0.5.1"
requires "argparse == 4.0.2"

# Strict compile options
switch("warning", "UnusedImport")
switch("warning", "UnusedVar")
switch("warning", "UnusedParam")
switch("warning", "ProveInit")
switch("warning", "ShadowIdent")

# Safer semantics
switch("threads", "on")
switch("checks", "on")               # runtime checks
switch("boundChecks", "on")
switch("overflowChecks", "on")
switch("assertions", "on")
switch("stackTrace", "on")
switch("lineTrace", "on")
switch("opt", "none")                # catch more issues
# switch("opt", "speed")               # optimize for speed

# Dead code elimination (helps detect unused paths)
switch("deadCodeElim", "on")

# Disable footguns
switch("nilChecks", "on")
switch("panics", "off")

switch("experimental", "dotOperators")

# ============================================================
# Tasks
# ============================================================

task test, "Run the unit test suite":
  exec "nim c -r --hints:off --warning:UnusedImport:off --skipParentCfg --path:src --path:src/parser --path:src/resolver --path:src/analyzer tests/all.nim"
