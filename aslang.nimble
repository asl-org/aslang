# Package

version       = "0.1.0"
author        = "Shubham Singh"
description   = "A Software Language for Zero Maintenance Software"
license       = "MIT"
srcDir        = "src"
bin           = @["aslang"]


# Dependencies

requires "nim >= 2.2.2"
requires "results >= 0.5.0"

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
# switch("opt", "none")                # catch more issues
switch("opt", "speed")               # optimize for speed

# Dead code elimination (helps detect unused paths)
switch("deadCodeElim", "on")

# Disable footguns
switch("nilChecks", "on")
switch("panics", "off")

switch("experimental", "dotOperators")
