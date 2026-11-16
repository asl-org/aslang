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
        "--vendor=std:./my-runtime.aslr"])
    check r.isOk
    let buildCmd = r.get.build.get
    check "std" in buildCmd.vendorRoots
    check "my-runtime.aslr" in buildCmd.vendorRoots["std"]

  test "additional vendor entries coexist with default `std`":
    let r = parseCliArgs(@["build", "entry.asl",
        "--vendor=runtime:./rt.aslr"])
    check r.isOk
    let buildCmd = r.get.build.get
    check "std" in buildCmd.vendorRoots
    check "runtime" in buildCmd.vendorRoots

  test "duplicate vendor name is rejected with both paths":
    let r = parseCliArgs(@["build", "entry.asl",
        "--vendor=std:./a.aslr",
        "--vendor=std:./b.aslr"])
    check r.isErr
    check "specified more than once" in r.error
    check "a.aslr" in r.error
    check "b.aslr" in r.error

  test "vendor value without `:` separator is rejected":
    let r = parseCliArgs(@["build", "entry.asl",
        "--vendor=nodelimiter"])
    check r.isErr
    check "name:path" in r.error or "<name>:<path>" in r.error

  test "vendor name starting with a digit is rejected":
    let r = parseCliArgs(@["build", "entry.asl",
        "--vendor=1bad:./x.aslr"])
    check r.isErr
    check "valid ASL identifier" in r.error

  test "vendor name with hyphen is rejected":
    # Hyphens aren't allowed in ASL identifiers; vendor names mirror
    # the same rule so `import "@<name>"` and `--vendor=<name>:...`
    # always agree on shape.
    let r = parseCliArgs(@["build", "entry.asl",
        "--vendor=my-vendor:./x.aslr"])
    check r.isErr
    check "valid ASL identifier" in r.error

  test "vendor name with empty path is rejected":
    let r = parseCliArgs(@["build", "entry.asl",
        "--vendor=std:"])
    check r.isErr
    check "empty path" in r.error

  test "vendor name with empty name is rejected":
    let r = parseCliArgs(@["build", "entry.asl",
        "--vendor=:./x.aslr"])
    check r.isErr
    check "empty vendor name" in r.error

  test "vendor path is resolved to an absolute path":
    let r = parseCliArgs(@["build", "entry.asl",
        "--vendor=rt:./rt.aslr"])
    check r.isOk
    let buildCmd = r.get.build.get
    check buildCmd.vendorRoots["rt"][0] == '/'

suite "cli — lsp command":

  test "lsp defaults indent width and the `std` vendor":
    let r = parseCliArgs(@["lsp"])
    check r.isOk
    check r.get.kind == ackLsp
    let lspCmd = r.get.lsp.get
    check lspCmd.indentWidth == 2
    check "std" in lspCmd.vendorRoots

  test "lsp accepts --vendor and --indent-width":
    let r = parseCliArgs(@["lsp", "--indent-width=4", "--vendor=rt:./rt.aslr"])
    check r.isOk
    let lspCmd = r.get.lsp.get
    check lspCmd.indentWidth == 4
    check "rt" in lspCmd.vendorRoots

suite "cli — build flags that need codegen":
  # `--debug` and `-o/--output` only make sense once there is code
  # generation, so `build` rejects them instead of silently ignoring them.

  # EXPECTED: `--debug` is accepted, and the build emits source-location
  # comments in the generated C.
  # TODO(codegen): there is no code generation yet, so `build` rejects the
  # flag. This test asserts that. Flip it when codegen lands.
  test "--debug is rejected as not supported yet":
    let r = parseCliArgs(@["build", "entry.asl", "--debug"])
    check r.isErr
    check "--debug" in r.error
    check "not supported" in r.error

  # EXPECTED: `-o/--output <file>` is accepted, and the build writes its
  # output binary to that path.
  # TODO(codegen): there is no code generation yet, so `build` rejects the
  # flag. This test asserts that. Flip it when codegen lands.
  test "-o and --output are rejected as not supported yet":
    for output in [@["-o", "out"], @["--output=out"]]:
      let r = parseCliArgs(@["build", "entry.asl"] & output)
      check r.isErr
      check "--output" in r.error
      check "not supported" in r.error
