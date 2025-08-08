import sequtils, strutils

import union, function

type ResolvedFile* = ref object of RootObj
  user_modules: seq[ResolvedUserModule]
  functions: seq[ResolvedFunction]

proc h*(resolved_file: ResolvedFile): string =
  # for user_mod in resolved_file.user_modules:
  #   echo "=".repeat(100)
  #   echo user_mod.h
  #   echo "=".repeat(100)
  #   echo "\n"

  # for function in resolved_file.functions:
  #   echo "=".repeat(100)
  #   echo function.h
  #   echo "=".repeat(100)
  #   echo "\n"

  @[
    resolved_file.user_modules.map_it(it.h).join("\n"),
    resolved_file.functions.map_it(it.h).join("\n\n"),
  ].join("\n")

proc c*(resolved_file: ResolvedFile): string =
  @[
    resolved_file.user_modules.map_it(it.c).join("\n"),
    resolved_file.functions.map_it(it.c).join("\n\n"),
  ].join("\n")

proc new_resolved_file*(user_modules: seq[ResolvedUserModule], functions: seq[
    ResolvedFunction]): ResolvedFile =
  ResolvedFile(user_modules: user_modules, functions: functions)
