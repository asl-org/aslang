import results, options, strformat

import parser

type File = parser.File

type ResolvedLiteralType = enum
  rltkU8, rltkU16, rltkU32, rltkU64
  rltkI8, rltkI16, rltkI32, rltkI64
  rltkF32, rltkF64, rltkString

proc resolveLiteralBlock(file: File, literal: LiteralType): Result[ResolvedLiteralType, string] =
  case literal.content:
  of "u8": ok(rltkU8)
  of "u16": ok(rltkU16)
  of "u32": ok(rltkU32)
  of "u64": ok(rltkU64)
  of "i8": ok(rltkI8)
  of "i16": ok(rltkI16)
  of "i32": ok(rltkI32)
  of "i64": ok(rltkI64)
  of "f32": ok(rltkF32)
  of "f64": ok(rltkF64)
  of "string": ok(rltkString)
  else: err(fmt"{file.path}:{literal.loc} unsupported literal type encountered `{literal.content}`")

proc resolveImport(app: App, file: File, imp: Import): Result[void, string] =
  err("todo: resolve import")

proc resolveFunction(app: App, file: File, module: Module, function: Function): Result[void, string] =
  err("todo: resolve function")

proc resolveDataBlock(app: App, file: File, module: Module, data: DataBlock): Result[void, string] =
  case data.kind:
  of dbkLiteral:
    discard ? resolveLiteralBlock(file, data.literal)
    ok()
  of dbkStruct: err("todo: resolve struct block")
  of dbkUnion: err("todo: resolve union block")

proc resolveModule(app: App, file: File, module: Module): Result[void, string] =
  if module.decorators.len > 0:
    return err("todo: resolve decorators")

  if module.requires.isSome:
    return err("todo: resolve requires block")

  if module.data.isSome:
    ? resolveDataBlock(app, file, module, module.data.get)

  for function in module.functions:
    ? resolveFunction(app, file, module, function)

  err("todo: resolve module")

proc resolveDefinedType(app: App, file: File, definedType: DefinedType): Result[void, string] =
  case definedType.kind:
  of dtkGeneric: err("todo: resolve generic")
  of dtkModule: resolveModule(app, file, definedType.module)

proc resolveFile(app: App, file: File): Result[void, string] =
  for imp in file.imports:
    ? resolveImport(app, file, imp)

  for definedType in file.definedTypes:
    ? resolveDefinedType(app, file, definedType)

  err("todo: resolve file")

proc resolve*(app: App): Result[void, string] =
  for file in app.files:
    ? resolveFile(app, file)

  err("todo: resolve app")
