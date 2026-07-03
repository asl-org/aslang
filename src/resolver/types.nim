## Consolidated resolver type declarations + field-touching primitives.
##
## Nim requires mutually-recursive `ref object` types to live in a
## single `type:` block — the resolver cycle rooted at
## `ResolvedArgumentType` reaches through Module/Function/Statement
## back to itself and cannot be split across modules. This file
## collects every type in that cycle plus every constructor and
## direct-field accessor. Everything that touches a private field
## lives here so per-concept files (argtypes.nim, funcdefs.nim, …)
## don't need to break the private-field discipline; those files own
## the `resolve*` procs and any computed helpers that operate through
## the accessors.
##
## `ResolvedCasePattern` is intentionally NOT here — it holds only
## parser AST types and therefore breaks no cycle. It lives in
## `patterns.nim` and is imported here.

import options, tables, sets, hashes, strformat

import tokenizer
import parser
import patterns

# FileScope alias — keyed by binding (alias-or-name); shared by
# every resolver file that walks bodies.
type FileScope* = Table[Identifier, DefinedType]

# FunctionScope alias — names of variables currently in scope inside
# a function body.
type FunctionScope* = HashSet[Identifier]

type
  # ==== Literal-def discriminator ====

  ResolvedLiteralDef* = enum
    rltkU8, rltkU16, rltkU32, rltkU64
    rltkI8, rltkI16, rltkI32, rltkI64
    rltkF32, rltkF64, rltkString, rltkPointer

  # ==== Argument-type cluster (grammar `ArgumentType`) ====
  #
  # `resolvedModule` — resolver-level back-ref to the ResolvedModule
  # (task 6c). The two-pass resolver creates a shell ResolvedModule
  # for every parser Module up-front so this reference is well-formed
  # before argument-type resolution runs; the shell is populated with
  # requires/data/functions/... in the define pass. Consumers that
  # need the parser Module read it via `resolvedModule.parsed`.
  #
  # `ResolvedGenericArgumentType.generic` stays a parser Generic —
  # task 6c is scoped to the module edge; the generic edge is a
  # follow-up (see tasks.md).

  ResolvedModuleArgumentType* = ref object
    resolvedModule: ResolvedModule
    impls: seq[ResolvedArgumentType]
    loc: Location

  ResolvedGenericArgumentType* = ref object
    generic: Generic
    loc: Location

  ResolvedArgumentTypeKind* = enum
    ratkModule, ratkGeneric

  ResolvedArgumentType* = ref object
    case kind: ResolvedArgumentTypeKind
    of ratkModule: module: ResolvedModuleArgumentType
    of ratkGeneric: generic: ResolvedGenericArgumentType

  # ==== Function-definition shape ====

  ResolvedArgumentDefinition* = ref object
    parsed: ArgumentDefinition
    argType: ResolvedArgumentType

  ResolvedFunctionDefinition* = ref object
    parsed: FunctionDefinition
    args: seq[ResolvedArgumentDefinition]
    returns: ResolvedArgumentType

  ResolvedExternFunction* = ref object
    parsed: ExternFunction
    def: ResolvedFunctionDefinition

  # ==== Data-block shapes ====

  ResolvedStructDef* = ref object
    parsed: StructDef
    fields: seq[ResolvedArgumentDefinition]
    fieldIndex: Table[Identifier, int]
    genericTypeIndex: Table[ResolvedGenericArgumentType, int]

  ResolvedVariant* = ref object
    parsed: VariantDefinition
    fields: seq[ResolvedArgumentDefinition]
    fieldIndex: Table[Identifier, int]

  ResolvedUnionDef* = ref object
    parsed: UnionDef
    variants: seq[ResolvedVariant]
    variantIndex: Table[Identifier, int]
    genericTypeIndex: Table[ResolvedGenericArgumentType, int]

  ResolvedDataKind* = enum
    rdkLiteral, rdkStruct, rdkUnion

  ResolvedData* = ref object
    case kind: ResolvedDataKind
    of rdkLiteral: literal: ResolvedLiteralDef
    of rdkStruct: struct: ResolvedStructDef
    of rdkUnion: union: ResolvedUnionDef

  # ==== Body-level cluster ====

  ResolvedGetter* = ref object
    parsed: Getter

  ResolvedLiteralInitializer* = ref object
    parsed: LiteralInitializer
    argType: ResolvedArgumentType

  ResolvedKeywordArgument* = ref object
    parsed: KeywordArgument
    expression: ResolvedExpression

  ResolvedStructRefKind* = enum
    rsrkDefault, rsrkImpl
  ResolvedStructRef* = ref object
    parsed: StructRef
    case kind: ResolvedStructRefKind
    of rsrkDefault: module: Module
    of rsrkImpl: argType: ResolvedArgumentType

  ResolvedUnionRefKind* = enum
    rurkDefault, rurkImpl
  ResolvedUnionRef* = ref object
    parsed: UnionRef
    case kind: ResolvedUnionRefKind
    of rurkDefault: module: Module
    of rurkImpl: argType: ResolvedArgumentType

  ResolvedStructInitializer* = ref object
    parsed: StructInitializer
    structRef: ResolvedStructRef
    kwargs: seq[ResolvedKeywordArgument]

  ResolvedUnionInitializer* = ref object
    parsed: UnionInitializer
    unionRef: ResolvedUnionRef
    kwargs: seq[ResolvedKeywordArgument]

  ResolvedInitializerKind* = enum
    rikStruct, rikUnion, rikLiteral
  ResolvedInitializer* = ref object
    case kind: ResolvedInitializerKind
    of rikStruct: struct: ResolvedStructInitializer
    of rikUnion: union: ResolvedUnionInitializer
    of rikLiteral: literal: ResolvedLiteralInitializer

  ResolvedFunctionCall* = ref object
    parsed: FunctionCall
    args: seq[ResolvedExpression]

  ResolvedAssignment* = ref object
    parsed: Assignment
    expression: ResolvedExpression

  ResolvedSetter* = ref object
    parsed: Setter
    getter: ResolvedGetter
    expression: ResolvedExpression

  ResolvedCaseBlock* = ref object
    parsed: CaseBlock
    pattern: ResolvedCasePattern
    statements: seq[ResolvedStatement]

  ResolvedMatchExpression* = ref object
    parsed: MatchExpression
    subject: ResolvedExpression
    cases: seq[ResolvedCaseBlock]

  ResolvedExpressionKind* = enum
    rekFunctionCall, rekVariable, rekLiteral, rekInitializer,
    rekGetter, rekMatchExpr
  ResolvedExpression* = ref object
    case kind: ResolvedExpressionKind
    of rekFunctionCall: fncall: ResolvedFunctionCall
    of rekVariable: variable: Identifier
    of rekLiteral: literal: Literal
    of rekInitializer: initializer: ResolvedInitializer
    of rekGetter: getter: ResolvedGetter
    of rekMatchExpr: match: ResolvedMatchExpression

  ResolvedStatementKind* = enum
    rskAssignment, rskExpr, rskSetter
  ResolvedStatement* = ref object
    case kind: ResolvedStatementKind
    of rskAssignment: assignment: ResolvedAssignment
    of rskExpr: expression: ResolvedExpression
    of rskSetter: setter: ResolvedSetter

  # ==== User function + tagged Function ====

  ResolvedUserFunction* = ref object
    parsed: UserFunction
    funcDef: ResolvedFunctionDefinition
    statements: seq[ResolvedStatement]

  ResolvedFunctionKind* = enum
    rfkExtern, rfkUser
  ResolvedFunction* = ref object
    case kind: ResolvedFunctionKind
    of rfkExtern: extern: ResolvedExternFunction
    of rfkUser: user: ResolvedUserFunction

  # ==== Module + Generic ====

  ResolvedModule* = ref object
    parsed: Module
    requires: seq[ResolvedGenericArgumentType]
    data: Option[ResolvedData]
    funcDefIndex: Table[ResolvedFunctionDefinition, int]
    funcNameArityIndex: Table[Identifier, Table[int, seq[int]]]
    functions: seq[ResolvedFunction]

  ResolvedGeneric* = ref object
    parsed: Generic
    funcDefs: seq[ResolvedFunctionDefinition]
    funcDefIndex: Table[ResolvedFunctionDefinition, int]
    funcNameArityIndex: Table[Identifier, Table[int, seq[int]]]

  # ==== DefinedType umbrella ====

  ResolvedDefinedTypeKind* = enum
    rdtkModule, rdtkGeneric
  ResolvedDefinedType* = ref object
    id: int
    case kind: ResolvedDefinedTypeKind
    of rdtkModule: module: ResolvedModule
    of rdtkGeneric: generic: ResolvedGeneric

# ============================================================================
# Constructors + accessors — every proc that touches a private field lives
# here so the field-privacy discipline is preserved for callers.
# ============================================================================

# ---- ResolvedGenericArgumentType ----

proc newResolvedGenericArgumentType*(generic: Generic, loc: Location): ResolvedGenericArgumentType =
  ResolvedGenericArgumentType(generic: generic, loc: loc)

proc parsed*(argType: ResolvedGenericArgumentType): Generic = argType.generic
proc name*(argType: ResolvedGenericArgumentType): Identifier = argType.generic.name
proc loc*(argType: ResolvedGenericArgumentType): Location = argType.loc
proc hash*(argType: ResolvedGenericArgumentType): Hash = argType.generic.hash
proc `==`*(a, b: ResolvedGenericArgumentType): bool = a.hash == b.hash
proc asl*(argType: ResolvedGenericArgumentType): string = argType.generic.name.asl

# ---- ResolvedModuleArgumentType ----

proc newResolvedModuleArgumentType*(resolvedModule: ResolvedModule, impls: seq[ResolvedArgumentType], loc: Location): ResolvedModuleArgumentType =
  ResolvedModuleArgumentType(loc: loc, resolvedModule: resolvedModule, impls: impls)

proc newResolvedModuleArgumentType*(resolvedModule: ResolvedModule, loc: Location): ResolvedModuleArgumentType =
  newResolvedModuleArgumentType(resolvedModule, @[], loc)

proc loc*(argType: ResolvedModuleArgumentType): Location = argType.loc
proc resolvedModule*(argType: ResolvedModuleArgumentType): ResolvedModule = argType.resolvedModule
proc impls*(argType: ResolvedModuleArgumentType): seq[ResolvedArgumentType] = argType.impls
proc parsed*(argType: ResolvedModuleArgumentType): Module = argType.resolvedModule.parsed
  ## Convenience: the parser Module that this argument type refers to.
  ## Reads through the resolvedModule shell — during the declare pass
  ## the shell's `parsed` field is always set, so this is safe even
  ## before the module has been populated.
proc name*(argType: ResolvedModuleArgumentType): Identifier = argType.resolvedModule.parsed.name
  ## Convenience: the parser Module's name. Same "always safe on the
  ## shell" argument as `parsed*` above.

# ---- ResolvedArgumentType (outer tagged union) ----

proc newResolvedArgumentType*(module: ResolvedModuleArgumentType): ResolvedArgumentType =
  ResolvedArgumentType(kind: ratkModule, module: module)

proc newResolvedArgumentType*(generic: ResolvedGenericArgumentType): ResolvedArgumentType =
  ResolvedArgumentType(kind: ratkGeneric, generic: generic)

proc kind*(argType: ResolvedArgumentType): ResolvedArgumentTypeKind = argType.kind

proc module*(argType: ResolvedArgumentType): ResolvedModuleArgumentType =
  assert argType.kind == ratkModule,
    fmt"ResolvedArgumentType.module accessed but kind is {argType.kind}"
  argType.module

proc generic*(argType: ResolvedArgumentType): ResolvedGenericArgumentType =
  assert argType.kind == ratkGeneric,
    fmt"ResolvedArgumentType.generic accessed but kind is {argType.kind}"
  argType.generic

# ---- ResolvedArgumentDefinition ----

proc newResolvedArgumentDefinition*(parsed: ArgumentDefinition,
    argType: ResolvedArgumentType): ResolvedArgumentDefinition =
  ResolvedArgumentDefinition(parsed: parsed, argType: argType)

proc parsed*(d: ResolvedArgumentDefinition): ArgumentDefinition = d.parsed
proc name*(d: ResolvedArgumentDefinition): Identifier = d.parsed.name
proc argType*(d: ResolvedArgumentDefinition): ResolvedArgumentType = d.argType

# ---- ResolvedFunctionDefinition ----

proc newResolvedFunctionDefinition*(parsed: FunctionDefinition,
    args: seq[ResolvedArgumentDefinition],
    returns: ResolvedArgumentType): ResolvedFunctionDefinition =
  ResolvedFunctionDefinition(parsed: parsed, args: args, returns: returns)

proc parsed*(funcDef: ResolvedFunctionDefinition): FunctionDefinition = funcDef.parsed
proc args*(funcDef: ResolvedFunctionDefinition): seq[ResolvedArgumentDefinition] = funcDef.args
proc returns*(funcDef: ResolvedFunctionDefinition): ResolvedArgumentType = funcDef.returns

# ---- ResolvedExternFunction ----

proc newResolvedExternFunction*(parsed: ExternFunction,
    def: ResolvedFunctionDefinition): ResolvedExternFunction =
  ResolvedExternFunction(parsed: parsed, def: def)

proc parsed*(function: ResolvedExternFunction): ExternFunction = function.parsed
proc def*(function: ResolvedExternFunction): ResolvedFunctionDefinition = function.def

# ---- ResolvedStructDef ----

proc newResolvedStructDef*(parsed: StructDef,
    fields: seq[ResolvedArgumentDefinition],
    genericTypeIndex: Table[ResolvedGenericArgumentType, int]): ResolvedStructDef =
  var fieldIndex: Table[Identifier, int]
  for id, field in fields:
    assert(field.name notin fieldIndex, "UNREACHABLE: duplicate field name — should have been caught in parser")
    fieldIndex[field.name] = id
  ResolvedStructDef(parsed: parsed, fields: fields, fieldIndex: fieldIndex, genericTypeIndex: genericTypeIndex)

proc parsed*(struct: ResolvedStructDef): StructDef = struct.parsed
proc fields*(struct: ResolvedStructDef): seq[ResolvedArgumentDefinition] = struct.fields
proc genericTypeIndex*(struct: ResolvedStructDef): Table[ResolvedGenericArgumentType, int] = struct.genericTypeIndex
proc fieldIndex*(struct: ResolvedStructDef): Table[Identifier, int] = struct.fieldIndex

# ---- ResolvedVariant ----

proc newResolvedVariant*(parsed: VariantDefinition,
    fields: seq[ResolvedArgumentDefinition]): ResolvedVariant =
  var fieldIndex: Table[Identifier, int]
  for id, field in fields:
    assert(field.name notin fieldIndex, "UNREACHABLE: duplicate field name — should have been caught in parser")
    fieldIndex[field.name] = id
  ResolvedVariant(parsed: parsed, fields: fields, fieldIndex: fieldIndex)

proc parsed*(variant: ResolvedVariant): VariantDefinition = variant.parsed
proc fields*(variant: ResolvedVariant): seq[ResolvedArgumentDefinition] = variant.fields
proc fieldIndex*(variant: ResolvedVariant): Table[Identifier, int] = variant.fieldIndex

# ---- ResolvedUnionDef ----

proc newResolvedUnionDef*(parsed: UnionDef, variants: seq[ResolvedVariant],
    genericTypeIndex: Table[ResolvedGenericArgumentType, int]): ResolvedUnionDef =
  var variantIndex: Table[Identifier, int]
  for id, variant in variants:
    assert(variant.parsed.name notin variantIndex, "UNREACHABLE: duplicate variant — should have been caught in parser")
    variantIndex[variant.parsed.name] = id
  ResolvedUnionDef(parsed: parsed, variants: variants, variantIndex: variantIndex, genericTypeIndex: genericTypeIndex)

proc parsed*(union: ResolvedUnionDef): UnionDef = union.parsed
proc variants*(union: ResolvedUnionDef): seq[ResolvedVariant] = union.variants
proc genericTypeIndex*(union: ResolvedUnionDef): Table[ResolvedGenericArgumentType, int] = union.genericTypeIndex
proc variantIndex*(union: ResolvedUnionDef): Table[Identifier, int] = union.variantIndex

# ---- ResolvedData ----

proc newResolvedData*(literal: ResolvedLiteralDef): ResolvedData =
  ResolvedData(kind: rdkLiteral, literal: literal)

proc newResolvedData*(struct: ResolvedStructDef): ResolvedData =
  ResolvedData(kind: rdkStruct, struct: struct)

proc newResolvedData*(union: ResolvedUnionDef): ResolvedData =
  ResolvedData(kind: rdkUnion, union: union)

proc kind*(data: ResolvedData): ResolvedDataKind = data.kind
proc literal*(data: ResolvedData): ResolvedLiteralDef =
  assert data.kind == rdkLiteral,
    fmt"ResolvedData.literal accessed but kind is {data.kind}"
  data.literal
proc struct*(data: ResolvedData): ResolvedStructDef =
  assert data.kind == rdkStruct,
    fmt"ResolvedData.struct accessed but kind is {data.kind}"
  data.struct
proc union*(data: ResolvedData): ResolvedUnionDef =
  assert data.kind == rdkUnion,
    fmt"ResolvedData.union accessed but kind is {data.kind}"
  data.union

# ---- ResolvedGetter ----

proc newResolvedGetter*(parsed: Getter): ResolvedGetter =
  ResolvedGetter(parsed: parsed)

proc parsed*(getter: ResolvedGetter): Getter = getter.parsed

# ---- ResolvedLiteralInitializer ----

proc newResolvedLiteralInitializer*(parsed: LiteralInitializer,
    argType: ResolvedArgumentType): ResolvedLiteralInitializer =
  ResolvedLiteralInitializer(parsed: parsed, argType: argType)

proc parsed*(init: ResolvedLiteralInitializer): LiteralInitializer = init.parsed
proc argType*(init: ResolvedLiteralInitializer): ResolvedArgumentType = init.argType

# ---- ResolvedKeywordArgument ----

proc newResolvedKeywordArgument*(parsed: KeywordArgument,
    expression: ResolvedExpression): ResolvedKeywordArgument =
  ResolvedKeywordArgument(parsed: parsed, expression: expression)

proc parsed*(kwarg: ResolvedKeywordArgument): KeywordArgument = kwarg.parsed
proc expression*(kwarg: ResolvedKeywordArgument): ResolvedExpression = kwarg.expression

# ---- ResolvedStructRef ----

proc newResolvedStructRef*(parsed: StructRef, module: Module): ResolvedStructRef =
  ## Default kind — carries the resolved receiver module (looked up from
  ## the file's typeIndex, handles local and imported alike).
  ResolvedStructRef(parsed: parsed, kind: rsrkDefault, module: module)

proc newResolvedStructRef*(parsed: StructRef, argType: ResolvedArgumentType): ResolvedStructRef =
  ## Impl kind — wraps the resolved argument type (root + impls). The
  ## resolved receiver module is reachable via argType.module.root.
  ResolvedStructRef(parsed: parsed, kind: rsrkImpl, argType: argType)

proc parsed*(s: ResolvedStructRef): StructRef = s.parsed
proc kind*(s: ResolvedStructRef): ResolvedStructRefKind = s.kind
proc module*(s: ResolvedStructRef): Module =
  ## Returns the resolved receiver parser Module. Default arm reads
  ## the stored field; impl arm walks through argType's
  ## resolvedModule.parsed.
  case s.kind:
  of rsrkDefault: s.module
  of rsrkImpl: s.argType.module.resolvedModule.parsed
proc argType*(s: ResolvedStructRef): ResolvedArgumentType =
  assert s.kind == rsrkImpl,
    fmt"ResolvedStructRef.argType accessed but kind is {s.kind}"
  s.argType

# ---- ResolvedStructInitializer ----

proc newResolvedStructInitializer*(parsed: StructInitializer,
    structRef: ResolvedStructRef,
    kwargs: seq[ResolvedKeywordArgument]): ResolvedStructInitializer =
  ResolvedStructInitializer(parsed: parsed, structRef: structRef, kwargs: kwargs)

proc parsed*(struct: ResolvedStructInitializer): StructInitializer = struct.parsed
proc structRef*(struct: ResolvedStructInitializer): ResolvedStructRef = struct.structRef
proc kwargs*(struct: ResolvedStructInitializer): seq[ResolvedKeywordArgument] = struct.kwargs

# ---- ResolvedUnionRef ----

proc newResolvedUnionRef*(parsed: UnionRef, module: Module): ResolvedUnionRef =
  ## Default kind — carries the resolved receiver module (looked up
  ## from the file's typeIndex, handles local and imported alike).
  ResolvedUnionRef(parsed: parsed, kind: rurkDefault, module: module)

proc newResolvedUnionRef*(parsed: UnionRef, argType: ResolvedArgumentType): ResolvedUnionRef =
  ## Impl kind — wraps the resolved argument type (root + impls). The
  ## resolved receiver module is reachable via argType.module.root.
  ResolvedUnionRef(parsed: parsed, kind: rurkImpl, argType: argType)

proc parsed*(u: ResolvedUnionRef): UnionRef = u.parsed
proc kind*(u: ResolvedUnionRef): ResolvedUnionRefKind = u.kind
proc module*(u: ResolvedUnionRef): Module =
  ## Returns the resolved receiver parser Module. Default arm reads
  ## the stored field; impl arm walks through argType's
  ## resolvedModule.parsed.
  case u.kind:
  of rurkDefault: u.module
  of rurkImpl: u.argType.module.resolvedModule.parsed
proc argType*(u: ResolvedUnionRef): ResolvedArgumentType =
  assert u.kind == rurkImpl,
    fmt"ResolvedUnionRef.argType accessed but kind is {u.kind}"
  u.argType

# ---- ResolvedUnionInitializer ----

proc newResolvedUnionInitializer*(parsed: UnionInitializer,
    unionRef: ResolvedUnionRef,
    kwargs: seq[ResolvedKeywordArgument]): ResolvedUnionInitializer =
  ResolvedUnionInitializer(parsed: parsed, unionRef: unionRef, kwargs: kwargs)

proc parsed*(init: ResolvedUnionInitializer): UnionInitializer = init.parsed
proc unionRef*(init: ResolvedUnionInitializer): ResolvedUnionRef = init.unionRef
proc kwargs*(init: ResolvedUnionInitializer): seq[ResolvedKeywordArgument] = init.kwargs

# ---- ResolvedInitializer ----

proc newResolvedInitializer*(struct: ResolvedStructInitializer): ResolvedInitializer =
  ResolvedInitializer(kind: rikStruct, struct: struct)

proc newResolvedInitializer*(union: ResolvedUnionInitializer): ResolvedInitializer =
  ResolvedInitializer(kind: rikUnion, union: union)

proc newResolvedInitializer*(literal: ResolvedLiteralInitializer): ResolvedInitializer =
  ResolvedInitializer(kind: rikLiteral, literal: literal)

proc kind*(init: ResolvedInitializer): ResolvedInitializerKind = init.kind
proc literal*(init: ResolvedInitializer): ResolvedLiteralInitializer =
  assert init.kind == rikLiteral,
    fmt"ResolvedInitializer.literal accessed but kind is {init.kind}"
  init.literal
proc union*(init: ResolvedInitializer): ResolvedUnionInitializer =
  assert init.kind == rikUnion,
    fmt"ResolvedInitializer.union accessed but kind is {init.kind}"
  init.union
proc struct*(init: ResolvedInitializer): ResolvedStructInitializer =
  assert init.kind == rikStruct,
    fmt"ResolvedInitializer.struct accessed but kind is {init.kind}"
  init.struct

# ---- ResolvedFunctionCall ----

proc newResolvedFunctionCall*(parsed: FunctionCall,
    args: seq[ResolvedExpression]): ResolvedFunctionCall =
  ResolvedFunctionCall(parsed: parsed, args: args)

proc parsed*(fncall: ResolvedFunctionCall): FunctionCall = fncall.parsed
proc args*(fncall: ResolvedFunctionCall): seq[ResolvedExpression] = fncall.args

# ---- ResolvedAssignment ----

proc newResolvedAssignment*(parsed: Assignment,
    expression: ResolvedExpression): ResolvedAssignment =
  ResolvedAssignment(parsed: parsed, expression: expression)

proc parsed*(assignment: ResolvedAssignment): Assignment = assignment.parsed
proc expression*(assignment: ResolvedAssignment): ResolvedExpression = assignment.expression

# ---- ResolvedSetter ----

proc newResolvedSetter*(parsed: Setter, getter: ResolvedGetter,
    expression: ResolvedExpression): ResolvedSetter =
  ResolvedSetter(parsed: parsed, getter: getter, expression: expression)

proc parsed*(setter: ResolvedSetter): Setter = setter.parsed
proc getter*(setter: ResolvedSetter): ResolvedGetter = setter.getter
proc expression*(setter: ResolvedSetter): ResolvedExpression = setter.expression

# ---- ResolvedCaseBlock ----

proc newResolvedCaseBlock*(parsed: CaseBlock, pattern: ResolvedCasePattern,
    statements: seq[ResolvedStatement]): ResolvedCaseBlock =
  ResolvedCaseBlock(parsed: parsed, pattern: pattern, statements: statements)

proc parsed*(caseBlock: ResolvedCaseBlock): CaseBlock = caseBlock.parsed
proc pattern*(caseBlock: ResolvedCaseBlock): ResolvedCasePattern = caseBlock.pattern
proc statements*(caseBlock: ResolvedCaseBlock): seq[ResolvedStatement] = caseBlock.statements

# ---- ResolvedMatchExpression ----

proc newResolvedMatchExpression*(parsed: MatchExpression,
    subject: ResolvedExpression,
    cases: seq[ResolvedCaseBlock]): ResolvedMatchExpression =
  ResolvedMatchExpression(parsed: parsed, subject: subject, cases: cases)

proc parsed*(match: ResolvedMatchExpression): MatchExpression = match.parsed
proc subject*(match: ResolvedMatchExpression): ResolvedExpression = match.subject
proc cases*(match: ResolvedMatchExpression): seq[ResolvedCaseBlock] = match.cases

# ---- ResolvedExpression ----

proc newResolvedExpression*(fncall: ResolvedFunctionCall): ResolvedExpression =
  ResolvedExpression(kind: rekFunctionCall, fncall: fncall)

proc newResolvedExpression*(initializer: ResolvedInitializer): ResolvedExpression =
  ResolvedExpression(kind: rekInitializer, initializer: initializer)

proc newResolvedExpression*(variable: Identifier): ResolvedExpression =
  ResolvedExpression(kind: rekVariable, variable: variable)

proc newResolvedExpression*(literal: Literal): ResolvedExpression =
  ResolvedExpression(kind: rekLiteral, literal: literal)

proc newResolvedExpression*(getter: ResolvedGetter): ResolvedExpression =
  ResolvedExpression(kind: rekGetter, getter: getter)

proc newResolvedExpression*(match: ResolvedMatchExpression): ResolvedExpression =
  ResolvedExpression(kind: rekMatchExpr, match: match)

proc kind*(expression: ResolvedExpression): ResolvedExpressionKind = expression.kind
proc fncall*(expression: ResolvedExpression): ResolvedFunctionCall =
  assert expression.kind == rekFunctionCall,
    fmt"ResolvedExpression.fncall accessed but kind is {expression.kind}"
  expression.fncall
proc variable*(expression: ResolvedExpression): Identifier =
  assert expression.kind == rekVariable,
    fmt"ResolvedExpression.variable accessed but kind is {expression.kind}"
  expression.variable
proc literal*(expression: ResolvedExpression): Literal =
  assert expression.kind == rekLiteral,
    fmt"ResolvedExpression.literal accessed but kind is {expression.kind}"
  expression.literal
proc match*(expression: ResolvedExpression): ResolvedMatchExpression =
  assert expression.kind == rekMatchExpr,
    fmt"ResolvedExpression.match accessed but kind is {expression.kind}"
  expression.match
proc init*(expression: ResolvedExpression): ResolvedInitializer =
  assert expression.kind == rekInitializer,
    fmt"ResolvedExpression.init accessed but kind is {expression.kind}"
  expression.initializer
proc getter*(expression: ResolvedExpression): ResolvedGetter =
  assert expression.kind == rekGetter,
    fmt"ResolvedExpression.getter accessed but kind is {expression.kind}"
  expression.getter

# ---- ResolvedStatement ----

proc newResolvedStatement*(assignment: ResolvedAssignment): ResolvedStatement =
  ResolvedStatement(kind: rskAssignment, assignment: assignment)

proc newResolvedStatement*(expression: ResolvedExpression): ResolvedStatement =
  ResolvedStatement(kind: rskExpr, expression: expression)

proc newResolvedStatement*(setter: ResolvedSetter): ResolvedStatement =
  ResolvedStatement(kind: rskSetter, setter: setter)

proc kind*(statement: ResolvedStatement): ResolvedStatementKind = statement.kind
proc expression*(statement: ResolvedStatement): ResolvedExpression =
  assert statement.kind == rskExpr,
    fmt"ResolvedStatement.expression accessed but kind is {statement.kind}"
  statement.expression
proc assignment*(statement: ResolvedStatement): ResolvedAssignment =
  assert statement.kind == rskAssignment,
    fmt"ResolvedStatement.assignment accessed but kind is {statement.kind}"
  statement.assignment
proc setter*(statement: ResolvedStatement): ResolvedSetter =
  assert statement.kind == rskSetter,
    fmt"ResolvedStatement.setter accessed but kind is {statement.kind}"
  statement.setter

# ---- ResolvedUserFunction ----

proc newResolvedUserFunction*(parsed: UserFunction,
    funcDef: ResolvedFunctionDefinition,
    statements: seq[ResolvedStatement]): ResolvedUserFunction =
  ResolvedUserFunction(parsed: parsed, funcDef: funcDef, statements: statements)

proc parsed*(function: ResolvedUserFunction): UserFunction = function.parsed
proc def*(function: ResolvedUserFunction): ResolvedFunctionDefinition = function.funcDef
proc statements*(function: ResolvedUserFunction): seq[ResolvedStatement] = function.statements

# ---- ResolvedFunction ----

proc newResolvedFunction*(extern: ResolvedExternFunction): ResolvedFunction =
  ResolvedFunction(kind: rfkExtern, extern: extern)

proc newResolvedFunction*(user: ResolvedUserFunction): ResolvedFunction =
  ResolvedFunction(kind: rfkUser, user: user)

proc kind*(function: ResolvedFunction): ResolvedFunctionKind = function.kind
proc extern*(function: ResolvedFunction): ResolvedExternFunction =
  assert function.kind == rfkExtern,
    fmt"ResolvedFunction.extern accessed but kind is {function.kind}"
  function.extern
proc user*(function: ResolvedFunction): ResolvedUserFunction =
  assert function.kind == rfkUser,
    fmt"ResolvedFunction.user accessed but kind is {function.kind}"
  function.user

# ---- ResolvedModule ----

proc newResolvedModuleInternal*(parsed: Module,
    requires: seq[ResolvedGenericArgumentType],
    data: Option[ResolvedData],
    funcDefIndex: Table[ResolvedFunctionDefinition, int],
    funcNameArityIndex: Table[Identifier, Table[int, seq[int]]],
    functions: seq[ResolvedFunction]): ResolvedModule =
  ## Raw constructor exposed for modules.nim's `newResolvedModule`
  ## front door, which computes the two indices from the function list.
  ResolvedModule(parsed: parsed, requires: requires, data: data,
    funcDefIndex: funcDefIndex, funcNameArityIndex: funcNameArityIndex,
    functions: functions)

proc parsed*(module: ResolvedModule): Module = module.parsed
proc requires*(module: ResolvedModule): seq[ResolvedGenericArgumentType] = module.requires
proc data*(module: ResolvedModule): Option[ResolvedData] = module.data
proc functions*(module: ResolvedModule): seq[ResolvedFunction] = module.functions
proc funcDefIndex*(module: ResolvedModule): Table[ResolvedFunctionDefinition, int] = module.funcDefIndex
proc funcNameArityIndex*(module: ResolvedModule): Table[Identifier, Table[int, seq[int]]] = module.funcNameArityIndex

# ---- ResolvedGeneric ----

proc newResolvedGenericInternal*(parsed: Generic,
    funcDefs: seq[ResolvedFunctionDefinition],
    funcDefIndex: Table[ResolvedFunctionDefinition, int],
    funcNameArityIndex: Table[Identifier, Table[int, seq[int]]]): ResolvedGeneric =
  ## Raw constructor exposed for modules.nim's `newResolvedGeneric`
  ## front door, which computes the two indices from the funcDef list.
  ResolvedGeneric(parsed: parsed, funcDefs: funcDefs,
    funcDefIndex: funcDefIndex, funcNameArityIndex: funcNameArityIndex)

proc parsed*(generic: ResolvedGeneric): Generic = generic.parsed
proc funcDefs*(generic: ResolvedGeneric): seq[ResolvedFunctionDefinition] = generic.funcDefs
proc funcDefIndex*(generic: ResolvedGeneric): Table[ResolvedFunctionDefinition, int] = generic.funcDefIndex
proc funcNameArityIndex*(generic: ResolvedGeneric): Table[Identifier, Table[int, seq[int]]] = generic.funcNameArityIndex

# ---- ResolvedDefinedType ----

proc newResolvedDefinedType*(id: int, module: ResolvedModule): ResolvedDefinedType =
  ResolvedDefinedType(id: id, kind: rdtkModule, module: module)

proc newResolvedDefinedType*(id: int, generic: ResolvedGeneric): ResolvedDefinedType =
  ResolvedDefinedType(id: id, kind: rdtkGeneric, generic: generic)

proc kind*(definedType: ResolvedDefinedType): ResolvedDefinedTypeKind = definedType.kind
proc module*(definedType: ResolvedDefinedType): ResolvedModule =
  assert definedType.kind == rdtkModule,
    fmt"ResolvedDefinedType.module accessed but kind is {definedType.kind}"
  definedType.module
proc generic*(definedType: ResolvedDefinedType): ResolvedGeneric =
  assert definedType.kind == rdtkGeneric,
    fmt"ResolvedDefinedType.generic accessed but kind is {definedType.kind}"
  definedType.generic

# ============================================================================
# Two-pass resolver support: shells + populate + shell tables.
#
# `ResolvedModuleArgumentType` now holds a `ResolvedModule` reference,
# but `ResolvedModule` is what the resolver is building — chicken/egg.
# Resolved by a declare-then-populate pattern:
#
#   1. Before any argument type resolves, the declare pass walks
#      every parser Module in the app and creates a shell
#      `ResolvedModule` (via `newResolvedModuleShell`) keyed on
#      parser identity in a `ResolvedModuleShells` table.
#   2. During the define pass, `resolveArgumentType` looks up the
#      shell in the table when building a `ResolvedModuleArgumentType`
#      — the resulting reference is stable even though the shell is
#      still empty.
#   3. When each module finishes resolving, its shell is
#      `populate`d with the freshly-computed requires / data /
#      functions / indices. After that, every ResolvedModuleArgumentType
#      dereferences to a fully-formed ResolvedModule.
#
# The generic edge (`ResolvedGenericArgumentType.generic`) stays a
# parser `Generic` — task 6c is scoped to the module edge.
# ============================================================================

type
  ResolvedModuleShells* = Table[Module, ResolvedModule]

proc newResolvedModuleShell*(parsed: Module): ResolvedModule =
  ## Zero-initialised ResolvedModule carrying only its parser back-ref.
  ## Every parser Module in the app gets one shell during the declare
  ## pass so ResolvedModuleArgumentType.resolvedModule always resolves.
  ResolvedModule(parsed: parsed)

proc populate*(module: ResolvedModule,
    requires: seq[ResolvedGenericArgumentType],
    data: Option[ResolvedData],
    functions: seq[ResolvedFunction],
    funcDefIndex: Table[ResolvedFunctionDefinition, int],
    funcNameArityIndex: Table[Identifier, Table[int, seq[int]]]) =
  ## Fill in a shell ResolvedModule after the define pass has walked
  ## the module. Called once per module — callers rely on the shell
  ## staying pristine until the define pass completes.
  module.requires = requires
  module.data = data
  module.functions = functions
  module.funcDefIndex = funcDefIndex
  module.funcNameArityIndex = funcNameArityIndex
