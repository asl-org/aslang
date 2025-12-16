import strutils, results

import resolver

proc generate*(file: ResolvedFile): Result[string, string] =
  let c_file = @[
    "#include \"runtime.h\"\n",
    file.c,
    "\n",
    "int main(int argc, char** argv) {",
    "return start(argc);",
    "}"
  ].join("\n")
  return ok(c_file)
