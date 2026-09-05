import strformat, strutils, options, sequtils, tables, results

import ../tokenizer/index as tokenizer
import ./error

import ./identifiers

# ============================================================
# ImportPath
# ============================================================
#
# The user-typed source of an import — either a relative path
# (`"./foo.asl"`) or a vendor reference (`"@std"`, `"@runtime"`).
# Used as the parsed form of `Import.source` once W3 lands; for now
# it lives standalone and `toImportPath` is the entry point for
# converting a raw quoted-string source into the typed form.

type
  ImportPathKind* = enum
    ipkRelative, ipkVendor
  ImportPath* = ref object
    case kind: ImportPathKind
    of ipkRelative: relativeSource: string
    of ipkVendor: vendorName: string

proc newRelativeImportPath*(relativeSource: string): ImportPath =
  ImportPath(kind: ipkRelative, relativeSource: relativeSource)

proc newVendorImportPath*(vendorName: string): ImportPath =
  ImportPath(kind: ipkVendor, vendorName: vendorName)

proc kind*(p: ImportPath): ImportPathKind = p.kind

proc relativeSource*(p: ImportPath): string =
  assert p.kind == ipkRelative,
    fmt"ImportPath.relativeSource accessed but kind is {p.kind}"
  p.relativeSource

proc vendorName*(p: ImportPath): string =
  assert p.kind == ipkVendor,
    fmt"ImportPath.vendorName accessed but kind is {p.kind}"
  p.vendorName

proc asl*(p: ImportPath): string =
  ## Renders the user-visible form of the import source — what the
  ## user would have typed (or could have typed for compiler-injected
  ## imports).
  case p.kind:
  of ipkRelative: p.relativeSource
  of ipkVendor: fmt"@{p.vendorName}"

# ============================================================
# VendorRoots
# ============================================================
#
# A vendor name → absolute path table, built by the CLI from
# repeated `--vendor="<name>:<path>"` flags (plus the default
# `std → examples/base.aslr` when not user-supplied). Threaded
# through `parse*` → `aslFileSpec` → `newAslFile` so that auto-
# injected `import "@std"` and any user-written `import "@<name>"`
# resolve via the same lookup.

type VendorRoots* = Table[string, string]

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
