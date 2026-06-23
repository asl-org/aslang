import strformat, strutils, options, tables, results, os

import tokenizer
import combinators
import helpers
import identifiers
import strings

# ============================================================
# ImportedType
# ============================================================

type ImportedType* = ref object
  name: Identifier
  alias: Option[Identifier]
  loc: Location

proc name*(n: ImportedType): Identifier = n.name
proc alias*(n: ImportedType): Option[Identifier] = n.alias
proc loc*(n: ImportedType): Location = n.loc
proc binding*(n: ImportedType): Identifier =
  if n.alias.isSome: n.alias.get else: n.name

proc newImportedType*(name: Identifier, alias: Option[Identifier],
    loc: Location): ImportedType =
  ImportedType(name: name, alias: alias, loc: loc)

proc asl*(importedType: ImportedType): string =
  if importedType.alias.isSome:
    fmt"{asl(importedType.name)} as {asl(importedType.alias.get)}"
  else:
    asl(importedType.name)

# import { Name, Name } from "path"
# identifier ("as" identifier)?
let importedTypeSpec* = Spec[ImportedType](
  name: "import_name",
  parseFn: proc(parser: Parser): Result[ImportedType, ParserError] =
  let name = ? parser.run(identifierSpec)
  let maybeAs = parser.run(atLeastOne(spaceSpec))
  if maybeAs.isErr:
    return ok(newImportedType(name, none(Identifier), name.loc))
  let maybeAsKeyword = parser.run(keywordSpec("as"))
  if maybeAsKeyword.isErr:
    return ok(newImportedType(name, none(Identifier), name.loc))
  discard ? parser.run(atLeastOne(spaceSpec))
  let alias = ? parser.run(identifierSpec)
  ok(newImportedType(name, some(alias), name.loc))
)

# ============================================================
# Import
# ============================================================

type
  ImportKind* = enum
    ikExplicit, ikShorthand
  Import* = ref object
    source: string
    path: string # absolute path of the imported file; set during BFS in parse*
    loc: Location
    case kind: ImportKind
    of ikExplicit: names: seq[ImportedType]
    of ikShorthand: discard

proc newImport*(names: seq[ImportedType], source: string, path: string,
    loc: Location): Result[Import, ParserError] =
  ## Explicit form: `import { Name, Name as Alias, ... } from "path"`.
  ## Validates per-import uniqueness of both `name` and `binding`
  ## (binding = alias if present, else name).
  var nameIndex: Table[Identifier, int]
  var bindingIndex: Table[Identifier, int]
  for index, importType in names:
    if importType.name in nameIndex:
      let prev = names[nameIndex[importType.name]]
      let msg = fmt"duplicate import encountered, see previous import at {prev.loc}"
      return err(newParserError(msg, importType.loc))
    else:
      nameIndex[importType.name] = index

    let binding = if importType.alias.isSome: importType.alias.get else: importType.name
    if binding in bindingIndex:
      let prev = names[bindingIndex[binding]]
      let msg = fmt"duplicate import binding encountered, see previous import at {prev.loc}"
      return err(newParserError(msg, binding.loc))
    else:
      bindingIndex[binding] = index

  ok(Import(kind: ikExplicit, names: names, source: source, path: path, loc: loc))

proc newImport*(source: string, path: string, loc: Location): Result[Import, ParserError] =
  ## Shorthand form: `import "path"` — brings every public defined type
  ## from the target file into scope under its original name. No names
  ## list at parse time; the resolver expands via `publicTypes()` once
  ## the target file's parser AST is in hand. No uniqueness check here
  ## (there are no names yet); collisions are caught at resolver time.
  ok(Import(kind: ikShorthand, source: source, path: path, loc: loc))

proc kind*(imp: Import): ImportKind = imp.kind
proc names*(imp: Import): seq[ImportedType] =
  assert imp.kind == ikExplicit,
    fmt"Import.names accessed but kind is {imp.kind}"
  imp.names
proc source*(imp: Import): string = imp.source
proc path*(imp: Import): string = imp.path
proc loc*(imp: Import): Location = imp.loc

proc asl*(imp: Import): string =
  case imp.kind:
  of ikExplicit:
    result = "import { "
    for i, name in imp.names:
      if i > 0: result.add(", ")
      result.add(asl(name))
    result.add(fmt" }} from ""{imp.source}""")
  of ikShorthand:
    result = fmt"import ""{imp.source}"""

proc resolveImportPath*(source: string, importingFile: string): Result[string, string] =
  ## Resolves an import path relative to the importing file.
  ## Rejects paths that escape to parent directories.
  ## Normalizes the resolved path so tricks like ./sub/../../escape
  ## are caught — not just paths starting with "..".
  let dir = normalizedPath(importingFile.parentDir)
  let resolved = normalizedPath((dir / source).absolutePath)
  let dirPrefix = if dir.endsWith($DirSep): dir else: dir & $DirSep
  if not resolved.startsWith(dirPrefix):
    return err(fmt"{importingFile}: import path '{source}' escapes to parent directory — imports must be from adjacent files or subdirectories")
  ok(resolved)

# TODO(import-shorthand): refactor to `oneOf(explicitImportLineSpec,
# shorthandImportLineSpec)` once the tagged-union Import lands (W2).
# The explicit spec stays as-is below; the shorthand spec parses
# `import` + space + stringLiteralSpec + ignorableLineSpec and builds
# an ikShorthand Import via the new constructor. Try explicit first
# — the `{` after `import ` disambiguates immediately. See W4 in
# plans/how-is-claude-parsed-whistle.md.
let importLineSpec* = Spec[Import](
  name: "import_line",
  parseFn: proc(parser: Parser): Result[Import, ParserError] =
  let loc = ? parser.run(keywordSpec("import"))
  discard ? parser.run(atLeastOne(spaceSpec))
  let names = ? parser.run(contained("import_names", "{",
    separatedBy(importedTypeSpec, commaWithSpacesSpec), "}"))
  discard ? parser.run(atLeastOne(spaceSpec))
  discard ? parser.run(keywordSpec("from"))
  discard ? parser.run(atLeastOne(spaceSpec))
  let source = ? parser.run(stringLiteralSpec)
  discard ? parser.run(ignorableLineSpec)
  let maybePath = resolveImportPath(source.value, parser.filepath)
  if maybePath.isOk:
    newImport(names, source.value, maybePath.get, loc)
  else:
    err(newParserError(maybePath.error, source.loc))
)

let importBlockSpec* = Spec[Import](
  name: "import_block",
  parseFn: proc(parser: Parser): Result[Import, ParserError] =
  discard parser.run(any(ignorableLineSpec))
  let imp = ? parser.run(importLineSpec)
  ok(imp)
)
