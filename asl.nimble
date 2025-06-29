# Package

version       = "0.1.0"
author        = "Shubham Singh"
description   = "A Software Language for Zero Maintenance Systems"
license       = "MIT"
srcDir        = "src"
installExt    = @["nim"]
bin           = @["asl"]


# Dependencies

requires "nim >= 2.2.2"
requires "results >= 0.5.0"
switch("experimental", "dotOperators")
switch("deadCodeElim", "on")
switch("opt", "speed")
switch("--threads", "on")
switch("--checks", "on")
