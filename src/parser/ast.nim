import strformat, strutils, options, results

import tokenizer
import combinators

# ============================================================
# AST types
# ============================================================

type
  Identifier* = ref object
    value: string
    loc: Location

proc newIdentifier*(value: string, loc: Location): Result[Identifier, ParserError] =
  if value.len > 256:
    err(newParserError(fmt"identifier can be of max length 256", loc))
  elif value.startsWith("__asl"):
    err(newParserError(fmt"identifier can not start with '__asl'", loc))
  else:
    ok(Identifier(value: value, loc: loc))

proc value*(id: Identifier): string = id.value
proc loc*(id: Identifier): Location = id.loc

proc asl(identifier: Identifier): string = identifier.value

type Decorator* = ref object
  name: Identifier

proc newDecorator*(name: Identifier): Decorator =
  Decorator(name: name)

proc asl(decorator: Decorator): string =
  fmt"@{asl(decorator.name)}"

type Space* = ref object
  spaces: uint32
  loc: Location

proc newSpace*(spaces: uint32, loc: Location): Space =
  Space(spaces: spaces, loc: loc)

type ArgumentType* = ref object
  root: Identifier
  impls: seq[ArgumentType]
  loc: Location

proc root*(a: ArgumentType): Identifier = a.root
proc impls*(a: ArgumentType): seq[ArgumentType] = a.impls
proc loc*(a: ArgumentType): Location = a.loc

proc newArgumentType*(root: Identifier, loc: Location): ArgumentType =
  ArgumentType(root: root, loc: loc)

proc newArgumentType*(root: Identifier, impls: seq[ArgumentType],
    loc: Location): ArgumentType =
  ArgumentType(root: root, loc: loc, impls: impls)

proc asl(argType: ArgumentType): string =
  result = asl(argType.root)
  if argType.impls.len > 0:
    result.add("[")
    for i, impl in argType.impls:
      if i > 0: result.add(", ")
      result.add(asl(impl))
    result.add("]")

type ArgumentDefinition* = ref object
  name: Identifier
  argType: ArgumentType
  loc: Location

proc name*(argDef: ArgumentDefinition): Identifier = argDef.name
proc argType*(argDef: ArgumentDefinition): ArgumentType = argDef.argType
proc loc*(argDef: ArgumentDefinition): Location = argDef.loc

proc newArgumentDefinition*(name: Identifier, argType: ArgumentType,
    loc: Location): ArgumentDefinition =
  ArgumentDefinition(name: name, argType: argType, loc: loc)

proc asl(argDef: ArgumentDefinition): string =
  fmt"{asl(argDef.name)}: {asl(argDef.argType)}"

type ArgumentDefinitionList* = ref object
  argDefs*: seq[ArgumentDefinition]
  loc: Location

proc newArgumentDefinitionList*(argDefs: seq[ArgumentDefinition],
    loc: Location): ArgumentDefinitionList =
  ArgumentDefinitionList(argDefs: argDefs, loc: loc)

proc asl(argDefList: ArgumentDefinitionList): string =
  result = "("
  for i, argDef in argDefList.argDefs:
    if i > 0: result.add(", ")
    result.add(asl(argDef))
  result.add(")")

type Struct* = ref object
  fields: seq[ArgumentDefinition]
  loc: Location

proc fields*(s: Struct): seq[ArgumentDefinition] = s.fields
proc loc*(s: Struct): Location = s.loc

proc newStruct*(fields: seq[ArgumentDefinition], loc: Location): Struct =
  Struct(fields: fields, loc: loc)

proc asl(s: Struct, indentWidth: uint32): seq[string] =
  result.add("struct:")
  let indent = " ".repeat(indentWidth)
  for field in s.fields:
    result.add(fmt"{indent}{asl(field)}")

type VariantDefinition* = ref object
  name: Identifier
  fields: seq[ArgumentDefinition]
  loc: Location

proc name*(v: VariantDefinition): Identifier = v.name
proc fields*(v: VariantDefinition): seq[ArgumentDefinition] = v.fields
proc loc*(v: VariantDefinition): Location = v.loc

proc newVariantDefinition*(name: Identifier, fields: seq[ArgumentDefinition],
    loc: Location): VariantDefinition =
  VariantDefinition(name: name, fields: fields, loc: loc)

proc asl(varDef: VariantDefinition): string =
  result = asl(varDef.name)
  if varDef.fields.len > 0:
    result.add(" { ")
    for i, field in varDef.fields:
      if i > 0: result.add(", ")
      result.add(asl(field))
    result.add(" }")

type Union* = ref object
  variants: seq[VariantDefinition]
  loc: Location

proc variants*(u: Union): seq[VariantDefinition] = u.variants
proc loc*(u: Union): Location = u.loc

proc newUnion*(variants: seq[VariantDefinition], loc: Location): Union =
  Union(variants: variants, loc: loc)

proc asl(u: Union, indentWidth: uint32): seq[string] =
  result.add("union:")
  let indent = " ".repeat(indentWidth)
  for variant in u.variants:
    result.add(fmt"{indent}{asl(variant)}")

type
  DataBlockKind* = enum
    dbkStruct, dbkUnion
  DataBlock* = ref object
    case kind: DataBlockKind
    of dbkStruct: struct: Struct
    of dbkUnion: union: Union

proc kind*(db: DataBlock): DataBlockKind = db.kind
proc struct*(db: DataBlock): Struct =
  assert db.kind == dbkStruct,
    fmt"DataBlock.struct accessed but kind is {db.kind}"
  db.struct
proc union*(db: DataBlock): Union =
  assert db.kind == dbkUnion,
    fmt"DataBlock.union accessed but kind is {db.kind}"
  db.union

proc newDataBlock*(s: Struct): DataBlock =
  DataBlock(kind: dbkStruct, struct: s)

proc newDataBlock*(u: Union): DataBlock =
  DataBlock(kind: dbkUnion, union: u)

proc asl(db: DataBlock, indentWidth: uint32): seq[string] =
  case db.kind:
  of dbkStruct: asl(db.struct, indentWidth)
  of dbkUnion: asl(db.union, indentWidth)

type FunctionDefinition* = ref object
  name: Identifier
  argDefList: ArgumentDefinitionList
  returns: ArgumentType
  loc: Location

proc name*(fd: FunctionDefinition): Identifier = fd.name
proc params*(fd: FunctionDefinition): seq[
    ArgumentDefinition] = fd.argDefList.argDefs
proc returns*(fd: FunctionDefinition): ArgumentType = fd.returns
proc loc*(fd: FunctionDefinition): Location = fd.loc

proc newFunctionDefinition*(name: Identifier,
    argDefList: ArgumentDefinitionList, returns: ArgumentType,
    loc: Location): FunctionDefinition =
  FunctionDefinition(name: name, argDefList: argDefList, returns: returns, loc: loc)

proc asl(funcDef: FunctionDefinition): string =
  fmt"func {asl(funcDef.name)}{asl(funcDef.argDefList)}: {asl(funcDef.returns)}"

type StringContent* = ref object
  content*: string
  loc: Location

proc newStringContent*(content: string,
    loc: Location): StringContent =
  StringContent(content: content, loc: loc)

type
  ArgumentList* = ref object
    args: seq[Expression]
    loc: Location

  StringLiteral* = ref object
    content: string
    loc: Location

  UnsignedIntegerLiteral* = ref object
    value: string
    loc*: Location

  SignedIntegerLiteral* = ref object
    sign: string
    value: UnsignedIntegerLiteral
    loc*: Location

  IntegerLiteralKind* = enum
    ilkSigned, ilkUnsigned
  IntegerLiteral* = ref object
    case kind*: IntegerLiteralKind
    of ilkSigned: signed*: SignedIntegerLiteral
    of ilkUnsigned: unsigned*: UnsignedIntegerLiteral

  FloatLiteral* = ref object
    value: string
    loc: Location

  FunctionCall* = ref object
    argType: ArgumentType
    name: Identifier
    argList: ArgumentList

  Getter* = ref object
    source: Identifier
    property: Identifier
    loc: Location

  KeywordArgument* = ref object
    name: Identifier
    expression: Expression
    loc: Location

  KeywordArgumentList* = ref object
    args: seq[KeywordArgument]
    loc: Location

  LiteralKind* = enum
    lkString, lkInteger, lkFloat
  Literal* = ref object
    case kind*: LiteralKind
    of lkString: strLit*: StringLiteral
    of lkInteger: intLit*: IntegerLiteral
    of lkFloat: floatLit*: FloatLiteral

  LiteralInitializer* = ref object
    typeName: Identifier
    value: Literal
    loc: Location

  StructInitializer* = ref object
    argType: ArgumentType
    kwargList: KeywordArgumentList
    loc: Location

  UnionInitializer* = ref object
    argType: ArgumentType
    variantName: Identifier
    kwargList: KeywordArgumentList
    loc: Location

  InitializerKind* = enum
    ikLiteral, ikStruct, ikUnion
  Initializer* = ref object
    case kind*: InitializerKind
    of ikLiteral: literal*: LiteralInitializer
    of ikStruct: struct*: StructInitializer
    of ikUnion: union*: UnionInitializer

  ExpressionKind* = enum
    ekLiteral, ekFnCall, ekGetter, ekInitializer, ekVariable, ekMatch
  Expression* = ref object
    case kind*: ExpressionKind
    of ekLiteral: literal*: Literal
    of ekFnCall: fncall*: FunctionCall
    of ekGetter: getter*: Getter
    of ekInitializer: initializer*: Initializer
    of ekVariable: variable*: Identifier
    of ekMatch: match*: MatchExpression

  Assignment* = ref object
    target: Identifier
    expression: Expression
    loc: Location

  VariantPatternField* = ref object
    name: Identifier
    binding: Identifier
    loc: Location

  VariantPattern* = ref object
    variantName: Identifier
    fields: seq[VariantPatternField]
    loc: Location

  CasePatternKind* = enum
    cpkIntegerLiteral, cpkVariable, cpkVariant
  CasePattern* = ref object
    case kind*: CasePatternKind
    of cpkIntegerLiteral: intLit*: IntegerLiteral
    of cpkVariable: variable*: Identifier
    of cpkVariant: variant*: VariantPattern

  CaseBlock* = ref object
    pattern: CasePattern
    body: StatementList
    loc: Location

  MatchExpression* = ref object
    subject: Expression
    cases: seq[CaseBlock]
    loc: Location

  StatementKind* = enum
    skAssignment, skExpr
  Statement* = ref object
    case kind*: StatementKind
    of skAssignment: assignment*: Assignment
    of skExpr: expression*: Expression

  StatementList* = ref object
    statements*: seq[Statement]

proc newArgumentList*(args: seq[Expression], loc: Location): ArgumentList =
  ArgumentList(args: args, loc: loc)

proc newStringLiteral*(content: string, loc: Location): StringLiteral =
  StringLiteral(content: content, loc: loc)

proc newFunctionCall*(argType: ArgumentType, name: Identifier,
    argList: ArgumentList): FunctionCall =
  FunctionCall(argType: argType, name: name, argList: argList)

proc newExpression*(literal: Literal): Expression =
  Expression(kind: ekLiteral, literal: literal)

proc newExpression*(fncall: FunctionCall): Expression =
  Expression(kind: ekFnCall, fncall: fncall)

proc newGetter*(source: Identifier, property: Identifier,
    loc: Location): Getter =
  Getter(source: source, property: property, loc: loc)

proc newKeywordArgument*(name: Identifier, expression: Expression,
    loc: Location): KeywordArgument =
  KeywordArgument(name: name, expression: expression, loc: loc)

proc newKeywordArgumentList*(args: seq[KeywordArgument],
    loc: Location): KeywordArgumentList =
  KeywordArgumentList(args: args, loc: loc)

proc newLiteral*(strLit: StringLiteral): Literal =
  Literal(kind: lkString, strLit: strLit)

proc newLiteral*(intLit: IntegerLiteral): Literal =
  Literal(kind: lkInteger, intLit: intLit)

proc newLiteral*(floatLit: FloatLiteral): Literal =
  Literal(kind: lkFloat, floatLit: floatLit)

proc newLiteralInitializer*(typeName: Identifier, value: Literal,
    loc: Location): LiteralInitializer =
  LiteralInitializer(typeName: typeName, value: value, loc: loc)

proc newStructInitializer*(argType: ArgumentType,
    kwargList: KeywordArgumentList, loc: Location): StructInitializer =
  StructInitializer(argType: argType, kwargList: kwargList, loc: loc)

proc newInitializer*(literal: LiteralInitializer): Initializer =
  Initializer(kind: ikLiteral, literal: literal)

proc newInitializer*(struct: StructInitializer): Initializer =
  Initializer(kind: ikStruct, struct: struct)

proc newUnionInitializer*(argType: ArgumentType, variantName: Identifier,
    kwargList: KeywordArgumentList, loc: Location): UnionInitializer =
  UnionInitializer(argType: argType, variantName: variantName,
    kwargList: kwargList, loc: loc)

proc newInitializer*(union: UnionInitializer): Initializer =
  Initializer(kind: ikUnion, union: union)

proc newExpression*(getter: Getter): Expression =
  Expression(kind: ekGetter, getter: getter)

proc newUnsignedIntegerLiteral*(value: string,
    loc: Location): UnsignedIntegerLiteral =
  UnsignedIntegerLiteral(value: value, loc: loc)

proc newSignedIntegerLiteral*(sign: string, value: UnsignedIntegerLiteral,
    loc: Location): SignedIntegerLiteral =
  SignedIntegerLiteral(sign: sign, value: value, loc: loc)

proc newIntegerLiteral*(signed: SignedIntegerLiteral): IntegerLiteral =
  IntegerLiteral(kind: ilkSigned, signed: signed)

proc newIntegerLiteral*(unsigned: UnsignedIntegerLiteral): IntegerLiteral =
  IntegerLiteral(kind: ilkUnsigned, unsigned: unsigned)

proc newFloatLiteral*(value: string, loc: Location): FloatLiteral =
  FloatLiteral(value: value, loc: loc)

proc newExpression*(initializer: Initializer): Expression =
  Expression(kind: ekInitializer, initializer: initializer)

proc newExpression*(variable: Identifier): Expression =
  Expression(kind: ekVariable, variable: variable)

proc asl(expr: Expression): string

proc value*(strLit: StringLiteral): string = strLit.content

proc asl(strLit: StringLiteral): string = fmt"""{strLit.content}"""

proc asl(unsigned: UnsignedIntegerLiteral): string = unsigned.value

proc asl(signed: SignedIntegerLiteral): string =
  fmt"{signed.sign}{asl(signed.value)}"

proc asl(intLit: IntegerLiteral): string =
  case intLit.kind:
  of ilkSigned: asl(intLit.signed)
  of ilkUnsigned: asl(intLit.unsigned)

proc asl(argList: ArgumentList): string =
  result = "("
  for i, arg in argList.args:
    if i > 0: result.add(", ")
    result.add(asl(arg))
  result.add(")")

proc asl(fncall: FunctionCall): string =
  fmt"{asl(fncall.argType)}.{asl(fncall.name)}{asl(fncall.argList)}"

proc asl(getter: Getter): string =
  fmt"{asl(getter.source)}.{asl(getter.property)}"

proc asl(kwarg: KeywordArgument): string =
  fmt"{asl(kwarg.name)}: {asl(kwarg.expression)}"

proc asl(kwargList: KeywordArgumentList): string =
  result = "{ "
  for i, arg in kwargList.args:
    if i > 0: result.add(", ")
    result.add(asl(arg))
  result.add(" }")

proc asl(floatLit: FloatLiteral): string = floatLit.value

proc asl(literal: Literal): string =
  case literal.kind:
  of lkString: asl(literal.strLit)
  of lkInteger: asl(literal.intLit)
  of lkFloat: asl(literal.floatLit)

proc asl(prim: LiteralInitializer): string =
  fmt"{asl(prim.typeName)} {asl(prim.value)}"

proc asl(nonPrim: StructInitializer): string =
  fmt"{asl(nonPrim.argType)} {asl(nonPrim.kwargList)}"

proc asl(unionInit: UnionInitializer): string =
  fmt"{asl(unionInit.argType)}.{asl(unionInit.variantName)} {asl(unionInit.kwargList)}"

proc asl(initializer: Initializer): string =
  case initializer.kind:
  of ikLiteral: asl(initializer.literal)
  of ikStruct: asl(initializer.struct)
  of ikUnion: asl(initializer.union)

proc asl(expr: Expression): string =
  case expr.kind:
  of ekLiteral: asl(expr.literal)
  of ekFnCall: asl(expr.fncall)
  of ekGetter: asl(expr.getter)
  of ekInitializer: asl(expr.initializer)
  of ekVariable: asl(expr.variable)
  of ekMatch: "" # match is a block expression, use aslBlock

proc newAssignment*(target: Identifier, expression: Expression,
    loc: Location): Assignment =
  Assignment(target: target, expression: expression, loc: loc)

proc asl(assignment: Assignment): string =
  fmt"{asl(assignment.target)} = {asl(assignment.expression)}"

proc newCasePattern*(intLit: IntegerLiteral): CasePattern =
  CasePattern(kind: cpkIntegerLiteral, intLit: intLit)

proc newCasePattern*(variable: Identifier): CasePattern =
  CasePattern(kind: cpkVariable, variable: variable)

proc newVariantPatternField*(name: Identifier, binding: Identifier,
    loc: Location): VariantPatternField =
  VariantPatternField(name: name, binding: binding, loc: loc)

proc newVariantPattern*(variantName: Identifier,
    fields: seq[VariantPatternField],
    loc: Location): VariantPattern =
  VariantPattern(variantName: variantName, fields: fields, loc: loc)

proc loc*(vp: VariantPattern): Location = vp.loc

proc newCasePattern*(variant: VariantPattern): CasePattern =
  CasePattern(kind: cpkVariant, variant: variant)

proc asl(field: VariantPatternField): string =
  fmt"{asl(field.name)}: {asl(field.binding)}"

proc asl(variant: VariantPattern): string =
  result = fmt"{asl(variant.variantName)} {{ "
  for i, field in variant.fields:
    if i > 0: result.add(", ")
    result.add(asl(field))
  result.add(" }")

proc asl(pattern: CasePattern): string =
  case pattern.kind:
  of cpkIntegerLiteral: asl(pattern.intLit)
  of cpkVariable: asl(pattern.variable)
  of cpkVariant: asl(pattern.variant)

proc newCaseBlock*(pattern: CasePattern, body: StatementList,
    loc: Location): CaseBlock =
  CaseBlock(pattern: pattern, body: body, loc: loc)

proc newMatchExpression*(subject: Expression, cases: seq[CaseBlock],
    loc: Location): MatchExpression =
  MatchExpression(subject: subject, cases: cases, loc: loc)

proc newExpression*(match: MatchExpression): Expression =
  Expression(kind: ekMatch, match: match)

proc newStatement*(assignment: Assignment): Statement =
  Statement(kind: skAssignment, assignment: assignment)

proc newStatement*(expression: Expression): Statement =
  Statement(kind: skExpr, expression: expression)

proc newStatementList*(statements: seq[Statement]): StatementList =
  StatementList(statements: statements)

proc asl(caseBlock: CaseBlock, indentWidth: uint32): seq[string]
proc asl(matchExpr: MatchExpression, indentWidth: uint32): seq[string]

proc isBlockStatement(stmt: Statement): bool =
  case stmt.kind:
  of skExpr: stmt.expression.kind == ekMatch
  of skAssignment:
    stmt.assignment.expression.kind == ekMatch

proc asl(stmt: Statement): string
proc aslBlock(stmt: Statement, indentWidth: uint32): seq[string]

proc asl(stmt: Statement): string =
  case stmt.kind:
  of skAssignment: asl(stmt.assignment)
  of skExpr: asl(stmt.expression)

proc aslBlock(stmt: Statement, indentWidth: uint32): seq[string] =
  if not stmt.isBlockStatement:
    return @[asl(stmt)]
  case stmt.kind:
  of skExpr:
    result = asl(stmt.expression.match, indentWidth)
  of skAssignment:
    let matchLines = asl(stmt.assignment.expression.match, indentWidth)
    result.add(fmt"{asl(stmt.assignment.target)} = {matchLines[0]}")
    for i in 1..<matchLines.len:
      result.add(matchLines[i])

proc asl(caseBlock: CaseBlock, indentWidth: uint32): seq[string] =
  result.add(fmt"case {asl(caseBlock.pattern)}:")
  let indent = " ".repeat(indentWidth)
  for s in caseBlock.body.statements:
    for line in aslBlock(s, indentWidth):
      result.add(fmt"{indent}{line}")

proc asl(matchExpr: MatchExpression, indentWidth: uint32): seq[string] =
  result.add(fmt"match {asl(matchExpr.subject)}:")
  let indent = " ".repeat(indentWidth)
  for cb in matchExpr.cases:
    for line in asl(cb, indentWidth):
      result.add(fmt"{indent}{line}")

type Function* = ref object
  decorators: seq[Decorator]
  def: FunctionDefinition
  statementList: StatementList

proc name*(fn: Function): Identifier = fn.def.name
proc def*(fn: Function): FunctionDefinition = fn.def
proc statementList*(fn: Function): StatementList = fn.statementList
proc decorators*(fn: Function): seq[Decorator] = fn.decorators

proc newFunction*(decorators: seq[Decorator], def: FunctionDefinition,
    statementList: StatementList): Function =
  Function(decorators: decorators, def: def, statementList: statementList)

proc asl(fn: Function, indentWidth: uint32): seq[string] =
  for d in fn.decorators:
    result.add(asl(d))
  result.add(asl(fn.def))
  let indent = " ".repeat(indentWidth)
  for stmt in fn.statementList.statements:
    for line in aslBlock(stmt, indentWidth):
      result.add(fmt"{indent}{line}")

type FunctionList* = ref object
  functions*: seq[Function]

proc newFunctionList*(functions: seq[Function]): FunctionList =
  FunctionList(functions: functions)

type ImportName* = ref object
  name: Identifier
  alias: Option[Identifier]
  loc: Location

proc name*(n: ImportName): Identifier = n.name
proc alias*(n: ImportName): Option[Identifier] = n.alias
proc loc*(n: ImportName): Location = n.loc

proc newImportName*(name: Identifier, alias: Option[Identifier],
    loc: Location): ImportName =
  ImportName(name: name, alias: alias, loc: loc)

proc asl(importName: ImportName): string =
  if importName.alias.isSome:
    fmt"{asl(importName.name)} as {asl(importName.alias.get)}"
  else:
    asl(importName.name)

type Import* = ref object
  names: seq[ImportName]
  source: string
  path: string # absolute path of the imported file; set during BFS in parse*
  loc: Location

proc newImport*(names: seq[ImportName], source: string, loc: Location): Import =
  Import(names: names, source: source, loc: loc)

proc names*(imp: Import): seq[ImportName] = imp.names
proc source*(imp: Import): string = imp.source
proc path*(imp: Import): string = imp.path
proc `path=`*(imp: Import, p: string) = imp.path = p
proc loc*(imp: Import): Location = imp.loc

proc asl(imp: Import): string =
  result = "import { "
  for i, name in imp.names:
    if i > 0: result.add(", ")
    result.add(asl(name))
  result.add(fmt" }} from ""{imp.source}""")

type Generic* = ref object
  decorators: seq[Decorator]
  name: Identifier
  funcDefs: seq[FunctionDefinition]
  loc: Location

proc name*(g: Generic): Identifier = g.name
proc funcDefs*(g: Generic): seq[FunctionDefinition] = g.funcDefs
proc decorators*(g: Generic): seq[Decorator] = g.decorators
proc loc*(g: Generic): Location = g.loc

proc newGeneric*(decorators: seq[Decorator], name: Identifier,
    funcDefs: seq[FunctionDefinition], loc: Location): Generic =
  Generic(decorators: decorators, name: name, funcDefs: funcDefs, loc: loc)

proc asl(gen: Generic, indentWidth: uint32): seq[string] =
  for d in gen.decorators:
    result.add(asl(d))
  result.add(fmt"generic {asl(gen.name)}:")
  let indent = " ".repeat(indentWidth)
  for funcDef in gen.funcDefs:
    result.add(fmt"{indent}{asl(funcDef)}")

type Module* = ref object
  decorators: seq[Decorator]
  name: Identifier
  data: Option[DataBlock]
  funcList: FunctionList
  loc: Location

proc name*(m: Module): Identifier = m.name
proc data*(m: Module): Option[DataBlock] = m.data
proc functions*(m: Module): seq[Function] = m.funcList.functions
proc decorators*(m: Module): seq[Decorator] = m.decorators
proc loc*(m: Module): Location = m.loc

proc newModule*(decorators: seq[Decorator], name: Identifier,
    data: Option[DataBlock], funcList: FunctionList, loc: Location): Module =
  Module(decorators: decorators, name: name, data: data,
    funcList: funcList, loc: loc)

proc asl(module: Module, indentWidth: uint32): seq[string] =
  for d in module.decorators:
    result.add(asl(d))
  result.add(fmt"module {asl(module.name)}:")
  let indent = " ".repeat(indentWidth)
  if module.data.isSome:
    for line in asl(module.data.get, indentWidth):
      result.add(fmt"{indent}{line}")
    result.add("")
  for i, fn in module.funcList.functions:
    if i > 0: result.add("")
    for line in asl(fn, indentWidth):
      result.add(fmt"{indent}{line}")

type
  FileItemKind* = enum
    fikModule, fikGeneric
  FileItem* = ref object
    case kind*: FileItemKind
    of fikModule: module*: Module
    of fikGeneric: generic*: Generic

proc newFileItem*(module: Module): FileItem =
  FileItem(kind: fikModule, module: module)

proc newFileItem*(generic: Generic): FileItem =
  FileItem(kind: fikGeneric, generic: generic)

type File* = ref object
  path: string
  imports: seq[Import]
  modules: seq[Module]
  generics: seq[Generic]

proc newFile*(path: string, imports: seq[Import], items: seq[FileItem]): File =
  var modules: seq[Module]
  var generics: seq[Generic]
  for item in items:
    case item.kind:
    of fikModule: modules.add(item.module)
    of fikGeneric: generics.add(item.generic)
  File(path: path, imports: imports, modules: modules, generics: generics)

proc path*(file: File): string = file.path
proc imports*(file: File): seq[Import] = file.imports
proc modules*(file: File): seq[Module] = file.modules
proc generics*(file: File): seq[Generic] = file.generics

proc asl*(file: File, indentWidth: uint32): string =
  var lines: seq[string]
  for imp in file.imports:
    lines.add(asl(imp))
  if file.imports.len > 0 and (file.generics.len > 0 or file.modules.len > 0):
    lines.add("")
  for i, gen in file.generics:
    if i > 0: lines.add("")
    for line in asl(gen, indentWidth):
      lines.add(line)
  if file.generics.len > 0 and file.modules.len > 0:
    lines.add("")
  for i, module in file.modules:
    if i > 0: lines.add("")
    for line in asl(module, indentWidth):
      lines.add(line)
  lines.join("\n") & "\n"
