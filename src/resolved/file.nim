import sequtils, strutils

import struct, function

type ResolvedFile* = ref object of RootObj
  structs: seq[ResolvedStruct]
  functions: seq[ResolvedFunction]

proc h*(resolved_file: ResolvedFile): string =
  @[
    resolved_file.structs.map_it(it.h).join("\n"),
    resolved_file.functions.map_it(it.h).join("\n\n"),
  ].join("\n")

proc c*(resolved_file: ResolvedFile): string =
  @[
    resolved_file.structs.map_it(it.c).join("\n"),
    resolved_file.functions.map_it(it.c).join("\n\n"),
  ].join("\n")

proc new_resolved_file*(structs: seq[ResolvedStruct], functions: seq[
    ResolvedFunction]): ResolvedFile =
  ResolvedFile(structs: structs, functions: functions)
