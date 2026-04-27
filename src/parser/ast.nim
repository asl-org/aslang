import strformat, strutils, options, results, tables, hashes

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

proc hash*(id: Identifier): Hash = hash(id.value)
proc `==`*(id: Identifier, other: Identifier): bool = hash(id) == hash(other)

proc asl*(identifier: Identifier): string = identifier.value

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
  argDefs: seq[ArgumentDefinition]
  argNameIndex: Table[Identifier, int]
  loc: Location

proc newArgumentDefinitionList*(argDefs: seq[ArgumentDefinition],
    loc: Location): Result[ArgumentDefinitionList, ParserError] =
  var argNameIndex: Table[Identifier, int]
  for index, argDef in argDefs:
    if argDef.name in argNameIndex:
      let prev = argDefs[argNameIndex[argDef.name]]
      let msg = fmt"duplicate argument encountered, see previous declaration at {prev.loc}"
      return err(newParserError(msg, argDef.loc))
    argNameIndex[argDef.name] = index
  ok(ArgumentDefinitionList(argDefs: argDefs, argNameIndex: argNameIndex, loc: loc))

proc arity(argDefList: ArgumentDefinitionList): int =
  argDefList.argDefs.len

proc asl(argDefList: ArgumentDefinitionList): string =
  result = "("
  for i, argDef in argDefList.argDefs:
    if i > 0: result.add(", ")
    result.add(asl(argDef))
  result.add(")")

type StringLiteral* = ref object
  content: string
  loc: Location

proc newStringLiteral*(content: string, loc: Location): StringLiteral =
  StringLiteral(content: content, loc: loc)

proc loc*(strLit: StringLiteral): Location = strLit.loc
proc value*(strLit: StringLiteral): string = strLit.content
proc asl(strLit: StringLiteral): string = fmt"""{strLit.content}"""

type LiteralType* = ref object
  value: StringLiteral
  loc: Location

proc newLiteralType*(value: StringLiteral, loc: Location): LiteralType =
  LiteralType(value: value, loc: loc)

proc content*(literalType: LiteralType): string = literalType.value.content
proc loc*(literalType: LiteralType): Location = literalType.loc

proc asl(l: LiteralType): seq[string] =
  @[fmt"literal: {asl(l.value)}"]

type Struct* = ref object
  fields: seq[ArgumentDefinition]
  fieldIndex: Table[Identifier, int]
  loc: Location

proc fields*(s: Struct): seq[ArgumentDefinition] = s.fields
proc loc*(s: Struct): Location = s.loc

proc newStruct*(fields: seq[ArgumentDefinition], loc: Location): Result[Struct, ParserError] =
  if fields.len == 0:
    return err(newParserError("struct must have at least one field", loc))
  var fieldIndex: Table[Identifier, int]
  for index, field in fields:
    if field.name in fieldIndex:
      let prev = fields[fieldIndex[field.name]]
      let msg = fmt"duplicate field encountered, see previous declaration at {prev.loc}"
      return err(newParserError(msg, field.loc))
    fieldIndex[field.name] = index
  ok(Struct(fields: fields, fieldIndex: fieldIndex, loc: loc))

proc asl(s: Struct, indentWidth: uint32): seq[string] =
  result.add("struct:")
  let indent = " ".repeat(indentWidth)
  for field in s.fields:
    result.add(fmt"{indent}{asl(field)}")

type VariantDefinition* = ref object
  name: Identifier
  fields: seq[ArgumentDefinition]
  fieldIndex: Table[Identifier, int]
  loc: Location

proc name*(v: VariantDefinition): Identifier = v.name
proc fields*(v: VariantDefinition): seq[ArgumentDefinition] = v.fields
proc loc*(v: VariantDefinition): Location = v.loc

proc newVariantDefinition*(name: Identifier, fields: seq[ArgumentDefinition],
    loc: Location): Result[VariantDefinition, ParserError] =
  var fieldIndex: Table[Identifier, int]
  for index, field in fields:
    if field.name in fieldIndex:
      let prev = fields[fieldIndex[field.name]]
      let msg = fmt"duplicate field encountered, see previous declaration at {prev.loc}"
      return err(newParserError(msg, field.loc))
    fieldIndex[field.name] = index
  ok(VariantDefinition(name: name, fields: fields, fieldIndex: fieldIndex, loc: loc))

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
  variantIndex: Table[Identifier, int]
  loc: Location

proc variants*(u: Union): seq[VariantDefinition] = u.variants
proc loc*(u: Union): Location = u.loc

proc newUnion*(variants: seq[VariantDefinition], loc: Location): Result[Union, ParserError] =
  var variantIndex: Table[Identifier, int]
  for index, variant in variants:
    if variant.name in variantIndex:
      let prev = variants[variantIndex[variant.name]]
      let msg = fmt"duplicate variant encountered, see previous declaration at {prev.loc}"
      return err(newParserError(msg, variant.loc))
    variantIndex[variant.name] = index
  ok(Union(variants: variants, variantIndex: variantIndex, loc: loc))

proc asl(u: Union, indentWidth: uint32): seq[string] =
  result.add("union:")
  let indent = " ".repeat(indentWidth)
  for variant in u.variants:
    result.add(fmt"{indent}{asl(variant)}")

type
  DataBlockKind* = enum
    dbkLiteral, dbkStruct, dbkUnion
  DataBlock* = ref object
    case kind: DataBlockKind
    of dbkLiteral: literal: LiteralType
    of dbkStruct: struct: Struct
    of dbkUnion: union: Union

proc newDataBlock*(l: LiteralType): DataBlock =
  DataBlock(kind: dbkLiteral, literal: l)

proc newDataBlock*(s: Struct): DataBlock =
  DataBlock(kind: dbkStruct, struct: s)

proc newDataBlock*(u: Union): DataBlock =
  DataBlock(kind: dbkUnion, union: u)


proc kind*(db: DataBlock): DataBlockKind = db.kind
proc literal*(db: DataBlock): LiteralType =
  assert db.kind == dbkLiteral,
    fmt"DataBlock.literal accessed but kind is {db.kind}"
  db.literal
proc struct*(db: DataBlock): Struct =
  assert db.kind == dbkStruct,
    fmt"DataBlock.struct accessed but kind is {db.kind}"
  db.struct
proc union*(db: DataBlock): Union =
  assert db.kind == dbkUnion,
    fmt"DataBlock.union accessed but kind is {db.kind}"
  db.union

proc loc*(db: DataBlock): Location =
  case db.kind:
  of dbkLiteral: db.literal.loc
  of dbkStruct: db.struct.loc
  of dbkUnion: db.union.loc

proc asl(db: DataBlock, indentWidth: uint32): seq[string] =
  case db.kind:
  of dbkLiteral: asl(db.literal)
  of dbkStruct: asl(db.struct, indentWidth)
  of dbkUnion: asl(db.union, indentWidth)

type FunctionDefinition* = ref object
  public: bool
  name: Identifier
  argDefList: ArgumentDefinitionList
  returns: ArgumentType
  loc: Location

proc public*(fd: FunctionDefinition): bool = fd.public
proc name*(fd: FunctionDefinition): Identifier = fd.name
proc args*(fd: FunctionDefinition): seq[
    ArgumentDefinition] = fd.argDefList.argDefs
proc returns*(fd: FunctionDefinition): ArgumentType = fd.returns
proc loc*(fd: FunctionDefinition): Location = fd.loc
proc arity(fd: FunctionDefinition): int = fd.argDefList.arity

proc newFunctionDefinition*(public: bool, name: Identifier,
    argDefList: ArgumentDefinitionList, returns: ArgumentType,
    loc: Location): FunctionDefinition =
  FunctionDefinition(public: public, name: name, argDefList: argDefList,
      returns: returns, loc: loc)

proc asl(funcDef: FunctionDefinition): string =
  let prefix = if funcDef.public: "public func" else: "func"
  fmt"{prefix} {asl(funcDef.name)}{asl(funcDef.argDefList)}: {asl(funcDef.returns)}"

type StringContent* = ref object
  content: string
  loc: Location

proc newStringContent*(content: string,
    loc: Location): StringContent =
  StringContent(content: content, loc: loc)

proc content*(sc: StringContent): string = sc.content

type UnsignedIntegerLiteral* = ref object
  value: string
  loc: Location

proc newUnsignedIntegerLiteral*(value: string,
    loc: Location): UnsignedIntegerLiteral =
  UnsignedIntegerLiteral(value: value, loc: loc)

proc value*(literal: UnsignedIntegerLiteral): string = literal.value
proc loc*(uil: UnsignedIntegerLiteral): Location = uil.loc
proc asl(unsigned: UnsignedIntegerLiteral): string = unsigned.value

type SignedIntegerLiteral* = ref object
  sign: string
  value: UnsignedIntegerLiteral
  loc: Location

proc newSignedIntegerLiteral*(sign: string, value: UnsignedIntegerLiteral,
    loc: Location): SignedIntegerLiteral =
  SignedIntegerLiteral(sign: sign, value: value, loc: loc)

proc loc*(sil: SignedIntegerLiteral): Location = sil.loc

proc asl(signed: SignedIntegerLiteral): string =
  fmt"{signed.sign}{asl(signed.value)}"

type
  IntegerLiteralKind* = enum
    ilkSigned, ilkUnsigned
  IntegerLiteral* = ref object
    case kind: IntegerLiteralKind
    of ilkSigned: signed: SignedIntegerLiteral
    of ilkUnsigned: unsigned: UnsignedIntegerLiteral

proc newIntegerLiteral*(signed: SignedIntegerLiteral): IntegerLiteral =
  IntegerLiteral(kind: ilkSigned, signed: signed)

proc newIntegerLiteral*(unsigned: UnsignedIntegerLiteral): IntegerLiteral =
  IntegerLiteral(kind: ilkUnsigned, unsigned: unsigned)

proc kind*(il: IntegerLiteral): IntegerLiteralKind = il.kind

proc signed*(il: IntegerLiteral): SignedIntegerLiteral =
  assert il.kind == ilkSigned,
    fmt"IntegerLiteral.signed accessed but kind is {il.kind}"
  il.signed

proc unsigned*(il: IntegerLiteral): UnsignedIntegerLiteral =
  assert il.kind == ilkUnsigned,
    fmt"IntegerLiteral.unsigned accessed but kind is {il.kind}"
  il.unsigned

proc loc(intLit: IntegerLiteral): Location =
  case intLit.kind:
  of ilkSigned: intLit.signed.loc
  of ilkUnsigned: intLit.unsigned.loc

proc asl(intLit: IntegerLiteral): string =
  case intLit.kind:
  of ilkSigned: asl(intLit.signed)
  of ilkUnsigned: asl(intLit.unsigned)

type FloatLiteral* = ref object
  value: string
  loc: Location

proc newFloatLiteral*(value: string, loc: Location): FloatLiteral =
  FloatLiteral(value: value, loc: loc)

proc asl(floatLit: FloatLiteral): string = floatLit.value

type
  LiteralKind* = enum
    lkString, lkInteger, lkFloat
  Literal* = ref object
    case kind: LiteralKind
    of lkString: strLit: StringLiteral
    of lkInteger: intLit: IntegerLiteral
    of lkFloat: floatLit: FloatLiteral

proc newLiteral*(strLit: StringLiteral): Literal =
  Literal(kind: lkString, strLit: strLit)

proc newLiteral*(intLit: IntegerLiteral): Literal =
  Literal(kind: lkInteger, intLit: intLit)

proc newLiteral*(floatLit: FloatLiteral): Literal =
  Literal(kind: lkFloat, floatLit: floatLit)

proc kind*(l: Literal): LiteralKind = l.kind

proc strLit*(l: Literal): StringLiteral =
  assert l.kind == lkString,
    fmt"Literal.strLit accessed but kind is {l.kind}"
  l.strLit

proc intLit*(l: Literal): IntegerLiteral =
  assert l.kind == lkInteger,
    fmt"Literal.intLit accessed but kind is {l.kind}"
  l.intLit

proc floatLit*(l: Literal): FloatLiteral =
  assert l.kind == lkFloat,
    fmt"Literal.floatLit accessed but kind is {l.kind}"
  l.floatLit

proc loc(literal: Literal): Location =
  case literal.kind:
  of lkString: literal.strLit.loc
  of lkInteger: literal.intLit.loc
  of lkFloat: literal.floatLit.loc

proc asl(literal: Literal): string =
  case literal.kind:
  of lkString: asl(literal.strLit)
  of lkInteger: asl(literal.intLit)
  of lkFloat: asl(literal.floatLit)

type Getter* = ref object
  source: Identifier
  property: Identifier
  loc: Location

proc newGetter*(source: Identifier, property: Identifier,
    loc: Location): Getter =
  Getter(source: source, property: property, loc: loc)

proc source*(g: Getter): Identifier = g.source
proc property*(g: Getter): Identifier = g.property
proc loc*(g: Getter): Location = g.loc

proc asl(getter: Getter): string =
  fmt"{asl(getter.source)}.{asl(getter.property)}"

type LiteralInitializer* = ref object
  typeName: Identifier
  value: Literal
  loc: Location

proc newLiteralInitializer*(typeName: Identifier, value: Literal,
    loc: Location): LiteralInitializer =
  LiteralInitializer(typeName: typeName, value: value, loc: loc)

proc asl(prim: LiteralInitializer): string =
  fmt"{asl(prim.typeName)} {asl(prim.value)}"

type VariantPatternField* = ref object
  name: Identifier
  binding: Identifier
  loc: Location

proc newVariantPatternField*(name: Identifier, binding: Identifier,
    loc: Location): VariantPatternField =
  VariantPatternField(name: name, binding: binding, loc: loc)

proc asl(field: VariantPatternField): string =
  fmt"{asl(field.name)}: {asl(field.binding)}"

type VariantPattern* = ref object
  variantName: Identifier
  fields: seq[VariantPatternField]
  loc: Location

proc newVariantPattern*(variantName: Identifier,
    fields: seq[VariantPatternField],
    loc: Location): Result[VariantPattern, ParserError] =
  var nameIndex: Table[Identifier, int]
  var bindingIndex: Table[Identifier, int]

  for index, field in fields:
    if field.name in nameIndex:
      let prev = fields[nameIndex[field.name]].name
      let msg = fmt"duplicate field encountered, see previous declaration at {prev.loc}"
      return err(newParserError(msg, field.name.loc))
    else:
      nameIndex[field.name] = index

    if field.binding in bindingIndex:
      let prev = fields[bindingIndex[field.binding]].binding
      let msg = fmt"duplicate binding encountered, see previous binding at {prev.loc}"
      return err(newParserError(msg, field.binding.loc))
    else:
      bindingIndex[field.binding] = index

  ok(VariantPattern(variantName: variantName, fields: fields, loc: loc))

proc loc*(vp: VariantPattern): Location = vp.loc

proc asl(variant: VariantPattern): string =
  result = fmt"{asl(variant.variantName)} " & "{"
  for i, field in variant.fields:
    if i > 0: result.add(", ")
    result.add(asl(field))
  result.add(" }")

type
  CasePatternKind* = enum
    cpkIntegerLiteral, cpkVariable, cpkVariant
  CasePattern* = ref object
    case kind: CasePatternKind
    of cpkIntegerLiteral: intLit: IntegerLiteral
    of cpkVariable: variable: Identifier
    of cpkVariant: variant: VariantPattern

proc newCasePattern*(intLit: IntegerLiteral): CasePattern =
  CasePattern(kind: cpkIntegerLiteral, intLit: intLit)

proc newCasePattern*(variable: Identifier): CasePattern =
  CasePattern(kind: cpkVariable, variable: variable)

proc newCasePattern*(variant: VariantPattern): CasePattern =
  CasePattern(kind: cpkVariant, variant: variant)

proc kind*(cp: CasePattern): CasePatternKind = cp.kind

proc intLit*(cp: CasePattern): IntegerLiteral =
  assert cp.kind == cpkIntegerLiteral,
    fmt"CasePattern.intLit accessed but kind is {cp.kind}"
  cp.intLit

proc variable*(cp: CasePattern): Identifier =
  assert cp.kind == cpkVariable,
    fmt"CasePattern.variable accessed but kind is {cp.kind}"
  cp.variable

proc variant*(cp: CasePattern): VariantPattern =
  assert cp.kind == cpkVariant,
    fmt"CasePattern.variant accessed but kind is {cp.kind}"
  cp.variant

proc asl(pattern: CasePattern): string =
  case pattern.kind:
  of cpkIntegerLiteral: asl(pattern.intLit)
  of cpkVariable: asl(pattern.variable)
  of cpkVariant: asl(pattern.variant)

type
  ArgumentList* = ref object
    args: seq[Expression]
    loc: Location

  FunctionCall* = ref object
    argType: ArgumentType
    name: Identifier
    argList: ArgumentList

  KeywordArgument* = ref object
    name: Identifier
    expression: Expression
    loc: Location

  KeywordArgumentList* = ref object
    args: seq[KeywordArgument]
    argIndex: Table[Identifier, int]
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
    case kind: InitializerKind
    of ikLiteral: literal: LiteralInitializer
    of ikStruct: struct: StructInitializer
    of ikUnion: union: UnionInitializer

  Assignment* = ref object
    target: Identifier
    expression: Expression
    loc: Location

  Mutation* = ref object
    target: Getter
    expression: Expression
    loc: Location

  CaseBlock* = ref object
    pattern: CasePattern
    body: StatementList
    loc: Location

  MatchExpression* = ref object
    subject: Expression
    cases: seq[CaseBlock]
    loc: Location

  ExpressionKind* = enum
    ekLiteral, ekFnCall, ekGetter, ekInitializer, ekVariable, ekMatch
  Expression* = ref object
    case kind: ExpressionKind
    of ekLiteral: literal: Literal
    of ekFnCall: fncall: FunctionCall
    of ekGetter: getter: Getter
    of ekInitializer: initializer: Initializer
    of ekVariable: variable: Identifier
    of ekMatch: match: MatchExpression

  StatementKind* = enum
    skAssignment, skExpr, skMutation
  Statement* = ref object
    case kind: StatementKind
    of skAssignment: assignment: Assignment
    of skExpr: expression: Expression
    of skMutation: mutation: Mutation

  StatementList* = ref object
    statements: seq[Statement]

# ------------------------------------------------------------
# Accessors for the variant + plain types declared in the block
# above. Kept private-fields + exported accessor procs throughout.
# ------------------------------------------------------------

proc asl(expr: Expression): string
proc asl(stmt: Statement): string
proc aslBlock(stmt: Statement, indentWidth: uint32): seq[string]

# ArgumentList
proc newArgumentList*(args: seq[Expression], loc: Location): ArgumentList =
  ArgumentList(args: args, loc: loc)

proc asl(argList: ArgumentList): string =
  result = "("
  for i, arg in argList.args:
    if i > 0: result.add(", ")
    result.add(asl(arg))
  result.add(")")

# FunctionCall
proc newFunctionCall*(argType: ArgumentType, name: Identifier,
    argList: ArgumentList): FunctionCall =
  FunctionCall(argType: argType, name: name, argList: argList)

proc loc*(fncall: FunctionCall): Location =
  fncall.argType.loc

proc argType*(fncall: FunctionCall): ArgumentType = fncall.argType
proc name*(fncall: FunctionCall): Identifier = fncall.name
proc args*(fncall: FunctionCall): seq[Expression] = fncall.argList.args

proc asl(fncall: FunctionCall): string =
  fmt"{asl(fncall.argType)}.{asl(fncall.name)}{asl(fncall.argList)}"

# KeywordArgument
proc newKeywordArgument*(name: Identifier, expression: Expression,
    loc: Location): KeywordArgument =
  KeywordArgument(name: name, expression: expression, loc: loc)

proc asl(kwarg: KeywordArgument): string =
  fmt"{asl(kwarg.name)}: {asl(kwarg.expression)}"

# KeywordArgumentList
proc newKeywordArgumentList*(args: seq[KeywordArgument], loc: Location): Result[KeywordArgumentList, ParserError] =
  if args.len == 0:
    let msg = "keyword argument list must contain at least 1 field"
    return err(newParserError(msg, loc))

  var argIndex: Table[Identifier, int]
  for index, arg in args:
    if arg.name in argIndex:
      let prev = args[argIndex[arg.name]]
      let msg = fmt"duplicate field encountered, see previous assignment at {prev.loc}"
      return err(newParserError(msg, arg.loc))
    argIndex[arg.name] = index
  ok(KeywordArgumentList(args: args, argIndex: argIndex, loc: loc))

proc asl(kwargList: KeywordArgumentList): string =
  result = "{ "
  for i, arg in kwargList.args:
    if i > 0: result.add(", ")
    result.add(asl(arg))
  result.add(" }")

# StructInitializer
proc newStructInitializer*(argType: ArgumentType, kwargList: KeywordArgumentList, loc: Location): StructInitializer =
  StructInitializer(argType: argType, kwargList: kwargList, loc: loc)

proc asl(nonPrim: StructInitializer): string =
  fmt"{asl(nonPrim.argType)} {asl(nonPrim.kwargList)}"

# UnionInitializer
proc newUnionInitializer*(argType: ArgumentType, variantName: Identifier,
    kwargList: KeywordArgumentList, loc: Location): UnionInitializer =
  UnionInitializer(argType: argType, variantName: variantName,
    kwargList: kwargList, loc: loc)

proc asl(unionInit: UnionInitializer): string =
  fmt"{asl(unionInit.argType)}.{asl(unionInit.variantName)} {asl(unionInit.kwargList)}"

# Initializer
proc newInitializer*(literal: LiteralInitializer): Initializer =
  Initializer(kind: ikLiteral, literal: literal)

proc newInitializer*(struct: StructInitializer): Initializer =
  Initializer(kind: ikStruct, struct: struct)

proc newInitializer*(union: UnionInitializer): Initializer =
  Initializer(kind: ikUnion, union: union)

proc kind*(i: Initializer): InitializerKind = i.kind

proc literal*(i: Initializer): LiteralInitializer =
  assert i.kind == ikLiteral,
    fmt"Initializer.literal accessed but kind is {i.kind}"
  i.literal

proc struct*(i: Initializer): StructInitializer =
  assert i.kind == ikStruct,
    fmt"Initializer.struct accessed but kind is {i.kind}"
  i.struct

proc union*(i: Initializer): UnionInitializer =
  assert i.kind == ikUnion,
    fmt"Initializer.union accessed but kind is {i.kind}"
  i.union

proc loc(initializer: Initializer): Location =
  case initializer.kind:
  of ikLiteral: initializer.literal.loc
  of ikStruct: initializer.struct.loc
  of ikUnion: initializer.union.loc

proc asl(initializer: Initializer): string =
  case initializer.kind:
  of ikLiteral: asl(initializer.literal)
  of ikStruct: asl(initializer.struct)
  of ikUnion: asl(initializer.union)

# Assignment
proc newAssignment*(target: Identifier, expression: Expression,
    loc: Location): Assignment =
  Assignment(target: target, expression: expression, loc: loc)

proc loc*(assignment: Assignment): Location = assignment.target.loc
proc target*(assignment: Assignment): Identifier = assignment.target
proc expression*(assignment: Assignment): Expression = assignment.expression

proc asl(assignment: Assignment): string =
  fmt"{asl(assignment.target)} = {asl(assignment.expression)}"

# Mutation
proc newMutation*(target: Getter, expression: Expression,
    loc: Location): Mutation =
  Mutation(target: target, expression: expression, loc: loc)

proc target*(mutation: Mutation): Getter = mutation.target
proc expression*(mutation: Mutation): Expression = mutation.expression
proc loc*(mutation: Mutation): Location = mutation.loc

proc asl(mutation: Mutation): string =
  fmt"{asl(mutation.target)} = {asl(mutation.expression)}"

# CaseBlock
proc newCaseBlock*(pattern: CasePattern, body: StatementList,
    loc: Location): CaseBlock =
  CaseBlock(pattern: pattern, body: body, loc: loc)

proc asl(caseBlock: CaseBlock, indentWidth: uint32): seq[string] =
  result.add(fmt"case {asl(caseBlock.pattern)}:")
  let indent = " ".repeat(indentWidth)
  for s in caseBlock.body.statements:
    for line in aslBlock(s, indentWidth):
      result.add(fmt"{indent}{line}")

# MatchExpression
proc newMatchExpression*(subject: Expression, cases: seq[CaseBlock],
    loc: Location): MatchExpression =
  MatchExpression(subject: subject, cases: cases, loc: loc)

proc asl(matchExpr: MatchExpression, indentWidth: uint32): seq[string] =
  result.add(fmt"match {asl(matchExpr.subject)}:")
  let indent = " ".repeat(indentWidth)
  for cb in matchExpr.cases:
    for line in asl(cb, indentWidth):
      result.add(fmt"{indent}{line}")

# Expression
proc newExpression*(literal: Literal): Expression =
  Expression(kind: ekLiteral, literal: literal)

proc newExpression*(fncall: FunctionCall): Expression =
  Expression(kind: ekFnCall, fncall: fncall)

proc newExpression*(getter: Getter): Expression =
  Expression(kind: ekGetter, getter: getter)

proc newExpression*(initializer: Initializer): Expression =
  Expression(kind: ekInitializer, initializer: initializer)

proc newExpression*(variable: Identifier): Expression =
  Expression(kind: ekVariable, variable: variable)

proc newExpression*(match: MatchExpression): Expression =
  Expression(kind: ekMatch, match: match)

proc kind*(e: Expression): ExpressionKind = e.kind

proc literal*(e: Expression): Literal =
  assert e.kind == ekLiteral,
    fmt"Expression.literal accessed but kind is {e.kind}"
  e.literal

proc fncall*(e: Expression): FunctionCall =
  assert e.kind == ekFnCall,
    fmt"Expression.fncall accessed but kind is {e.kind}"
  e.fncall

proc getter*(e: Expression): Getter =
  assert e.kind == ekGetter,
    fmt"Expression.getter accessed but kind is {e.kind}"
  e.getter

proc initializer*(e: Expression): Initializer =
  assert e.kind == ekInitializer,
    fmt"Expression.initializer accessed but kind is {e.kind}"
  e.initializer

proc variable*(e: Expression): Identifier =
  assert e.kind == ekVariable,
    fmt"Expression.variable accessed but kind is {e.kind}"
  e.variable

proc match*(e: Expression): MatchExpression =
  assert e.kind == ekMatch,
    fmt"Expression.match accessed but kind is {e.kind}"
  e.match

proc loc*(expression: Expression): Location =
  case expression.kind:
  of ekFnCall: expression.fncall.loc
  of ekGetter: expression.getter.loc
  of ekInitializer: expression.initializer.loc
  of ekLiteral: expression.literal.loc
  of ekMatch: expression.match.loc
  of ekVariable: expression.variable.loc

proc asl(expr: Expression): string =
  case expr.kind:
  of ekLiteral: asl(expr.literal)
  of ekFnCall: asl(expr.fncall)
  of ekGetter: asl(expr.getter)
  of ekInitializer: asl(expr.initializer)
  of ekVariable: asl(expr.variable)
  of ekMatch: "" # match is a block expression, use aslBlock

# Statement
proc newStatement*(assignment: Assignment): Statement =
  Statement(kind: skAssignment, assignment: assignment)

proc newStatement*(expression: Expression): Statement =
  Statement(kind: skExpr, expression: expression)

proc newStatement*(mutation: Mutation): Statement =
  Statement(kind: skMutation, mutation: mutation)

proc kind*(s: Statement): StatementKind = s.kind

proc assignment*(s: Statement): Assignment =
  assert s.kind == skAssignment,
    fmt"Statement.assignment accessed but kind is {s.kind}"
  s.assignment

proc expression*(s: Statement): Expression =
  assert s.kind == skExpr,
    fmt"Statement.expression accessed but kind is {s.kind}"
  s.expression

proc mutation*(s: Statement): Mutation =
  assert s.kind == skMutation,
    fmt"Statement.mutation accessed but kind is {s.kind}"
  s.mutation

proc loc*(statement: Statement): Location =
  case statement.kind:
  of skAssignment: statement.assignment.loc
  of skExpr: statement.expression.loc
  of skMutation: statement.mutation.loc

proc isBlockStatement(stmt: Statement): bool =
  case stmt.kind:
  of skExpr: stmt.expression.kind == ekMatch
  of skAssignment:
    stmt.assignment.expression.kind == ekMatch
  of skMutation: false

proc asl(stmt: Statement): string =
  case stmt.kind:
  of skAssignment: asl(stmt.assignment)
  of skMutation: asl(stmt.mutation)
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
  of skMutation:
    result = @[asl(stmt.mutation)]

# StatementList
proc newStatementList*(statements: seq[Statement]): StatementList =
  StatementList(statements: statements)

type UserFunction* = ref object
  decorators: seq[Decorator]
  def: FunctionDefinition
  statementList: StatementList

proc newUserFunction*(decorators: seq[Decorator], def: FunctionDefinition,
    statementList: StatementList): UserFunction =
  UserFunction(decorators: decorators, def: def, statementList: statementList)

proc loc*(fn: UserFunction): Location = fn.def.loc
proc name*(fn: UserFunction): Identifier = fn.def.name
proc def*(fn: UserFunction): FunctionDefinition = fn.def
proc statements*(fn: UserFunction): seq[Statement] = fn.statementList.statements
proc decorators*(fn: UserFunction): seq[Decorator] = fn.decorators
proc arity*(fn: UserFunction): int = fn.def.arity

proc asl(fn: UserFunction, indentWidth: uint32): seq[string] =
  for d in fn.decorators:
    result.add(asl(d))
  result.add(asl(fn.def))
  let indent = " ".repeat(indentWidth)
  for stmt in fn.statementList.statements:
    for line in aslBlock(stmt, indentWidth):
      result.add(fmt"{indent}{line}")

type ExternFunction* = ref object
  ffi: string
  def: FunctionDefinition
  loc: Location

proc ffi*(fn: ExternFunction): string = fn.ffi
proc name*(fn: ExternFunction): Identifier = fn.def.name
proc def*(fn: ExternFunction): FunctionDefinition = fn.def
proc arity*(fn: ExternFunction): int = fn.def.arity
proc loc*(fn: ExternFunction): Location = fn.loc

proc newExternFunction*(ffi: string, def: FunctionDefinition,
    loc: Location): ExternFunction =
  ExternFunction(ffi: ffi, def: def, loc: loc)

proc asl(fn: ExternFunction, indentWidth: uint32): seq[string] =
  result.add(fmt"@extern(""{fn.ffi}"")")
  result.add(asl(fn.def))

type
  FunctionKind* = enum
    fkUser, fkExtern
  Function* = ref object
    case kind: FunctionKind
    of fkUser: user: UserFunction
    of fkExtern: extern: ExternFunction

proc newFunction*(user: UserFunction): Function =
  Function(kind: fkUser, user: user)

proc newFunction*(extern: ExternFunction): Function =
  Function(kind: fkExtern, extern: extern)

proc kind*(fn: Function): FunctionKind = fn.kind

proc user*(fn: Function): UserFunction =
  assert fn.kind == fkUser,
    fmt"Function.user accessed but kind is {fn.kind}"
  fn.user

proc extern*(fn: Function): ExternFunction =
  assert fn.kind == fkExtern,
    fmt"Function.extern accessed but kind is {fn.kind}"
  fn.extern

proc loc*(fn: Function): Location =
  case fn.kind:
  of fkUser: fn.user.loc
  of fkExtern: fn.extern.loc

proc name*(fn: Function): Identifier =
  case fn.kind:
  of fkUser: fn.user.name
  of fkExtern: fn.extern.name

proc def*(fn: Function): FunctionDefinition =
  case fn.kind:
  of fkUser: fn.user.def
  of fkExtern: fn.extern.def

proc arity*(fn: Function): int =
  case fn.kind:
  of fkUser: fn.user.arity
  of fkExtern: fn.extern.arity

proc asl(fn: Function, indentWidth: uint32): seq[string] =
  case fn.kind:
  of fkUser: asl(fn.user, indentWidth)
  of fkExtern: asl(fn.extern, indentWidth)

type FunctionList* = ref object
  functions: seq[Function]
  functionIndex: Table[Identifier, Table[int, seq[int]]]

proc newFunctionList*(functions: seq[Function]): Result[FunctionList, ParserError] =
  var functionIndex: Table[Identifier, Table[int, seq[int]]]
  # TODO: ensure that there no duplicate function signatures
  for index, function in functions:
    if function.name notin functionIndex:
      functionIndex[function.name] = initTable[int, seq[int]]()
    if function.arity notin functionIndex[function.name]:
      functionIndex[function.name][function.arity] = newSeq[int]()
    functionIndex[function.name][function.arity].add(index)
  ok(FunctionList(functions: functions, functionIndex: functionIndex))

proc len(fnlist: FunctionList): int = fnlist.functions.len

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

proc asl(importedType: ImportedType): string =
  if importedType.alias.isSome:
    fmt"{asl(importedType.name)} as {asl(importedType.alias.get)}"
  else:
    asl(importedType.name)

type Import* = ref object
  names: seq[ImportedType]
  source: string
  path: string # absolute path of the imported file; set during BFS in parse*
  loc: Location

proc newImport*(names: seq[ImportedType], source: string, path: string,
    loc: Location): Result[Import, ParserError] =
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

  ok(Import(names: names, source: source, path: path, loc: loc))

proc names*(imp: Import): seq[ImportedType] = imp.names
proc source*(imp: Import): string = imp.source
proc path*(imp: Import): string = imp.path
proc loc*(imp: Import): Location = imp.loc

proc asl(imp: Import): string =
  result = "import { "
  for i, name in imp.names:
    if i > 0: result.add(", ")
    result.add(asl(name))
  result.add(fmt" }} from ""{imp.source}""")

type Generic* = ref object
  decorators: seq[Decorator]
  public: bool
  name: Identifier
  funcDefs: seq[FunctionDefinition]
  funcDefArityIndex: Table[Identifier, Table[int, seq[int]]]
  funcDefIndex: Table[string, seq[int]]
  loc: Location

proc public*(g: Generic): bool = g.public
proc name*(g: Generic): Identifier = g.name
proc funcDefs*(g: Generic): seq[FunctionDefinition] = g.funcDefs
proc decorators*(g: Generic): seq[Decorator] = g.decorators
proc loc*(g: Generic): Location = g.loc
proc `==`*(a, b: Generic): bool = a.loc == b.loc

proc newGeneric*(decorators: seq[Decorator], public: bool, name: Identifier,
    funcDefs: seq[FunctionDefinition], loc: Location): Result[Generic, ParserError] =
  var funcDefArityIndex: Table[Identifier, Table[int, seq[int]]]
  var funcDefIndex: Table[string, seq[int]]
  for index, def in funcDefs:
    if def.name notin funcDefArityIndex:
      funcDefArityIndex[def.name] = initTable[int, seq[int]]()
    if def.arity notin funcDefArityIndex[def.name]:
      funcDefArityIndex[def.name][def.arity] = newSeq[int]()
    funcDefArityIndex[def.name][def.arity].add(index)
    funcDefIndex.mgetOrPut(def.name.value, @[]).add(index)
  ok(Generic(decorators: decorators, public: public, name: name, funcDefs: funcDefs,
      funcDefArityIndex: funcDefArityIndex, funcDefIndex: funcDefIndex, loc: loc))

proc asl(gen: Generic, indentWidth: uint32): seq[string] =
  for d in gen.decorators:
    result.add(asl(d))
  let prefix = if gen.public: "public generic" else: "generic"
  result.add(fmt"{prefix} {asl(gen.name)}:")
  let indent = " ".repeat(indentWidth)
  for funcDef in gen.funcDefs:
    result.add(fmt"{indent}{asl(funcDef)}")

proc findFunctionDefIds(generic: Generic, name: Identifier, arity: int): Result[seq[int], string] =
  if name notin generic.funcDefArityIndex:
    err(fmt"{name.loc} function `{name.asl}` does not exist in generic")
  elif arity notin generic.funcDefArityIndex[name]:
    err(fmt"{name.loc} function `{name.asl}` with arity `{arity}` does not exist in generic")
  else:
    ok(generic.funcDefArityIndex[name][arity])

proc findFunctionDefs*(generic: Generic, name: Identifier, arity: int): Result[seq[FunctionDefinition], string] =
  let funcIds = ? generic.findFunctionDefIds(name, arity)
  var funcs: seq[FunctionDefinition]
  for id in funcIds:
    funcs.add(generic.funcDefs[id])
  ok(funcs)

type Requires* = ref object
  generics: seq[Identifier]
  loc: Location

proc generics*(r: Requires): seq[Identifier] = r.generics
proc loc*(r: Requires): Location = r.loc

proc newRequires*(generics: seq[Identifier], loc: Location): Requires =
  Requires(generics: generics, loc: loc)

proc asl(r: Requires): string =
  result = "requires("
  for i, g in r.generics:
    if i > 0: result.add(", ")
    result.add(asl(g))
  result.add(")")

type Module* = ref object
  decorators: seq[Decorator]
  public: bool
  name: Identifier
  requires: Option[Requires]
  data: Option[DataBlock]
  funcList: FunctionList
  functionIndex: Table[Identifier, Table[int, seq[int]]]
  loc: Location

proc public*(m: Module): bool = m.public
proc name*(m: Module): Identifier = m.name
proc requires*(m: Module): Option[Requires] = m.requires
proc data*(m: Module): Option[DataBlock] = m.data
proc functions*(m: Module): seq[Function] = m.funcList.functions
proc decorators*(m: Module): seq[Decorator] = m.decorators
proc loc*(m: Module): Location = m.loc

proc newModule*(decorators: seq[Decorator], public: bool, name: Identifier,
    requires: Option[Requires], data: Option[DataBlock],
    funcList: FunctionList, loc: Location): Result[Module, ParserError] =
  if data.isNone and funcList.len == 0:
    let msg = "module must have at least 1 struct/union/function block"
    return err(newParserError(msg, loc))
  var functionIndex: Table[Identifier, Table[int, seq[int]]]
  for i, fn in funcList.functions:
    if fn.name notin functionIndex:
      functionIndex[fn.name] = initTable[int, seq[int]]()
    if fn.arity notin functionIndex[fn.name]:
      functionIndex[fn.name][fn.arity] = newSeq[int]()
    functionIndex[fn.name][fn.arity].add(i)

  ok(Module(decorators: decorators, public: public, name: name,
      requires: requires, data: data, funcList: funcList,
      functionIndex: functionIndex, loc: loc))

proc asl(module: Module, indentWidth: uint32): seq[string] =
  for d in module.decorators:
    result.add(asl(d))
  let prefix = if module.public: "public module" else: "module"
  result.add(fmt"{prefix} {asl(module.name)}:")
  let indent = " ".repeat(indentWidth)
  if module.requires.isSome:
    result.add(fmt"{indent}{asl(module.requires.get)}")
    result.add("")
  if module.data.isSome:
    for line in asl(module.data.get, indentWidth):
      result.add(fmt"{indent}{line}")
    result.add("")
  for i, fn in module.funcList.functions:
    if i > 0: result.add("")
    for line in asl(fn, indentWidth):
      result.add(fmt"{indent}{line}")

proc findFunctionIds(module: Module, name: Identifier, arity: int): Result[seq[int], string] =
  if name notin module.functionIndex:
    err(fmt"{name.loc} module `{module.name.asl}` does not have function `{name.asl}`")
  elif arity notin module.functionIndex[name]:
    err(fmt"{name.loc} module `{module.name.asl}` does not have function `{name.asl}` with arity `{arity}`")
  else:
    ok(module.functionIndex[name][arity])

proc findFunctions*(module: Module, name: Identifier, arity: int): Result[seq[Function], string] =
  let funcDefIds = ? module.findFunctionIds(name, arity)
  var funcDefs: seq[Function]
  for id in funcDefIds:
    funcDefs.add(module.functions[id])
  ok(funcDefs)

type
  DefinedTypeKind* = enum
    dtkModule, dtkGeneric
  DefinedType* = ref object
    case kind: DefinedTypeKind
    of dtkModule: module: Module
    of dtkGeneric: generic: Generic

proc newDefinedType*(module: Module): DefinedType =
  DefinedType(kind: dtkModule, module: module)

proc newDefinedType*(generic: Generic): DefinedType =
  DefinedType(kind: dtkGeneric, generic: generic)

proc kind*(dt: DefinedType): DefinedTypeKind = dt.kind

proc module*(dt: DefinedType): Module =
  assert dt.kind == dtkModule,
    fmt"DefinedType.module accessed but kind is {dt.kind}"
  dt.module

proc generic*(dt: DefinedType): Generic =
  assert dt.kind == dtkGeneric,
    fmt"DefinedType.generic accessed but kind is {dt.kind}"
  dt.generic

proc name*(definedType: DefinedType): Identifier =
  case definedType.kind:
  of dtkModule: definedType.module.name
  of dtkGeneric: definedType.generic.name

proc loc*(definedType: DefinedType): Location =
  case definedType.kind:
  of dtkModule: definedType.module.loc
  of dtkGeneric: definedType.generic.loc

type
  TypeKind* = enum
    tkImported, tkDefined
  Type* = ref object
    case kind: TypeKind
    of tkImported: imported: ImportedType
    of tkDefined: definedType: DefinedType

proc newType(imported: ImportedType): Type =
  Type(kind: tkImported, imported: imported)

proc newType(definedType: DefinedType): Type =
  Type(kind: tkDefined, definedType: definedType)

proc kind*(typ: Type): TypeKind = typ.kind

proc imported*(typ: Type): ImportedType =
  assert typ.kind == tkImported,
    fmt"Type.imported accessed but kind is {typ.kind}"
  typ.imported

proc definedType*(typ: Type): DefinedType =
  assert typ.kind == tkDefined,
    fmt"Type.definedType accessed but kind is {typ.kind}"
  typ.definedType

proc loc*(typ: Type): Location =
  case typ.kind:
  of tkImported: typ.imported.loc
  of tkDefined: typ.definedType.loc

type File* = ref object
  path: string
  imports: seq[Import]
  definedTypes: seq[DefinedType]
  types: seq[Type]
  typeIndex: Table[Identifier, int]

proc newFile*(path: string, imports: seq[Import], definedTypes: seq[DefinedType]): Result[
    File, ParserError] =
  # TODO: Ensure that same file is not used in multiple import statements
  # var importedFileSet: Hashset[string]
  # for imp in imports:
  #   if imp.path in importedFileSet:
  #     return err(newParserError("", imp.loc))
  #   importedFileSet.incl(imp.path)

  var typeIndex: Table[Identifier, int]
  var types: seq[Type]

  for imp in imports:
    if imp.path == path:
      let msg = "importing the source file in itself is disallowed"
      return err(newParserError(msg, imp.loc))
    for impType in imp.names:
      if impType.binding in typeIndex:
        let prev = types[typeIndex[impType.binding]]
        let msg = fmt"duplicate type declaration encountered, see previous declaration at {prev.loc}"
        return err(newParserError(msg, impType.loc))
      typeIndex[impType.binding] = types.len
      types.add(newType(impType))

  for definedType in definedTypes:
    if definedType.name in typeIndex:
      let prev = types[typeIndex[definedType.name]]
      let msg = fmt"duplicate type declaration encountered, see previous declaration at {prev.loc}"
      return err(newParserError(msg, definedType.loc))
    else:
      typeIndex[definedType.name] = types.len
      types.add(newType(definedType))
  ok(File(path: path, imports: imports, definedTypes: definedTypes, types: types, typeIndex: typeIndex))

proc path*(file: File): string = file.path
proc imports*(file: File): seq[Import] = file.imports
proc definedTypes*(file: File): seq[DefinedType] = file.definedTypes
proc types*(file: File): seq[Type] = file.types

proc asl*(file: File, indentWidth: uint32): string =
  var lines: seq[string]
  for imp in file.imports:
    lines.add(asl(imp))
  if file.imports.len > 0 and file.definedTypes.len > 0:
    lines.add("")
  for i, dt in file.definedTypes:
    if i > 0: lines.add("")
    case dt.kind:
    of dtkModule:
      for line in asl(dt.module, indentWidth):
        lines.add(line)
    of dtkGeneric:
      for line in asl(dt.generic, indentWidth):
        lines.add(line)
  lines.join("\n") & "\n"

proc findType*(file: File, name: Identifier): Result[Type, string] =
  if name in file.typeIndex: ok(file.types[file.typeIndex[name]])
  else: err(fmt"{file.path}:{name.loc} type `{name.asl}` does not exist in the scope")

# ============================================================
# App
# ============================================================

type App* = ref object
  files: seq[File]
  fileIndex: Table[string, int] # absolute path -> index in files

proc newApp*(files: seq[File]): App =
  var fileIndex: Table[string, int]
  for i, f in files:
    fileIndex[f.path] = i
  App(files: files, fileIndex: fileIndex)

proc files*(app: App): seq[File] = app.files

# ============================================================
# Lookup procs
# ============================================================

proc findFileId*(app: App, path: string): Result[int, string] =
  if path in app.fileIndex: ok(app.fileIndex[path])
  else: err(fmt"file '{path}' does not exists")

proc findFile*(app: App, path: string): Result[File, string] =
  let id = ? app.findFileId(path)
  ok(app.files[id])
