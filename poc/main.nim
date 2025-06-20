import results, sequtils, strutils, osproc, strformat

import tokenizer
import parser
import blocks
import resolver

proc generate(file: blocks.File, functions: seq[Function]): Result[
    string, string] =
  let impl_code = @[
    file.expanded.map_it(it.definition.c).join("\n"),
    file.expanded.map_it(it.c).join("\n\n"),
    functions.map_it(it.definition.c).join("\n"),
    functions.map_it(it.c).join("\n\n"),
  ].join("\n")

  let code = @[
    "#include \"runtime/asl.h\"",
    impl_code,
    "int main(int argc, char** argv) {",
    "return (int)start((U8)argc);",
    "}\n"
  ].join("\n")

  ok(code)

proc compile(input_file: string, output_file: string): Result[void, string] =
  let content = read_file(input_file)
  let tokens = ? tokenize(input_file, content)
  let lines = ? parse(tokens)
  let file = ? blockify(input_file, lines)
  let functions = ? resolve(file)
  let expanded_file = ? expand(file)
  let code = ? generate(expanded_file, functions)
  write_file(output_file, code)
  let exit_code = exec_cmd(fmt"gcc -O3 -o example {output_file}")
  if exit_code != 0: err("GCC Compilation failed.") else: ok()

when is_main_module:
  let maybe_compiled = compile("poc/sample.asl", "generated.c")
  if maybe_compiled.is_err:
    echo maybe_compiled.error
