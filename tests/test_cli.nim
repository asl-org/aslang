## Tests for the CLI's `--vendor` flag validation and the build
## command's downstream `vendorRoots` propagation.

import unittest, results, tables, strutils

import cli

suite "cli — --vendor flag":

  test "no --vendor flag → default `std` is registered":
    let r = parseCliArgs(@["build", "entry.asl"])
    check r.isOk
    let cmd = r.get
    check cmd.kind == ackBuild
    let buildCmd = cmd.build.get
    check "std" in buildCmd.vendorRoots

  test "explicit --vendor=std:... overrides the default":
    let r = parseCliArgs(@["build", "entry.asl",
        "--vendor=std:./my-runtime.aslb"])
    check r.isOk
    let buildCmd = r.get.build.get
    check "std" in buildCmd.vendorRoots
    check "my-runtime.aslb" in buildCmd.vendorRoots["std"]

  test "additional vendor entries coexist with default `std`":
    let r = parseCliArgs(@["build", "entry.asl",
        "--vendor=runtime:./rt.aslb"])
    check r.isOk
    let buildCmd = r.get.build.get
    check "std" in buildCmd.vendorRoots
    check "runtime" in buildCmd.vendorRoots

  test "duplicate vendor name is rejected with both paths":
    let r = parseCliArgs(@["build", "entry.asl",
        "--vendor=std:./a.aslb",
        "--vendor=std:./b.aslb"])
    check r.isErr
    check "specified more than once" in r.error
    check "a.aslb" in r.error
    check "b.aslb" in r.error

  test "vendor value without `:` separator is rejected":
    let r = parseCliArgs(@["build", "entry.asl",
        "--vendor=nodelimiter"])
    check r.isErr
    check "name:path" in r.error or "<name>:<path>" in r.error

  test "vendor name starting with a digit is rejected":
    let r = parseCliArgs(@["build", "entry.asl",
        "--vendor=1bad:./x.aslb"])
    check r.isErr
    check "valid ASL identifier" in r.error

  test "vendor name with hyphen is rejected":
    # Hyphens aren't allowed in ASL identifiers; vendor names mirror
    # the same rule so `import "@<name>"` and `--vendor=<name>:...`
    # always agree on shape.
    let r = parseCliArgs(@["build", "entry.asl",
        "--vendor=my-vendor:./x.aslb"])
    check r.isErr
    check "valid ASL identifier" in r.error

  test "vendor name with empty path is rejected":
    let r = parseCliArgs(@["build", "entry.asl",
        "--vendor=std:"])
    check r.isErr
    check "empty path" in r.error

  test "vendor name with empty name is rejected":
    let r = parseCliArgs(@["build", "entry.asl",
        "--vendor=:./x.aslb"])
    check r.isErr
    check "empty vendor name" in r.error

  test "vendor path is resolved to an absolute path":
    let r = parseCliArgs(@["build", "entry.asl",
        "--vendor=rt:./rt.aslb"])
    check r.isOk
    let buildCmd = r.get.build.get
    check buildCmd.vendorRoots["rt"][0] == '/'
