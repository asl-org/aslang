import sequtils, strutils

import union, function

type ResolvedFile* = ref object of RootObj
  user_modules: seq[ResolvedUserModule]
  functions: seq[ResolvedFunction]

proc h*(resolved_file: ResolvedFile): string =
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
