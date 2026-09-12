import strformat, strutils, options, sequtils, tables, results

import ../tokenizer/main as tokenizer

import parser
import error

import identifiers
import literals

# ImportPath (relative vs vendor), VendorRoots, and the path-resolution
# logic (toImportPath / toAbsPath) were extracted to importpath.nim;
# re-exported so `import imports` and the parser/main barrel still
# surface them.
import importpath
export importpath

# ============================================================
# ImportedType
# ============================================================

type ImportedType* = ref object
  name: Identifier
  alias: Option[Identifier]

proc newImportedType*(name: Identifier, alias: Identifier): ImportedType =
  ImportedType(name: name, alias: some(alias))

proc newImportedType*(name: Identifier): ImportedType =
  ImportedType(name: name, alias: none(Identifier))

proc name*(n: ImportedType): Identifier = n.name
proc loc*(n: ImportedType): Location = n.name.loc
proc binding*(n: ImportedType): Identifier =
  if n.alias.isSome: n.alias.get else: n.name

proc asl*(importedType: ImportedType): string =
  if importedType.alias.isSome:
    fmt"{asl(importedType.name)} as {asl(importedType.alias.get)}"
  else:
    asl(importedType.name)

proc explicitImportedTypeConsumer(parser: Parser): Result[ImportedType, ParserError] =
  let name = ? parser.expect(identifierSpec)
  discard ? parser.expect(spaceSpec)
  discard ? parser.expect("as")
  discard ? parser.expect(spaceSpec)
  let alias = ? parser.expect(identifierSpec)
  ok(newImportedType(name, alias))

let explicitImportedTypeSpec = newSpec("explicit imported type", explicitImportedTypeConsumer)

let implicitImportedTypeSpec = map(identifierSpec,
  proc(name: Identifier): ImportedType = newImportedType(name))


let importedTypeSpec* = oneOf("imported type", @[
  explicitImportedTypeSpec,
  implicitImportedTypeSpec,
])

# ============================================================
# Import
# ============================================================

proc validateTypeNameConflict(importedTypes: seq[ImportedType]): Result[void, ParserError] =
  var nameIndex: Table[Identifier, int]
  for index, importType in importedTypes:
    if importType.name in nameIndex:
      let loc = importedTypes[nameIndex[importType.name]].loc
      let msg = fmt"duplicate import encountered, see previous import at {loc}"
      return err(newParserError(msg, importType.loc))
    nameIndex[importType.name] = index
  ok()

proc validateBindingNameConflict(importedTypes: seq[ImportedType]): Result[void, ParserError] =
  var bindingIndex: Table[Identifier, int]
  for index, importType in importedTypes:
    let binding = if importType.alias.isSome: importType.alias.get else: importType.name
    if binding in bindingIndex:
      let loc = importedTypes[bindingIndex[binding]].loc
      let msg = fmt"duplicate import binding encountered, see previous import at {loc}"
      return err(newParserError(msg, binding.loc))
    else:
      bindingIndex[binding] = index
  ok()

type
  ImportKind* = enum
    ikExplicit, ikShorthand
  Import* = ref object
    parsedPath: ImportPath # typed parsed source — either `ipkRelative` or `ipkVendor`
    absPath: string        # absolute path of the imported file; set during BFS in parse*
    loc: Location
    case kind: ImportKind
    of ikExplicit: names: seq[ImportedType]
    of ikShorthand: discard

proc newImport*(names: seq[ImportedType], parsedPath: ImportPath, absPath: string,
    loc: Location): Result[Import, ParserError] =
  ## Explicit form: `import { Name, Name as Alias, ... } from "path"`.
  ## Validates per-import uniqueness of both `name` and `binding`
  ## (binding = alias if present, else name).
  ? validateTypeNameConflict(names)
  ? validateBindingNameConflict(names)
  ok(Import(kind: ikExplicit, names: names, parsedPath: parsedPath, absPath: absPath, loc: loc))

proc newImport*(parsedPath: ImportPath, absPath: string, loc: Location): Result[Import, ParserError] =
  ## Shorthand form: `import "path"` — brings every public defined type
  ## from the target file into scope under its original name. No names
  ## list at parse time; the resolver expands it once the target
  ## file's types are resolved. No uniqueness check here
  ## (there are no names yet); collisions are caught at resolver time.
  ok(Import(kind: ikShorthand, parsedPath: parsedPath, absPath: absPath, loc: loc))

proc kind*(imp: Import): ImportKind = imp.kind
proc names*(imp: Import): seq[ImportedType] =
  assert imp.kind == ikExplicit,
    fmt"Import.names accessed but kind is {imp.kind}"
  imp.names
proc absPath*(imp: Import): string = imp.absPath
proc loc*(imp: Import): Location = imp.loc

proc asl*(imp: Import): string =
  var content: string
  case imp.kind:
  of ikExplicit:
    let inner = imp.names.mapIt(asl(it)).join(", ")
    content.add(fmt"import {{ {inner} }} from ""{asl(imp.parsedPath)}""")
  of ikShorthand:
    content.add(fmt"import ""{asl(imp.parsedPath)}""")
  content

# Explicit form: `import { Name, Name as Alias } from "path"`.
proc explicitImportLineConsumer(parser: Parser): Result[Import, ParserError] =
  let importKeyword = ? parser.expect("import")
  discard ? parser.expect(spaceSpec)
  let (names, _)  = ? parser.expect(importedTypeSpec.curlyBracketList(allowEmpty = false))
  discard ? parser.expect(spaceSpec)
  discard ? parser.expect("from")
  discard ? parser.expect(spaceSpec)
  let source = ? parser.expect(stringLiteralSpec)
  discard ? parser.expect(emptyLineSpec)
  let parsedPath = ? toImportPath(source.content, source.loc)
  let maybePath = toAbsPath(parsedPath, parser.filepath, initTable[string, string]())
  if maybePath.isOk:
    newImport(names, parsedPath, maybePath.get, importKeyword.loc)
  else:
    err(newParserError(maybePath.error, source.loc))

let explicitImportLineSpec = newSpec[Import]("explicit import", explicitImportLineConsumer)

# Shorthand form: `import "path"` — brings every public defined
# type from the target file into scope under each type's original
# name. The names list is materialized by the resolver once the
# target file's types are resolved.
proc shorthandImportLineConsumer(parser: Parser): Result[Import, ParserError] =
  let importKeyword = ? parser.expect("import")
  discard ? parser.expect(spaceSpec)
  let source = ? parser.expect(stringLiteralSpec)
  discard ? parser.expect(emptyLineSpec)
  let parsedPath = ? toImportPath(source.content, source.loc)
  let maybePath = toAbsPath(parsedPath, parser.filepath, initTable[string, string]())
  if maybePath.isOk:
    newImport(parsedPath, maybePath.get, importKeyword.loc)
  else:
    err(newParserError(maybePath.error, source.loc))

let shorthandImportLineSpec = newSpec[Import]("implicit import", shorthandImportLineConsumer)

let importLineSpec =
  oneOf("import line", @[
    explicitImportLineSpec,
    shorthandImportLineSpec,
  ])

proc importConsumer(parser: Parser): Result[Import, ParserError] =
  ## Skips leading blank / comment lines, then parses one import line
  ## (either explicit `import { A, B } from "path"` or shorthand
  ## `import "path"`).
  discard ? parser.expect(any(emptyLineSpec))
  parser.expect(importLineSpec)

let importSpec* = newSpec[Import]("import", importConsumer)