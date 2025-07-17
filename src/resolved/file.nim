import sequtils, strutils

import struct, function

type ResolvedFile* = ref object of RootObj
  structs: seq[ResolvedStruct]
  unions: seq[ResolvedUnion]
  functions: seq[ResolvedFunction]

proc h*(resolved_file: ResolvedFile): string =
  @[
    resolved_file.structs.map_it(it.h).join("\n"),
    resolved_file.unions.map_it(it.h).join("\n"),
    resolved_file.functions.map_it(it.h).join("\n\n"),
  ].join("\n")

proc c*(resolved_file: ResolvedFile): string =
  # TODO: Support impls for resolved unions
  @[
    resolved_file.structs.map_it(it.c).join("\n"),
    resolved_file.unions.map_it(it.c).join("\n"),
    resolved_file.functions.map_it(it.c).join("\n\n"),
  ].join("\n")

proc new_resolved_file*(structs: seq[ResolvedStruct], unions: seq[
    ResolvedUnion], functions: seq[ResolvedFunction]): ResolvedFile =
  ResolvedFile(structs: structs, unions: unions, functions: functions)
