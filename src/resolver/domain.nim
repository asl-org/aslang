## src/resolver/domain.nim
##
## The resolver's domain model — every mutually-recursive
## resolved type together with its constructors, accessors, and
## resolveX procs. Cohesion: types stay next to their procs, in
## the same file. One giant `type:` block up front satisfies
## Nim's mutually-recursive ref-object requirement; the block
## is followed by per-concept sections that group everything
## about each concept together.
##
## Standalone concepts that don't participate in the cycle
## (`ResolvedLiteralDef` in `literals.nim`, `ResolvedCasePattern`
## in `patterns.nim`) stay in their own files.

import results, options, tables, sets, hashes, strformat, strutils, sequtils

import parser
import literals
import patterns

# =====================================================================
# Type aliases (non-recursive).
# =====================================================================

# FileScope alias — keyed by binding (alias-or-name); shared by
# every resolver file that walks bodies.
type FileScope* = Table[Identifier, DefinedType]

# FunctionScope alias — names of variables currently in scope inside
# a function body.
type FunctionScope* = HashSet[Identifier]

# =====================================================================
# One `type:` block for the whole mutually-recursive cycle.
#
# Nim requires mutually-recursive `ref object` types to share a single
# `type:` block — the cycle rooted at `ResolvedArgumentType` reaches
# through Module/Function/Statement back to itself and cannot be split.
# =====================================================================

type
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

  ResolvedArgumentDef* = ref object
    parsed: ArgumentDef
    argType: ResolvedArgumentType

  ResolvedFunctionDef* = ref object
    parsed: FunctionDef
    args: seq[ResolvedArgumentDef]
    returns: ResolvedArgumentType

  ResolvedExternFunction* = ref object
    parsed: ExternFunction
    def: ResolvedFunctionDef

  # ==== Data-block shapes ====

  ResolvedStructDef* = ref object
    parsed: StructDef
    fields: seq[ResolvedArgumentDef]
    fieldIndex: Table[Identifier, int]
    genericTypeIndex: Table[ResolvedGenericArgumentType, int]

  ResolvedVariant* = ref object
    parsed: VariantDef
    fields: seq[ResolvedArgumentDef]
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

  ResolvedStructRef* = ref object
    parsed: StructRef
    resolvedModule: ResolvedModule
    resolvedImpls: seq[ResolvedArgumentType]

  ResolvedUnionRef* = ref object
    parsed: UnionRef
    resolvedModule: ResolvedModule
    resolvedImpls: seq[ResolvedArgumentType]

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
    # Task 7: reserved for FunctionCall receivers that carry an
    # explicit impl list. The parser currently has no impl syntax for
    # function calls (FunctionCall.root is a bare Identifier, not an
    # ArgumentType), so this stays empty for now. When impl syntax is
    # added, the arity+constraint check for these impls will run in
    # resolveFunctionCall — never in the analyzer.
    resolvedImpls: seq[ResolvedArgumentType]

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
    funcDef: ResolvedFunctionDef
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
    funcDefIndex: Table[ResolvedFunctionDef, int]
    funcNameArityIndex: Table[Identifier, Table[int, seq[int]]]
    functions: seq[ResolvedFunction]

  ResolvedGeneric* = ref object
    parsed: Generic
    funcDefs: seq[ResolvedFunctionDef]
    funcDefIndex: Table[ResolvedFunctionDef, int]
    funcNameArityIndex: Table[Identifier, Table[int, seq[int]]]

  # ==== DefinedType umbrella ====

  ResolvedDefinedTypeKind* = enum
    rdtkModule, rdtkGeneric
  ResolvedDefinedType* = ref object
    id: int
    case kind: ResolvedDefinedTypeKind
    of rdtkModule: module: ResolvedModule
    of rdtkGeneric: generic: ResolvedGeneric

# =====================================================================
# Shell table for the two-pass resolver.
#
# `ResolvedModuleArgumentType` holds a `ResolvedModule` reference,
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
# The alias lives up here because virtually every `resolve*` proc
# threads it through. The shell constructor and `populate` proc live
# with the Module section further down.
# =====================================================================

type
  ResolvedModuleShells* = Table[Module, ResolvedModule]

# =====================================================================
# Forward declarations
#
# Only the mutual-recursion points that cross section boundaries or
# arms of a tagged union need forward declarations.
# =====================================================================

# hash/asl on ResolvedArgumentType and ResolvedModuleArgumentType
# call into each other through the tagged-union dispatch.
proc hash*(argType: ResolvedArgumentType): Hash
proc asl*(argType: ResolvedArgumentType): string

# resolveArgumentType (both context overloads) is called by the
# module-context resolveModuleArgumentType helper for impls.
proc resolveArgumentType*(app: App, shells: ResolvedModuleShells,
    file: parser.File, fileScope: FileScope, module: Module,
    argType: ArgumentType): Result[ResolvedArgumentType, string]

proc resolveArgumentType*(app: App, shells: ResolvedModuleShells,
    file: parser.File, fileScope: FileScope, generic: Generic,
    argType: ArgumentType): Result[ResolvedArgumentType, string]

# resolveExpression / resolveStatement form the body-cluster cycle.
proc resolveExpression*(app: App, shells: ResolvedModuleShells,
    file: parser.File, fileScope: FileScope,
    module: Module, scope: FunctionScope,
    expression: Expression): Result[ResolvedExpression, string]

proc resolveStatement*(app: App, shells: ResolvedModuleShells,
    file: parser.File, fileScope: FileScope,
    module: Module, scope: FunctionScope,
    statement: Statement): Result[ResolvedStatement, string]

# =====================================================================
# Argument-type cluster (grammar `ArgumentType`)
# =====================================================================

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

proc hash*(argType: ResolvedModuleArgumentType): Hash =
  # Hash by parser Module identity (the resolvedModule shell is
  # created keyed on Module, so parsed.hash is the stable identity).
  var acc = argType.parsed.hash
  for impl in argType.impls:
    acc = acc !& impl.hash
  return acc
proc `==`*(a, b: ResolvedModuleArgumentType): bool = a.hash == b.hash

proc asl*(argType: ResolvedModuleArgumentType): string =
  if argType.impls.len == 0:
    fmt"{argType.parsed.name.asl}"
  else:
    var impls: seq[string]
    for impl in argType.impls:
      impls.add(impl.asl)
    let implsJoined = impls.join(", ")
    fmt"{argType.parsed.name.asl}[{implsJoined}]"

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

proc name*(argType: ResolvedArgumentType): Identifier =
  case argType.kind:
  of ratkModule: argType.module.parsed.name
  of ratkGeneric: argType.generic.name

proc loc*(argType: ResolvedArgumentType): Location =
  case argType.kind:
  of ratkModule: argType.module.loc
  of ratkGeneric: argType.generic.loc

proc hash*(argType: ResolvedArgumentType): Hash =
  case argType.kind:
  of ratkModule: argType.module.hash
  of ratkGeneric: argType.generic.hash

proc `==`*(a, b: ResolvedArgumentType): bool = a.hash == b.hash

proc asl*(argType: ResolvedArgumentType): string =
  case argType.kind:
  of ratkModule: argType.module.asl
  of ratkGeneric: argType.generic.asl

proc concreteArgumentType*(argType: ResolvedArgumentType, concrete: ResolvedArgumentType, generic: Generic): ResolvedArgumentType =
  case argType.kind:
  of ratkModule: argType
  of ratkGeneric:
    if argType.generic.parsed != generic:
      argType
    else:
      concrete

# ---- Scope lookups ----

proc findDefinedType*(file: parser.File, fileScope: FileScope, name: Identifier): Result[DefinedType, string] =
  let maybeFieldType = file.findType(name)
  if maybeFieldType.isOk:
    let fieldType = maybeFieldType.get
    case fieldType.kind:
    of tkImported:
      let importedType = fieldType.imported
      if importedType.binding notin fileScope:
        err(fmt"{importedType.loc} type `{importedType.binding.asl}` does not exist in the file scope.")
      else:
        ok(fileScope[importedType.binding])
    of tkDefined:
      ok(fieldType.definedType)
  elif name in fileScope:
    # Name isn't in the parser's typeIndex (no explicit import or
    # local definition) but the resolver populated fileScope with it
    # — i.e., it came from a shorthand `import "file.asl"` expansion
    # in resolveImport.
    ok(fileScope[name])
  else:
    err(fmt"{name.loc} type `{name.asl}` does not exist in the scope")

proc findModule*(file: parser.File, fileScope: FileScope, name: Identifier): Result[Module, string] =
  let initDefinedType = ? file.findDefinedType(fileScope, name)
  case initDefinedType.kind:
  of dtkGeneric: err(fmt"{name.loc} type `{name.asl}` is a generic and not a module")
  of dtkModule: ok(initDefinedType.module)

proc findRequiredImplsForFields(file: parser.File, fileScope: FileScope, fields: seq[ArgumentDef]): Result[seq[Generic], string] =
  # TODO(union-inference): walk impls recursively. Today this only
  # looks at the field's top-level root, so a field typed
  # `Box[u8, Sample]` returns nothing — even though the containing
  # struct/variant should inherit `Sample` as one of its requires.
  # Under leave-as-is, polymorphic types nesting in field positions
  # is common (any field whose value came from a partial-coverage
  # union initializer carries a free generic). Walk each impl's
  # ArgumentType recursively and collect every generic referenced
  # anywhere in the tree, deduped by first-seen order.
  var requiredImpls: seq[Generic]
  for field in fields:
    let definedFieldType = ? file.findDefinedType(fileScope, field.argType.root)
    case definedFieldType.kind:
    of dtkModule: discard
    of dtkGeneric: requiredImpls.add(definedFieldType.generic)
  ok(requiredImpls)

proc findRequiredImplsForStruct(file: parser.File, fileScope: FileScope, struct: StructDef): Result[seq[Generic], string] =
  findRequiredImplsForFields(file, fileScope, struct.fields)

proc findRequiredImplsForUnion(file: parser.File, fileScope: FileScope, union: UnionDef): Result[seq[Generic], string] =
  # Rust-style: a generic name shared across variants is one shared
  # type parameter, deduped by first-seen order across variants.
  var seen: HashSet[Generic]
  var requiredUnionImpls: seq[Generic]
  for variant in union.variants:
    let requiredVariantImpls = ? findRequiredImplsForFields(file, fileScope, variant.fields)
    for generic in requiredVariantImpls:
      if generic notin seen:
        seen.incl(generic)
        requiredUnionImpls.add(generic)
  ok(requiredUnionImpls)

# ---- resolveArgumentType internals ----

proc lookupShell(shells: ResolvedModuleShells, root: Module): ResolvedModule =
  ## Look up the shell allocated during the declare pass. Every parser
  ## Module reachable through resolution must have a shell — the
  ## declare pass in apps.nim walks every DefinedType in every file.
  assert(root in shells, fmt"UNREACHABLE: no shell allocated for module `{root.name.asl}` at {root.loc}")
  shells[root]

# Constraint-satisfaction check: does `resolvedImpl` provide every
# funcDef the required generic `base` mandates? Retired the analyzer's
# equivalent def-time check and moved it here so
# ResolvedModuleArgumentType.impls is a provably valid value by the
# time it leaves the resolver.
#
# Semantics drift vs the retired analyzer check: verification is by
# (name, arity) at the parser level, not by concretized-signature
# hash. Signature-parity (e.g. impl provides `byte_size(items: u16)`
# where the base generic mandates `byte_size(items: u32)`) is left to
# the analyzer's value-vs-defType walk at use sites
# (analyzer/body.nim's `analyzeValueTypeAgainstDefType`), which
# already runs the strict hash-based check every time a value is
# type-checked against a definition. The def-time check here catches
# the "impl is missing the method entirely" case — the common
# regression path — without needing ResolvedGeneric to be populated at
# def-time (generics have no shell/populate two-pass, so ordering
# would otherwise force a wider refactor).
proc checkImplSatisfiesGeneric(resolvedImpl: ResolvedArgumentType, base: Generic): Result[void, string] =
  case resolvedImpl.kind:
  of ratkModule:
    let implModule = resolvedImpl.module.resolvedModule.parsed
    for funcDef in base.funcDefs:
      let maybeFuncDefs = implModule.findFunctionDefs(funcDef.name, funcDef.arity)
      if maybeFuncDefs.isErr:
        return err(fmt"{resolvedImpl.module.loc} module `{implModule.name.asl}` does not implement function `{funcDef.name.asl}` to support `{base.name.asl}`")
  of ratkGeneric:
    let implGeneric = resolvedImpl.generic.parsed
    for funcDef in base.funcDefs:
      let maybeFuncDefs = implGeneric.findFunctionDefs(funcDef.name, funcDef.arity)
      if maybeFuncDefs.isErr:
        return err(fmt"{resolvedImpl.generic.loc} generic `{implGeneric.name.asl}` does not implement function `{funcDef.name.asl}` to support `{base.name.asl}`")
  ok()

proc findGeneric*(file: parser.File, fileScope: FileScope, name: Identifier): Result[Generic, string] =
  ## Parser-level generic lookup — mirror of `findModule` for the
  ## constraint-check helper. Used by resolveModuleArgumentType's
  ## explicit-requires path to translate each `requires(...)` name into
  ## its parser Generic so the check can walk its funcDefs.
  let initDefinedType = ? file.findDefinedType(fileScope, name)
  case initDefinedType.kind:
  of dtkModule: err(fmt"{name.loc} type `{name.asl}` is a module but expected generic")
  of dtkGeneric: ok(initDefinedType.generic)

# resolveModuleArgumentType — module context.
proc resolveModuleArgumentType(app: App, shells: ResolvedModuleShells,
    file: parser.File, fileScope: FileScope,
    module: Module, argType: ArgumentType,
    root: Module): Result[ResolvedModuleArgumentType, string] =
  let resolvedRoot = lookupShell(shells, root)
  # NOTE: requires block will override the inferred impl list
  if root.requires.isSome:
    let requiredNames = root.requires.get.generics
    if argType.impls.len != requiredNames.len:
      return err(fmt"{argType.loc} type `{root.name.asl}` expects `{requiredNames.len}` impls but found `{argType.impls.len}`")

    var resolvedImpls: seq[ResolvedArgumentType]
    for (requiredName, impl) in zip(requiredNames, argType.impls):
      let requiredGeneric = ? file.findGeneric(fileScope, requiredName)
      let resolvedImpl = ? resolveArgumentType(app, shells, file, fileScope, module, impl)
      ? checkImplSatisfiesGeneric(resolvedImpl, requiredGeneric)
      resolvedImpls.add(resolvedImpl)

    return ok(newResolvedModuleArgumentType(resolvedRoot, resolvedImpls, argType.loc))

  # NOTE: infer the impl list from struct/union block
  if root.data.isSome:
    let dataDef = root.data.get
    case dataDef.kind:
    of dbkLiteral:
      if argType.impls.len == 0:
        return ok(newResolvedModuleArgumentType(resolvedRoot, argType.loc))
      else:
        return err(fmt"{argType.loc} type `{root.name.asl}` does not require impl types")
    of ddkStruct:
      let requires = ? file.findRequiredImplsForStruct(fileScope, dataDef.struct)
      if argType.impls.len != requires.len:
        return err(fmt"{argType.loc} struct `{root.name.asl}` expects `{requires.len}` impls but found `{argType.impls.len}`")

      var resolvedImpls: seq[ResolvedArgumentType]
      for (requiredGeneric, impl) in zip(requires, argType.impls):
        let resolvedImpl = ? resolveArgumentType(app, shells, file, fileScope, module, impl)
        ? checkImplSatisfiesGeneric(resolvedImpl, requiredGeneric)
        resolvedImpls.add(resolvedImpl)

      return ok(newResolvedModuleArgumentType(resolvedRoot, resolvedImpls, argType.loc))

    of ddkUnion:
      let requires = ? file.findRequiredImplsForUnion(fileScope, dataDef.union)
      if argType.impls.len != requires.len:
        return err(fmt"{argType.loc} union `{root.name.asl}` expects `{requires.len}` impls but found `{argType.impls.len}`")

      var resolvedImpls: seq[ResolvedArgumentType]
      for (requiredGeneric, impl) in zip(requires, argType.impls):
        let resolvedImpl = ? resolveArgumentType(app, shells, file, fileScope, module, impl)
        ? checkImplSatisfiesGeneric(resolvedImpl, requiredGeneric)
        resolvedImpls.add(resolvedImpl)

      return ok(newResolvedModuleArgumentType(resolvedRoot, resolvedImpls, argType.loc))

  if argType.impls.len == 0:
    ok(newResolvedModuleArgumentType(resolvedRoot, argType.loc))
  else:
    err(fmt"{argType.loc} type `{root.name.asl}` does not require impl types")

# resolveModuleArgumentType — generic context. Mirrors module-context
# but with the self-only rule and a still-stubbed ddkStruct path.
proc resolveModuleArgumentType(app: App, shells: ResolvedModuleShells,
    file: parser.File, fileScope: FileScope, generic: Generic,
    argType: ArgumentType,
    root: Module): Result[ResolvedModuleArgumentType, string] =
  let resolvedRoot = lookupShell(shells, root)
  if root.requires.isSome:
    return err("todo: resolve requires block in argument type")

  if root.data.isSome:
    let dataDef = root.data.get
    case dataDef.kind:
    of ddkStruct:
      return err(fmt"{dataDef.loc} todo: resolve struct block in argument type")
    of dbkLiteral:
      if argType.impls.len == 0:
        return ok(newResolvedModuleArgumentType(resolvedRoot, argType.loc))
      else:
        return err(fmt"{argType.loc} type `{root.name.asl}` does not require impl types")
    of ddkUnion:
      var requires = ? findRequiredImplsForUnion(file, fileScope, dataDef.union)
      if argType.impls.len != requires.len:
        return err(fmt"{argType.loc} type `{root.name.asl}` expects `{requires.len}` impls but found `{argType.impls.len}`")

      var resolvedImpls: seq[ResolvedArgumentType]
      for (requiredGeneric, impl) in zip(requires, argType.impls):
        let resolvedImpl = ? resolveArgumentType(app, shells, file, fileScope, generic, impl)
        ? checkImplSatisfiesGeneric(resolvedImpl, requiredGeneric)
        resolvedImpls.add(resolvedImpl)

      return ok(newResolvedModuleArgumentType(resolvedRoot, resolvedImpls, argType.loc))

  if argType.impls.len == 0:
    ok(newResolvedModuleArgumentType(resolvedRoot, argType.loc))
  else:
    err(fmt"{argType.loc} type `{root.name.asl}` does not require impl types")

proc resolveGenericArgumentType(app: App, file: parser.File, generic: Generic, argType: ArgumentType, genericArgType: Generic): Result[ResolvedGenericArgumentType, string] =
  if genericArgType == generic:
    ok(newResolvedGenericArgumentType(genericArgType, argType.loc))
  else:
    err(fmt"{argType.loc} type `{genericArgType.name.asl}` is a generic and can not be used within the generic block")

proc resolveGenericArgumentType(app: App, file: parser.File, module: Module, argType: ArgumentType, genericArgType: Generic): Result[ResolvedGenericArgumentType, string] =
  if argType.impls.len == 0:
    ok(newResolvedGenericArgumentType(genericArgType, genericArgType.loc))
  else:
    err(fmt"{genericArgType.loc} generic `{genericArgType.name.asl}` is not allowed to have impls")

# resolveArgumentType — both context overloads.
proc resolveArgumentType*(app: App, shells: ResolvedModuleShells,
    file: parser.File, fileScope: FileScope, module: Module,
    argType: ArgumentType): Result[ResolvedArgumentType, string] =
  let definedType = ? file.findDefinedType(fileScope, argType.root)
  case definedType.kind:
  of dtkGeneric:
    let resolvedGenericType = ? resolveGenericArgumentType(app, file, module, argType, definedType.generic)
    ok(newResolvedArgumentType(resolvedGenericType))
  of dtkModule:
    let resolvedModuleType = ? resolveModuleArgumentType(app, shells, file, fileScope, module, argType, definedType.module)
    ok(newResolvedArgumentType(resolvedModuleType))

proc resolveArgumentType*(app: App, shells: ResolvedModuleShells,
    file: parser.File, fileScope: FileScope, generic: Generic,
    argType: ArgumentType): Result[ResolvedArgumentType, string] =
  let definedType = ? file.findDefinedType(fileScope, argType.root)
  case definedType.kind:
  of dtkGeneric:
    let resolvedGenericType = ? resolveGenericArgumentType(app, file, generic, argType, definedType.generic)
    ok(newResolvedArgumentType(resolvedGenericType))
  of dtkModule:
    let resolvedModuleType = ? resolveModuleArgumentType(app, shells, file, fileScope, generic, argType, definedType.module)
    ok(newResolvedArgumentType(resolvedModuleType))

# resolveDataType — post-resolution guard. Confirms the resolved
# argument's underlying module has a data block (or that we're
# pointing at an unsubstituted generic, which is acceptable).
#
# Reads through the parser Module via `parsed*` — the shell
# ResolvedModule's own `data` field may still be empty at the time
# this guard runs (shells populate only after resolveModule finishes
# its own data block + functions), but the parser Module's data
# option is set at parse time and always available.
proc resolveDataType*(file: parser.File, module: Module, arg: ArgumentType,
    resolvedArgumentType: ResolvedArgumentType): Result[void, string] =
  case resolvedArgumentType.kind:
  of ratkGeneric:
    ok()
  of ratkModule:
    let parsedModule = resolvedArgumentType.module.parsed
    if parsedModule.data.isSome:
      ok()
    else:
      err(fmt"{arg.loc} module `{parsedModule.name.asl}` is not a literal/struct/union")

proc resolveDataType*(file: parser.File, generic: Generic, arg: ArgumentType,
    resolvedArgumentType: ResolvedArgumentType): Result[void, string] =
  case resolvedArgumentType.kind:
  of ratkGeneric:
    ok()
  of ratkModule:
    let parsedModule = resolvedArgumentType.module.parsed
    if parsedModule.data.isSome:
      ok()
    else:
      err(fmt"{arg.loc} module `{parsedModule.name.asl}` is not a literal/struct/union")

# =====================================================================
# Function definitions
# (ResolvedArgumentDef, ResolvedFunctionDef,
#  ResolvedExternFunction)
# =====================================================================

# ---- ResolvedArgumentDef ----

proc newResolvedArgumentDef*(parsed: ArgumentDef,
    argType: ResolvedArgumentType): ResolvedArgumentDef =
  ResolvedArgumentDef(parsed: parsed, argType: argType)

proc parsed*(d: ResolvedArgumentDef): ArgumentDef = d.parsed
proc name*(d: ResolvedArgumentDef): Identifier = d.parsed.name
proc argType*(d: ResolvedArgumentDef): ResolvedArgumentType = d.argType
proc loc*(d: ResolvedArgumentDef): Location = d.argType.loc
proc hash*(d: ResolvedArgumentDef): Hash = d.argType.hash
proc `==`*(a, b: ResolvedArgumentDef): bool = a.hash == b.hash
proc asl*(argDef: ResolvedArgumentDef): string =
  fmt"{argDef.name.asl}: {argDef.argType.asl}"

proc concreteArgumentDef(argDef: ResolvedArgumentDef, concrete: ResolvedArgumentType, generic: Generic): ResolvedArgumentDef =
  let concreteArgType = argDef.argType.concreteArgumentType(concrete, generic)
  newResolvedArgumentDef(argDef.parsed, concreteArgType)

proc resolveArgumentDef*(app: App, shells: ResolvedModuleShells,
    file: parser.File, fileScope: FileScope, module: Module,
    arg: ArgumentDef): Result[ResolvedArgumentDef, string] =
  let resolvedArgumentType = ? resolveArgumentType(app, shells, file, fileScope, module,
    arg.argType)
  ? resolveDataType(file, module, arg.argType, resolvedArgumentType)
  ok(newResolvedArgumentDef(arg, resolvedArgumentType))

proc resolveArgumentDef*(app: App, shells: ResolvedModuleShells,
    file: parser.File, fileScope: FileScope, generic: Generic,
    arg: ArgumentDef): Result[ResolvedArgumentDef, string] =
  let resolvedArgumentType = ? resolveArgumentType(app, shells, file, fileScope, generic,
    arg.argType)
  ? resolveDataType(file, generic, arg.argType, resolvedArgumentType)
  ok(newResolvedArgumentDef(arg, resolvedArgumentType))

# ---- ResolvedFunctionDef ----

proc newResolvedFunctionDef*(parsed: FunctionDef,
    args: seq[ResolvedArgumentDef],
    returns: ResolvedArgumentType): ResolvedFunctionDef =
  ResolvedFunctionDef(parsed: parsed, args: args, returns: returns)

proc parsed*(funcDef: ResolvedFunctionDef): FunctionDef = funcDef.parsed
proc args*(funcDef: ResolvedFunctionDef): seq[ResolvedArgumentDef] = funcDef.args
proc returns*(funcDef: ResolvedFunctionDef): ResolvedArgumentType = funcDef.returns
proc public*(funcDef: ResolvedFunctionDef): bool = funcDef.parsed.public
proc name*(funcDef: ResolvedFunctionDef): Identifier = funcDef.parsed.name
proc arity*(funcDef: ResolvedFunctionDef): int = funcDef.parsed.arity
proc loc*(funcDef: ResolvedFunctionDef): Location = funcDef.parsed.loc

proc asl*(funcDef: ResolvedFunctionDef): string =
  var args: seq[string]
  for arg in funcDef.args:
    args.add(arg.asl)
  let argsJoined = args.join(", ")
  fmt"func {funcDef.name.asl}({argsJoined}): {funcDef.returns.asl}"

proc hash*(funcDef: ResolvedFunctionDef): Hash =
  var acc = funcDef.name.hash
  for arg in funcDef.args:
    acc = acc !& arg.hash
  return acc

proc `==`*(a, b: ResolvedFunctionDef): bool = a.hash == b.hash

proc concreteFunctionDef*(funcDef: ResolvedFunctionDef, moduleType: ResolvedArgumentType, generic: Generic): ResolvedFunctionDef =
  var concreteArgs: seq[ResolvedArgumentDef]
  for arg in funcDef.args:
    concreteArgs.add(arg.concreteArgumentDef(moduleType, generic))
  let concreteReturns = funcDef.returns.concreteArgumentType(moduleType, generic)
  newResolvedFunctionDef(funcDef.parsed, concreteArgs, concreteReturns)

proc resolveFunctionDef*(app: App, shells: ResolvedModuleShells,
    file: parser.File, fileScope: FileScope, module: Module,
    def: FunctionDef): Result[ResolvedFunctionDef, string] =
  var resolvedArgs: seq[ResolvedArgumentDef]
  for arg in def.args:
    let resolvedArg = ? resolveArgumentDef(app, shells, file, fileScope, module,
      arg)
    resolvedArgs.add(resolvedArg)

  let resolvedReturnArgType = ? resolveArgumentType(app, shells, file, fileScope, module,
    def.returns)
  ? resolveDataType(file, module, def.returns, resolvedReturnArgType)

  ok(newResolvedFunctionDef(def, resolvedArgs,
    resolvedReturnArgType))

proc resolveFunctionDef*(app: App, shells: ResolvedModuleShells,
    file: parser.File, fileScope: FileScope, generic: Generic,
    def: FunctionDef): Result[ResolvedFunctionDef, string] =
  var resolvedArgs: seq[ResolvedArgumentDef]
  for arg in def.args:
    let resolvedArg = ? resolveArgumentDef(app, shells, file, fileScope, generic, arg)
    resolvedArgs.add(resolvedArg)

  let resolvedReturnArgType = ? resolveArgumentType(app, shells, file, fileScope, generic,
    def.returns)
  ? resolveDataType(file, generic, def.returns, resolvedReturnArgType)

  ok(newResolvedFunctionDef(def, resolvedArgs,
    resolvedReturnArgType))

# ---- ResolvedExternFunction ----

proc newResolvedExternFunction*(parsed: ExternFunction,
    def: ResolvedFunctionDef): ResolvedExternFunction =
  ResolvedExternFunction(parsed: parsed, def: def)

proc parsed*(function: ResolvedExternFunction): ExternFunction = function.parsed
proc def*(function: ResolvedExternFunction): ResolvedFunctionDef = function.def
proc ffi*(function: ResolvedExternFunction): string = function.parsed.ffi
proc loc*(function: ResolvedExternFunction): Location = function.def.loc

proc resolveExternFunction*(app: App, shells: ResolvedModuleShells,
    file: parser.File, fileScope: FileScope, module: Module,
    function: ExternFunction): Result[ResolvedExternFunction, string] =
  let resolvedFunctionDef = ? resolveFunctionDef(app, shells, file, fileScope,
    module, function.def)
  ok(newResolvedExternFunction(function, resolvedFunctionDef))

# =====================================================================
# Data-block cluster
# (ResolvedStructDef, ResolvedVariant, ResolvedUnionDef, ResolvedData)
# =====================================================================

proc accumulateGenericPosition(genericTypeIndex: var Table[ResolvedGenericArgumentType, int], field: ResolvedArgumentDef) =
  ## Assigns the next position to each new generic encountered in
  ## field types. Same name across multiple fields keeps its first
  ## position — the analyzer's GenericImplMap binds one generic to
  ## one concrete type per construction, so duplicate occurrences
  ## are semantically benign (any conflict surfaces at the init site
  ## via merge()). Generic-uniqueness inside an explicit requires()
  ## block is still enforced by validateRequiresConstraints.
  case field.argType.kind:
  of ratkModule: discard
  of ratkGeneric:
    let genericType = field.argType.generic
    if genericType notin genericTypeIndex:
      genericTypeIndex[genericType] = genericTypeIndex.len

# ---- ResolvedStructDef ----

proc newResolvedStructDef*(parsed: StructDef,
    fields: seq[ResolvedArgumentDef],
    genericTypeIndex: Table[ResolvedGenericArgumentType, int]): ResolvedStructDef =
  var fieldIndex: Table[Identifier, int]
  for id, field in fields:
    assert(field.name notin fieldIndex, "UNREACHABLE: duplicate field name — should have been caught in parser")
    fieldIndex[field.name] = id
  ResolvedStructDef(parsed: parsed, fields: fields, fieldIndex: fieldIndex, genericTypeIndex: genericTypeIndex)

proc parsed*(struct: ResolvedStructDef): StructDef = struct.parsed
proc fields*(struct: ResolvedStructDef): seq[ResolvedArgumentDef] = struct.fields
proc genericTypeIndex*(struct: ResolvedStructDef): Table[ResolvedGenericArgumentType, int] = struct.genericTypeIndex
proc fieldIndex*(struct: ResolvedStructDef): Table[Identifier, int] = struct.fieldIndex
proc loc*(struct: ResolvedStructDef): Location = struct.parsed.loc

proc findField*(struct: ResolvedStructDef, name: Identifier): Result[ResolvedArgumentDef, string] =
  if name in struct.fieldIndex: ok(struct.fields[struct.fieldIndex[name]])
  else: err(fmt"{name.loc} field `{name.asl}` does not exist")

proc requires*(struct: ResolvedStructDef): seq[ResolvedGenericArgumentType] =
  var requires = newSeq[ResolvedGenericArgumentType](struct.genericTypeIndex.len)
  for genericType, index in struct.genericTypeIndex:
    requires[index] = genericType
  return requires

proc resolveStructDef*(app: App, shells: ResolvedModuleShells, file: parser.File, fileScope: FileScope, module: Module, struct: StructDef): Result[ResolvedStructDef, string] =
  var resolvedFields: seq[ResolvedArgumentDef]
  var genericTypeIndex: Table[ResolvedGenericArgumentType, int]
  for field in struct.fields:
    let resolvedField = ? resolveArgumentDef(app, shells, file, fileScope, module, field)
    genericTypeIndex.accumulateGenericPosition(resolvedField)
    resolvedFields.add(resolvedField)
  ok(newResolvedStructDef(struct, resolvedFields, genericTypeIndex))

# ---- ResolvedVariant ----

proc newResolvedVariant*(parsed: VariantDef,
    fields: seq[ResolvedArgumentDef]): ResolvedVariant =
  var fieldIndex: Table[Identifier, int]
  for id, field in fields:
    assert(field.name notin fieldIndex, "UNREACHABLE: duplicate field name — should have been caught in parser")
    fieldIndex[field.name] = id
  ResolvedVariant(parsed: parsed, fields: fields, fieldIndex: fieldIndex)

proc parsed*(variant: ResolvedVariant): VariantDef = variant.parsed
proc fields*(variant: ResolvedVariant): seq[ResolvedArgumentDef] = variant.fields
proc fieldIndex*(variant: ResolvedVariant): Table[Identifier, int] = variant.fieldIndex
proc loc*(variant: ResolvedVariant): Location = variant.parsed.loc
proc name*(variant: ResolvedVariant): Identifier = variant.parsed.name

proc findField*(variant: ResolvedVariant, name: Identifier): Result[ResolvedArgumentDef, string] =
  if name in variant.fieldIndex: ok(variant.fields[variant.fieldIndex[name]])
  else: err(fmt"{name.loc} field `{name.asl}` does not exist")

# NOTE: `genericTypeIndex` is the union's shared position table — mutated
# in place as each variant's fields contribute new generics (in
# declaration order); not returned because the union accumulates it.
proc resolveVariant(app: App, shells: ResolvedModuleShells, file: parser.File, fileScope: FileScope, module: Module, variant: VariantDef, genericTypeIndex: var Table[ResolvedGenericArgumentType, int]): Result[ResolvedVariant, string] =
  var resolvedFields: seq[ResolvedArgumentDef]
  for field in variant.fields:
    let resolvedField = ? resolveArgumentDef(app, shells, file, fileScope, module, field)
    genericTypeIndex.accumulateGenericPosition(resolvedField)
    resolvedFields.add(resolvedField)
  ok(newResolvedVariant(variant, resolvedFields))

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
proc loc*(union: ResolvedUnionDef): Location = union.parsed.loc

proc findVariant*(union: ResolvedUnionDef, variant: Identifier): Result[ResolvedVariant, string] =
  if variant in union.variantIndex: ok(union.variants[union.variantIndex[variant]])
  else: err(fmt"{variant.loc} union does not contain variant `{variant.asl}`")

proc requires*(union: ResolvedUnionDef): seq[ResolvedGenericArgumentType] =
  ## One union scope: a generic name shared across variants is one
  ## shared type parameter (Rust style), so dedup by underlying Generic
  ## identity. Within-variant duplicates are already impossible
  ## (caught by validateUniqueGenericFields in resolveVariant).
  var requires = newSeq[ResolvedGenericArgumentType](union.genericTypeIndex.len)
  for genericType, index in union.genericTypeIndex:
    requires[index] = genericType
  return requires

proc resolveUnionDef*(app: App, shells: ResolvedModuleShells, file: parser.File, fileScope: FileScope,
    module: Module, union: UnionDef): Result[ResolvedUnionDef, string] =
  var resolvedVariants: seq[ResolvedVariant]
  var genericTypeIndex: Table[ResolvedGenericArgumentType, int]
  for variant in union.variants:
    let resolvedVariant = ? resolveVariant(app, shells, file, fileScope, module, variant, genericTypeIndex)
    resolvedVariants.add(resolvedVariant)
  ok(newResolvedUnionDef(union, resolvedVariants, genericTypeIndex))

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

proc requires*(data: ResolvedData): seq[ResolvedGenericArgumentType] =
  case data.kind:
  of rdkLiteral: @[]
  of rdkStruct: data.struct.requires
  of rdkUnion: data.union.requires

proc resolveDataDef*(app: App, shells: ResolvedModuleShells, file: parser.File,
    fileScope: FileScope, module: Module, data: DataDef): Result[ResolvedData, string] =
  case data.kind:
  of dbkLiteral:
    let resolvedLiteralType = ? resolveLiteralDef(file, data.literal)
    ok(newResolvedData(resolvedLiteralType))
  of ddkStruct:
    let resolvedStruct = ? resolveStructDef(app, shells, file, fileScope, module,
      data.struct)
    ok(newResolvedData(resolvedStruct))
  of ddkUnion:
    let resolvedUnion = ? resolveUnionDef(app, shells, file, fileScope, module, data.union)
    ok(newResolvedData(resolvedUnion))

# =====================================================================
# Body-level cluster
# (Getter, LiteralInitializer, KeywordArgument, StructRef, UnionRef,
#  StructInitializer, UnionInitializer, Initializer, FunctionCall,
#  Assignment, Setter, CaseBlock, MatchExpression, Expression, Statement)
#
# Every resolveX proc threads `shells: ResolvedModuleShells` — the
# table allocated by apps.nim during the declare pass — down to
# `resolveArgumentType`, which uses it to attach a stable
# ResolvedModule reference to every ResolvedModuleArgumentType.
# =====================================================================

# ---- ResolvedGetter ----

proc newResolvedGetter*(parsed: Getter): ResolvedGetter =
  ResolvedGetter(parsed: parsed)

proc parsed*(getter: ResolvedGetter): Getter = getter.parsed
proc source*(getter: ResolvedGetter): Identifier = getter.parsed.source
proc property*(getter: ResolvedGetter): Identifier = getter.parsed.property
proc loc*(getter: ResolvedGetter): Location = getter.parsed.loc

proc resolveVariable*(file: parser.File, scope: FunctionScope,
    variable: Identifier): Result[Identifier, string] =
  if variable notin scope:
    err(fmt"{variable.loc} variable `{variable.asl}` is not present in scope")
  else:
    ok(variable)

proc resolveGetter*(file: parser.File, scope: FunctionScope,
    getter: Getter): Result[ResolvedGetter, string] =
  discard ? resolveVariable(file, scope, getter.source)
  ok(newResolvedGetter(getter))

# ---- ResolvedLiteralInitializer ----

proc newResolvedLiteralInitializer*(parsed: LiteralInitializer,
    argType: ResolvedArgumentType): ResolvedLiteralInitializer =
  ResolvedLiteralInitializer(parsed: parsed, argType: argType)

proc parsed*(init: ResolvedLiteralInitializer): LiteralInitializer = init.parsed
proc argType*(init: ResolvedLiteralInitializer): ResolvedArgumentType = init.argType
proc value*(init: ResolvedLiteralInitializer): Literal = init.parsed.value
proc loc*(init: ResolvedLiteralInitializer): Location = init.parsed.loc
proc literal*(init: ResolvedLiteralInitializer): Literal = init.parsed.value

proc resolveLiteralInitializer(app: App, shells: ResolvedModuleShells,
    file: parser.File, fileScope: FileScope, module: Module,
    literalInit: LiteralInitializer): Result[
        ResolvedLiteralInitializer, string] =
  let resolvedArgType = ? resolveArgumentType(app, shells, file, fileScope, module,
    literalInit.argType)
  ok(newResolvedLiteralInitializer(literalInit, resolvedArgType))

# ---- ResolvedKeywordArgument ----

proc newResolvedKeywordArgument*(parsed: KeywordArgument,
    expression: ResolvedExpression): ResolvedKeywordArgument =
  ResolvedKeywordArgument(parsed: parsed, expression: expression)

proc parsed*(kwarg: ResolvedKeywordArgument): KeywordArgument = kwarg.parsed
proc expression*(kwarg: ResolvedKeywordArgument): ResolvedExpression = kwarg.expression
proc name*(kwarg: ResolvedKeywordArgument): Identifier = kwarg.parsed.name
proc loc*(kwarg: ResolvedKeywordArgument): Location = kwarg.parsed.loc

# ---- ResolvedStructRef ----

proc newResolvedStructRef*(parsed: StructRef, resolvedModule: ResolvedModule,
    resolvedImpls: seq[ResolvedArgumentType]): ResolvedStructRef =
  ## One-shape constructor. `resolvedImpls` is empty when the surface
  ## form was `Module { ... }` and non-empty (arity + constraint checked)
  ## when the surface form was `Module[Impl, ...] { ... }`.
  ResolvedStructRef(parsed: parsed, resolvedModule: resolvedModule,
    resolvedImpls: resolvedImpls)

proc parsed*(s: ResolvedStructRef): StructRef = s.parsed
proc resolvedModule*(s: ResolvedStructRef): ResolvedModule = s.resolvedModule
proc module*(s: ResolvedStructRef): Module = s.resolvedModule.parsed
proc resolvedImpls*(s: ResolvedStructRef): seq[ResolvedArgumentType] = s.resolvedImpls
proc loc*(s: ResolvedStructRef): Location = s.parsed.loc

# ---- ResolvedStructInitializer ----

proc newResolvedStructInitializer*(parsed: StructInitializer,
    structRef: ResolvedStructRef,
    kwargs: seq[ResolvedKeywordArgument]): ResolvedStructInitializer =
  ResolvedStructInitializer(parsed: parsed, structRef: structRef, kwargs: kwargs)

proc parsed*(struct: ResolvedStructInitializer): StructInitializer = struct.parsed
proc structRef*(struct: ResolvedStructInitializer): ResolvedStructRef = struct.structRef
proc kwargs*(struct: ResolvedStructInitializer): seq[ResolvedKeywordArgument] = struct.kwargs
proc loc*(struct: ResolvedStructInitializer): Location = struct.parsed.loc

proc resolvedImpls*(struct: ResolvedStructInitializer): seq[ResolvedArgumentType] =
  ## Delegates to the underlying structRef. Empty === bare initializer,
  ## non-empty === explicit-impls initializer.
  ##
  ## Invariant: every entry is arity- and constraint-validated at
  ## resolve time by resolveModuleArgumentType (see the module-context
  ## overload above). Downstream consumers can treat this seq as a
  ## provably valid value — no need to re-check.
  struct.structRef.resolvedImpls

# ---- ResolvedUnionRef ----

proc newResolvedUnionRef*(parsed: UnionRef, resolvedModule: ResolvedModule,
    resolvedImpls: seq[ResolvedArgumentType]): ResolvedUnionRef =
  ## One-shape constructor. `resolvedImpls` is empty when the surface
  ## form was `Module.Variant { ... }` and non-empty (arity + constraint
  ## checked) when the surface form was `Module[Impl, ...].Variant { ... }`.
  ResolvedUnionRef(parsed: parsed, resolvedModule: resolvedModule,
    resolvedImpls: resolvedImpls)

proc parsed*(u: ResolvedUnionRef): UnionRef = u.parsed
proc resolvedModule*(u: ResolvedUnionRef): ResolvedModule = u.resolvedModule
proc module*(u: ResolvedUnionRef): Module = u.resolvedModule.parsed
proc resolvedImpls*(u: ResolvedUnionRef): seq[ResolvedArgumentType] = u.resolvedImpls
proc loc*(u: ResolvedUnionRef): Location = u.parsed.loc

# ---- ResolvedUnionInitializer ----

proc newResolvedUnionInitializer*(parsed: UnionInitializer,
    unionRef: ResolvedUnionRef,
    kwargs: seq[ResolvedKeywordArgument]): ResolvedUnionInitializer =
  ResolvedUnionInitializer(parsed: parsed, unionRef: unionRef, kwargs: kwargs)

proc parsed*(init: ResolvedUnionInitializer): UnionInitializer = init.parsed
proc unionRef*(init: ResolvedUnionInitializer): ResolvedUnionRef = init.unionRef
proc kwargs*(init: ResolvedUnionInitializer): seq[ResolvedKeywordArgument] = init.kwargs
proc loc*(init: ResolvedUnionInitializer): Location = init.parsed.loc
proc module*(init: ResolvedUnionInitializer): Module = module(init.unionRef)
proc variant*(init: ResolvedUnionInitializer): Identifier = init.parsed.variant

proc resolvedImpls*(init: ResolvedUnionInitializer): seq[ResolvedArgumentType] =
  ## Delegates to the underlying unionRef. Empty === bare initializer,
  ## non-empty === explicit-impls initializer.
  ##
  ## Invariant: every entry is arity- and constraint-validated at
  ## resolve time by resolveModuleArgumentType. Downstream consumers
  ## can treat this seq as a provably valid value — no need to re-check.
  init.unionRef.resolvedImpls

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
proc loc*(init: ResolvedInitializer): Location =
  case init.kind:
  of rikLiteral: init.literal.loc
  of rikStruct: init.struct.loc
  of rikUnion: init.union.loc

# ---- ResolvedFunctionCall ----

proc newResolvedFunctionCall*(parsed: FunctionCall,
    args: seq[ResolvedExpression]): ResolvedFunctionCall =
  ResolvedFunctionCall(parsed: parsed, args: args)

proc parsed*(fncall: ResolvedFunctionCall): FunctionCall = fncall.parsed
proc args*(fncall: ResolvedFunctionCall): seq[ResolvedExpression] = fncall.args
proc loc*(fncall: ResolvedFunctionCall): Location = fncall.parsed.loc

proc resolvedImpls*(fncall: ResolvedFunctionCall): seq[ResolvedArgumentType] =
  ## Empty for the time being — the parser has no impl syntax for
  ## FunctionCall receivers. Kept as a first-class accessor so
  ## downstream code that treats StructInit/UnionInit/FunctionCall
  ## uniformly (an "impl-carrying node") can pattern-match on it.
  ##
  ## Invariant: entries would be arity- and constraint-validated at
  ## resolve time — the current always-empty seq trivially satisfies
  ## that.
  fncall.resolvedImpls

# ---- ResolvedAssignment ----

proc newResolvedAssignment*(parsed: Assignment,
    expression: ResolvedExpression): ResolvedAssignment =
  ResolvedAssignment(parsed: parsed, expression: expression)

proc parsed*(assignment: ResolvedAssignment): Assignment = assignment.parsed
proc expression*(assignment: ResolvedAssignment): ResolvedExpression = assignment.expression
proc loc*(assignment: ResolvedAssignment): Location = assignment.parsed.loc
proc target*(assignment: ResolvedAssignment): Identifier = assignment.parsed.target

# ---- ResolvedSetter ----

proc newResolvedSetter*(parsed: Setter, getter: ResolvedGetter,
    expression: ResolvedExpression): ResolvedSetter =
  ResolvedSetter(parsed: parsed, getter: getter, expression: expression)

proc parsed*(setter: ResolvedSetter): Setter = setter.parsed
proc getter*(setter: ResolvedSetter): ResolvedGetter = setter.getter
proc expression*(setter: ResolvedSetter): ResolvedExpression = setter.expression
proc loc*(setter: ResolvedSetter): Location = setter.parsed.loc

# ---- ResolvedCaseBlock ----

proc newResolvedCaseBlock*(parsed: CaseBlock, pattern: ResolvedCasePattern,
    statements: seq[ResolvedStatement]): ResolvedCaseBlock =
  ResolvedCaseBlock(parsed: parsed, pattern: pattern, statements: statements)

proc parsed*(caseBlock: ResolvedCaseBlock): CaseBlock = caseBlock.parsed
proc pattern*(caseBlock: ResolvedCaseBlock): ResolvedCasePattern = caseBlock.pattern
proc statements*(caseBlock: ResolvedCaseBlock): seq[ResolvedStatement] = caseBlock.statements
proc loc*(caseBlock: ResolvedCaseBlock): Location = caseBlock.parsed.loc

# ---- ResolvedMatchExpression ----

proc newResolvedMatchExpression*(parsed: MatchExpression,
    subject: ResolvedExpression,
    cases: seq[ResolvedCaseBlock]): ResolvedMatchExpression =
  ResolvedMatchExpression(parsed: parsed, subject: subject, cases: cases)

proc parsed*(match: ResolvedMatchExpression): MatchExpression = match.parsed
proc subject*(match: ResolvedMatchExpression): ResolvedExpression = match.subject
proc cases*(match: ResolvedMatchExpression): seq[ResolvedCaseBlock] = match.cases
proc loc*(match: ResolvedMatchExpression): Location = match.parsed.loc

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
proc loc*(expression: ResolvedExpression): Location =
  case expression.kind:
  of rekFunctionCall: expression.fncall.loc
  of rekGetter: expression.getter.loc
  of rekInitializer: expression.init.loc
  of rekMatchExpr: expression.match.loc
  of rekVariable: expression.variable.loc
  of rekLiteral: expression.literal.loc

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
proc loc*(statement: ResolvedStatement): Location =
  case statement.kind:
  of rskAssignment: statement.assignment.loc
  of rskExpr: statement.expression.loc
  of rskSetter: statement.setter.loc

# Accessor used by callers to thread bindings into scope.
proc variable*(statement: ResolvedStatement): Option[Identifier] =
  ## Returns the new binding introduced by this statement (if any).
  case statement.kind:
  of rskAssignment: some(statement.assignment.target)
  of rskExpr: none(Identifier)
  of rskSetter: none(Identifier)

# ---- Body resolve* procs ----

proc resolveFunctionCall(app: App, shells: ResolvedModuleShells,
    file: parser.File, fileScope: FileScope,
    module: Module, scope: FunctionScope,
    fncall: FunctionCall): Result[ResolvedFunctionCall, string] =
  let definedType = ? file.findDefinedType(fileScope, fncall.root)
  let funcDefs = ? definedType.findFunctionDefs(fncall.name, fncall.args.len)
  if funcDefs.len == 0:
    err(fmt"{fncall.loc} generic `{definedType.generic.name.asl}` does not have any function named `{fncall.name.asl}` with arity `{fncall.args.len}`")
  else:
    var resolvedArgs: seq[ResolvedExpression]
    for arg in fncall.args:
      let resolvedArg = ? resolveExpression(app, shells, file, fileScope, module, scope, arg)
      resolvedArgs.add(resolvedArg)
    ok(newResolvedFunctionCall(fncall, resolvedArgs))

proc resolveStructRef(app: App, shells: ResolvedModuleShells,
    file: parser.File, fileScope: FileScope, module: Module,
    structRef: StructRef): Result[ResolvedStructRef, string] =
  ## Resolves a StructRef into the one-shape (module + resolvedImpls).
  ## Validates the "receiver-declares-requires ↔ impls-provided" match
  ## and delegates to resolveModuleArgumentType so the resolvedImpls
  ## seq is arity- and constraint-checked at resolve time.
  let structModule = ? file.findModule(fileScope, structRef.module)
  if structRef.impls.len == 0 and structModule.requires.isSome:
    return err(fmt"{structRef.loc} module `{structModule.name.asl}` declares requires; initializer must specify impl types as `{structModule.name.asl}[...]`")
  if structRef.impls.len > 0 and not structModule.requires.isSome:
    return err(fmt"{structRef.loc} module `{structModule.name.asl}` has no requires block; initializer must not specify impl types")
  let resolvedRoot = lookupShell(shells, structModule)
  if structRef.impls.len == 0:
    return ok(newResolvedStructRef(structRef, resolvedRoot, @[]))
  # Reuse the module-context argType resolver so arity + constraint
  # validation stays in one place. Build a synthetic ArgumentType from
  # the parser StructRef's (module, impls, loc) and unwrap its
  # resolvedImpls after the check.
  let syntheticArgType = newArgumentType(structRef.module, structRef.impls, structRef.loc)
  let resolvedArgType = ? resolveArgumentType(app, shells, file, fileScope, module, syntheticArgType)
  ok(newResolvedStructRef(structRef, resolvedRoot, resolvedArgType.module.impls))

proc resolveStructInitializer(app: App, shells: ResolvedModuleShells,
    file: parser.File, fileScope: FileScope, module: Module, scope: FunctionScope,
    struct: StructInitializer): Result[ResolvedStructInitializer, string] =
  let resolvedStructRef = ? resolveStructRef(app, shells, file, fileScope, module, struct.structRef)
  let structModule = module(resolvedStructRef)
  var structBlock = ? structModule.struct(struct.loc)
  if struct.kwargs.len != structBlock.fields.len:
    err(fmt"{struct.loc} struct `{structModule.name.asl}` expects `{structBlock.fields.len}` but `{struct.kwargs.len}` were given")
  else:
    var resolvedKeywordArgs = newSeq[ResolvedKeywordArgument](structBlock.fields.len)
    for kwarg in struct.kwargs:
      let fieldId = ? structBlock.findFieldId(kwarg.name)
      let resolvedExpression = ? resolveExpression(app, shells, file, fileScope,
        module, scope, kwarg.expression)
      resolvedKeywordArgs[fieldId] = newResolvedKeywordArgument(kwarg,
        resolvedExpression)
    ok(newResolvedStructInitializer(struct, resolvedStructRef, resolvedKeywordArgs))

proc resolveUnionRef(app: App, shells: ResolvedModuleShells,
    file: parser.File, fileScope: FileScope, module: Module,
    unionRef: UnionRef): Result[ResolvedUnionRef, string] =
  ## Resolves a UnionRef into the one-shape (module + resolvedImpls).
  ## Empty impls drive leave-as-is inference at the analyzer; non-empty
  ## impls are arity- and constraint-checked here via
  ## resolveModuleArgumentType so the analyzer can seed its
  ## GenericImplMap from the seq directly.
  let unionModule = ? file.findModule(fileScope, unionRef.module)
  let resolvedRoot = lookupShell(shells, unionModule)
  if unionRef.impls.len == 0:
    return ok(newResolvedUnionRef(unionRef, resolvedRoot, @[]))
  let syntheticArgType = newArgumentType(unionRef.module, unionRef.impls, unionRef.loc)
  let resolvedArgType = ? resolveArgumentType(app, shells, file, fileScope, module, syntheticArgType)
  ok(newResolvedUnionRef(unionRef, resolvedRoot, resolvedArgType.module.impls))

proc resolveUnionInitializer(app: App, shells: ResolvedModuleShells,
    file: parser.File, fileScope: FileScope,
    module: Module, scope: FunctionScope,
    unionInit: UnionInitializer): Result[ResolvedUnionInitializer, string] =
  let resolvedUnionRef = ? resolveUnionRef(app, shells, file, fileScope, module, unionInit.unionRef)
  let initModule = module(resolvedUnionRef)
  let union = ? initModule.union(unionInit.loc)
  let variant = ? union.findVariant(unionInit.variant)
  if unionInit.kwargs.len != variant.fields.len:
    return err(fmt"{unionInit.loc} union `{initModule.name.asl}` expects `{variant.fields.len}` but `{unionInit.kwargs.len}` were given")
  var resolvedKeywordArgs = newSeq[ResolvedKeywordArgument](
    variant.fields.len)
  for kwarg in unionInit.kwargs:
    let fieldId = ? variant.findFieldId(kwarg.name)
    let resolvedExpression = ? resolveExpression(app, shells, file, fileScope,
      module, scope, kwarg.expression)
    resolvedKeywordArgs[fieldId] = newResolvedKeywordArgument(kwarg,
      resolvedExpression)
  ok(newResolvedUnionInitializer(unionInit, resolvedUnionRef, resolvedKeywordArgs))

proc resolveInitializer(app: App, shells: ResolvedModuleShells,
    file: parser.File, fileScope: FileScope,
    module: Module, scope: FunctionScope,
    initializer: Initializer): Result[ResolvedInitializer, string] =
  case initializer.kind:
  of ikLiteral:
    let resolvedLiteralInit = ? resolveLiteralInitializer(app, shells, file, fileScope,
      module, initializer.literal)
    ok(newResolvedInitializer(resolvedLiteralInit))
  of ikStruct:
    let resolvedStructInit = ? resolveStructInitializer(app, shells, file, fileScope,
      module, scope, initializer.struct)
    ok(newResolvedInitializer(resolvedStructInit))
  of ikUnion:
    let resolvedUnionInit = ? resolveUnionInitializer(app, shells, file, fileScope,
      module, scope, initializer.union)
    ok(newResolvedInitializer(resolvedUnionInit))

proc resolveCaseBlock(app: App, shells: ResolvedModuleShells,
    file: parser.File, fileScope: FileScope,
    module: Module, scope: FunctionScope,
    caseBlock: CaseBlock): Result[ResolvedCaseBlock, string] =
  let resolvedCasePattern = ? resolveCasePattern(caseBlock.pattern)
  var resolvedStatements: seq[ResolvedStatement]
  var childScope = scope # create a child scope to enable shadowing

  for binding in caseBlock.pattern.bindings:
    childScope.incl(binding)

  for statement in caseBlock.statements:
    let resolvedStatement = ? resolveStatement(app, shells, file, fileScope, module,
      childScope, statement)
    resolvedStatements.add(resolvedStatement)
    if resolvedStatement.variable.isSome:
      childScope.incl(resolvedStatement.variable.get)
  ok(newResolvedCaseBlock(caseBlock, resolvedCasePattern, resolvedStatements))

proc resolveMatchExpression(app: App, shells: ResolvedModuleShells,
    file: parser.File, fileScope: FileScope,
    module: Module, scope: FunctionScope,
    match: MatchExpression): Result[ResolvedMatchExpression, string] =
  let resolvedSubject = ? resolveExpression(app, shells, file, fileScope, module, scope,
    match.subject)
  var resolvedCaseBlocks: seq[ResolvedCaseBlock]
  for caseBlock in match.cases:
    let resolvedCaseBlock = ? resolveCaseBlock(app, shells, file, fileScope, module,
      scope, caseBlock)
    resolvedCaseBlocks.add(resolvedCaseBlock)
  ok(newResolvedMatchExpression(match, resolvedSubject, resolvedCaseBlocks))

proc resolveExpression*(app: App, shells: ResolvedModuleShells,
    file: parser.File, fileScope: FileScope,
    module: Module, scope: FunctionScope,
    expression: Expression): Result[ResolvedExpression, string] =
  case expression.kind:
  of ekLiteral:
    ok(newResolvedExpression(expression.literal))
  of ekGetter:
    let resolvedGetter = ? resolveGetter(file, scope, expression.getter)
    ok(newResolvedExpression(resolvedGetter))
  of ekVariable:
    let resolvedVariable = ? resolveVariable(file, scope, expression.variable)
    ok(newResolvedExpression(resolvedVariable))
  of ekFnCall:
    let resolvedFunctionCall = ? resolveFunctionCall(app, shells, file, fileScope,
      module, scope, expression.fncall)
    ok(newResolvedExpression(resolvedFunctionCall))
  of ekInitializer:
    let resolvedInitializer = ? resolveInitializer(app, shells, file, fileScope, module,
      scope, expression.initializer)
    ok(newResolvedExpression(resolvedInitializer))
  of ekMatch:
    let resolvedMatchExpr = ? resolveMatchExpression(app, shells, file, fileScope,
      module, scope, expression.match)
    ok(newResolvedExpression(resolvedMatchExpr))

proc resolveAssignment(app: App, shells: ResolvedModuleShells,
    file: parser.File, fileScope: FileScope,
    module: Module, scope: FunctionScope,
    assignment: Assignment): Result[ResolvedAssignment, string] =
  let resolvedExpression = ? resolveExpression(app, shells, file, fileScope, module,
    scope, assignment.expression)
  ok(newResolvedAssignment(assignment, resolvedExpression))

proc resolveSetter(app: App, shells: ResolvedModuleShells,
    file: parser.File, fileScope: FileScope,
    module: Module, scope: FunctionScope,
    setter: Setter): Result[ResolvedSetter, string] =
  let resolvedGetter = ? resolveGetter(file, scope, setter.target)
  let resolvedExpression = ? resolveExpression(app, shells, file, fileScope, module,
    scope, setter.expression)
  ok(newResolvedSetter(setter, resolvedGetter, resolvedExpression))

proc resolveStatement*(app: App, shells: ResolvedModuleShells,
    file: parser.File, fileScope: FileScope,
    module: Module, scope: FunctionScope,
    statement: Statement): Result[ResolvedStatement, string] =
  case statement.kind:
  of skExpr:
    let resolvedExpression = ? resolveExpression(app, shells, file, fileScope, module,
      scope, statement.expression)
    ok(newResolvedStatement(resolvedExpression))
  of skAssignment:
    let resolvedAssignment = ? resolveAssignment(app, shells, file, fileScope, module,
      scope, statement.assignment)
    ok(newResolvedStatement(resolvedAssignment))
  of skSetter:
    let resolvedMutation = ? resolveSetter(app, shells, file, fileScope, module, scope,
      statement.setter)
    ok(newResolvedStatement(resolvedMutation))

# =====================================================================
# Functions (UserFunction, tagged Function)
# =====================================================================

# ---- ResolvedUserFunction ----

proc newResolvedUserFunction*(parsed: UserFunction,
    funcDef: ResolvedFunctionDef,
    statements: seq[ResolvedStatement]): ResolvedUserFunction =
  ResolvedUserFunction(parsed: parsed, funcDef: funcDef, statements: statements)

proc parsed*(function: ResolvedUserFunction): UserFunction = function.parsed
proc def*(function: ResolvedUserFunction): ResolvedFunctionDef = function.funcDef
proc statements*(function: ResolvedUserFunction): seq[ResolvedStatement] = function.statements
proc loc*(function: ResolvedUserFunction): Location = function.parsed.loc

proc resolveUserFunction*(app: App, shells: ResolvedModuleShells,
    file: parser.File, fileScope: FileScope, module: Module,
    function: UserFunction): Result[ResolvedUserFunction, string] =
  if function.decorators.len > 0:
    return err(fmt"{function.loc} todo: resolve decorators in user function")

  let resolvedFunctionDef = ? resolveFunctionDef(app, shells, file, fileScope, module, function.def)

  var scope: FunctionScope
  for arg in resolvedFunctionDef.args:
    scope.incl(arg.name)

  var resolvedStatements: seq[ResolvedStatement]
  for statement in function.statements:
    let resolvedStatement = ? resolveStatement(app, shells, file, fileScope, module,
      scope, statement)
    resolvedStatements.add(resolvedStatement)
    if resolvedStatement.variable.isSome:
      scope.incl(resolvedStatement.variable.get)

  ok(newResolvedUserFunction(function, resolvedFunctionDef, resolvedStatements))

# ---- ResolvedFunction (tagged union) ----

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

proc def*(function: ResolvedFunction): ResolvedFunctionDef =
  case function.kind:
  of rfkExtern: function.extern.def
  of rfkUser: function.user.def
proc loc*(function: ResolvedFunction): Location =
  case function.kind:
  of rfkExtern: function.extern.loc
  of rfkUser: function.user.loc

proc resolveFunction*(app: App, shells: ResolvedModuleShells,
    file: parser.File, fileScope: FileScope, module: Module,
    function: Function): Result[ResolvedFunction, string] =
  case function.kind:
  of fkUser:
    let resolvedUserFunction = ? resolveUserFunction(app, shells, file, fileScope,
      module, function.user)
    ok(newResolvedFunction(resolvedUserFunction))
  of fkExtern:
    let resolvedExternFunction = ? resolveExternFunction(app, shells, file, fileScope,
      module, function.extern)
    ok(newResolvedFunction(resolvedExternFunction))

# =====================================================================
# Module + Generic
#
# Includes the shell/populate mechanism used by the two-pass resolver
# — `newResolvedModuleShell` allocates an empty shell for every parser
# Module during the declare pass in apps.nim, and `populate` fills it
# in when its define pass completes.
# =====================================================================

# ---- Module: raw ctor, shell, populate ----

proc newResolvedModuleInternal(parsed: Module,
    requires: seq[ResolvedGenericArgumentType],
    data: Option[ResolvedData],
    funcDefIndex: Table[ResolvedFunctionDef, int],
    funcNameArityIndex: Table[Identifier, Table[int, seq[int]]],
    functions: seq[ResolvedFunction]): ResolvedModule =
  ## Raw constructor used by the front-door `newResolvedModule`, which
  ## computes the two indices from the function list.
  ResolvedModule(parsed: parsed, requires: requires, data: data,
    funcDefIndex: funcDefIndex, funcNameArityIndex: funcNameArityIndex,
    functions: functions)

proc newResolvedModuleShell*(parsed: Module): ResolvedModule =
  ## Zero-initialised ResolvedModule carrying only its parser back-ref.
  ## Every parser Module in the app gets one shell during the declare
  ## pass so ResolvedModuleArgumentType.resolvedModule always resolves.
  ResolvedModule(parsed: parsed)

proc populate(module: ResolvedModule,
    requires: seq[ResolvedGenericArgumentType],
    data: Option[ResolvedData],
    functions: seq[ResolvedFunction],
    funcDefIndex: Table[ResolvedFunctionDef, int],
    funcNameArityIndex: Table[Identifier, Table[int, seq[int]]]) =
  ## Fill in a shell ResolvedModule after the define pass has walked
  ## the module. Called once per module — callers rely on the shell
  ## staying pristine until the define pass completes.
  module.requires = requires
  module.data = data
  module.functions = functions
  module.funcDefIndex = funcDefIndex
  module.funcNameArityIndex = funcNameArityIndex

proc buildFuncNameArityIndex(funcDefs: seq[ResolvedFunctionDef]): Table[Identifier, Table[int, seq[int]]] =
  ## Positions of function definitions indexed by name then arity —
  ## drives overload lookup at call sites. Used by both ResolvedModule
  ## and ResolvedGeneric (see below).
  for id, funcDef in funcDefs:
    if funcDef.name notin result:
      result[funcDef.name] = initTable[int, seq[int]]()
    if funcDef.arity notin result[funcDef.name]:
      result[funcDef.name][funcDef.arity] = newSeq[int]()
    result[funcDef.name][funcDef.arity].add(id)

# ---- ResolvedModule front-door constructor + helpers ----

proc newResolvedModule*(parsed: Module, requires: seq[ResolvedGenericArgumentType], data: Option[ResolvedData], functions: seq[ResolvedFunction]): ResolvedModule =
  ## Full-construction path — used by call sites that don't participate
  ## in the shell/populate two-pass (currently only tests). Regular
  ## resolution uses `newResolvedModuleShell` + `populate` in
  ## `resolveModule` below.
  var funcDefIndex: Table[ResolvedFunctionDef, int]
  var funcDefs: seq[ResolvedFunctionDef]
  for id, function in functions:
    assert(function.def notin funcDefIndex, fmt"NOTE: should be unreachable {function.def.asl}")
    funcDefIndex[function.def] = id
    funcDefs.add(function.def)
  newResolvedModuleInternal(parsed, requires, data, funcDefIndex,
    buildFuncNameArityIndex(funcDefs), functions)

proc populateResolvedModule(shell: ResolvedModule,
    requires: seq[ResolvedGenericArgumentType],
    data: Option[ResolvedData],
    functions: seq[ResolvedFunction]) =
  ## Compute the funcDef and funcNameArity indices from the resolved
  ## functions, then hand off to the shell's `populate`.
  var funcDefIndex: Table[ResolvedFunctionDef, int]
  var funcDefs: seq[ResolvedFunctionDef]
  for id, function in functions:
    assert(function.def notin funcDefIndex, fmt"NOTE: should be unreachable {function.def.asl}")
    funcDefIndex[function.def] = id
    funcDefs.add(function.def)
  shell.populate(requires, data, functions, funcDefIndex,
    buildFuncNameArityIndex(funcDefs))

proc parsed*(module: ResolvedModule): Module = module.parsed
proc requires*(module: ResolvedModule): seq[ResolvedGenericArgumentType] = module.requires
proc data*(module: ResolvedModule): Option[ResolvedData] = module.data
proc functions*(module: ResolvedModule): seq[ResolvedFunction] = module.functions
proc funcDefIndex*(module: ResolvedModule): Table[ResolvedFunctionDef, int] = module.funcDefIndex
proc funcNameArityIndex*(module: ResolvedModule): Table[Identifier, Table[int, seq[int]]] = module.funcNameArityIndex
proc name*(module: ResolvedModule): Identifier = module.parsed.name
proc loc*(module: ResolvedModule): Location = module.parsed.loc
proc self*(module: ResolvedModule): ResolvedModuleArgumentType =
  var impls: seq[ResolvedArgumentType]
  for generic in module.requires:
    let argType = newResolvedArgumentType(generic)
    impls.add(argType)
  newResolvedModuleArgumentType(module, impls, newLocation())

proc hash*(a: ResolvedModule): Hash = a.parsed.hash
proc `==`*(a, b: ResolvedModule): bool = a.hash == b.hash

proc findFunctionDef*(module: ResolvedModule, funcDef: ResolvedFunctionDef): Option[ResolvedFunctionDef] =
  if funcDef notin module.funcDefIndex:
    none(ResolvedFunctionDef)
  else:
    some(module.functions[module.funcDefIndex[funcDef]].def)

proc findFunctionDefs*(module: ResolvedModule, name: Identifier, arity: int, public: bool): Result[seq[ResolvedFunctionDef], string] =
  ## Overload-lookup entry point — returns every function definition
  ## that matches `name` + `arity`, optionally filtered to `public` only
  ## (for external-call receivers). Uniqueness is left to the caller's
  ## overload-selection step (see analyzer/body.nim's analyzeFunctionCall).
  if name notin module.funcNameArityIndex:
    err(fmt"{name.loc} module `{module.name.asl}` does not have a function named `{name.asl}`")
  elif arity notin module.funcNameArityIndex[name]:
    err(fmt"{name.loc} module `{module.name.asl}` does not have a function named `{name.asl}` with arity `{arity}`")
  else:
    let funcDefs = module.funcNameArityIndex[name][arity].mapIt(module.functions[it].def)
    ok(if public: funcDefs.filterIt(it.public) else: funcDefs)

proc validateRequiresConstraints(module: Module): Result[void, string] =
  ## Enforces the two structural requires-block constraints:
  ##   1. Generic names inside `requires(...)` must be unique.
  ##   2. `requires` pairs with a `struct` data block — not literal, not union,
  ##      not absent. The no-generic-fields constraint is enforced
  ##      post-resolution.
  ##
  ## `requires` is an internal feature — undocumented and not promoted to
  ## end users — but no name whitelist is enforced here: any module that
  ## declares `requires` and satisfies these structural rules is accepted,
  ## so future internal types (List, dynamic containers, etc.) can adopt
  ## the same phantom-type machinery without editing this proc.
  if module.requires.isNone: return ok()
  let requires = module.requires.get
  var seen: HashSet[Identifier]
  for generic in requires.generics:
    if generic in seen:
      return err(fmt"{generic.loc} duplicate generic `{generic.asl}` in requires block")
    seen.incl(generic)
  if module.data.isNone:
    return err(fmt"{requires.loc} module `{module.name.asl}` declares requires but has no data block; requires must pair with a struct")
  case module.data.get.kind:
  of ddkStruct: ok()
  of dbkLiteral, ddkUnion:
    err(fmt"{module.data.get.loc} module `{module.name.asl}` declares requires but data block is not a struct")

proc resolveModule*(app: App, shells: ResolvedModuleShells, file: parser.File,
    fileScope: FileScope, module: Module): Result[ResolvedModule, string] =
  ## Fill in the shell allocated for this parser Module during the
  ## declare pass. `resolveArgumentType` (called transitively from
  ## resolveDataDef / resolveFunction) may already have handed out
  ## `ResolvedModuleArgumentType` values pointing at this shell —
  ## populating it here makes those forward references complete.
  if module.decorators.len > 0:
    return err("todo: resolve decorators")

  ? validateRequiresConstraints(module)

  var resolvedRequires: seq[ResolvedGenericArgumentType]
  if module.requires.isSome:
    for generic in module.requires.get.generics:
      let definedType = ? file.findDefinedType(fileScope, generic)
      case definedType.kind:
      of dtkModule:
        return err(fmt"{generic.loc} type `{generic.asl}` is a module but expected generic")
      of dtkGeneric:
        resolvedRequires.add(newResolvedGenericArgumentType(definedType.generic, generic.loc))

  var resolvedData: Option[ResolvedData]
  if module.data.isSome:
    let resolvedDataDef = ? resolveDataDef(app, shells, file, fileScope, module,
      module.data.get)
    resolvedData = some(resolvedDataDef)

  # NOTE: Infer requires list if not explicitly mentioned.
  if module.requires.isNone and resolvedData.isSome:
    resolvedRequires = resolvedData.get.requires

  # Constraint 3b (post-resolution): when requires is declared, the struct
  # block cannot have any generic fields — phantom types live in the
  # signature, not the data.
  if module.requires.isSome and resolvedData.isSome:
    let structRequires = resolvedData.get.struct.requires
    if structRequires.len > 0:
      let firstGeneric = structRequires[0]
      return err(fmt"{firstGeneric.loc} module `{module.name.asl}` declares requires but struct field is typed as a generic — phantom struct cannot have generic fields")

  var resolvedFunctions: seq[ResolvedFunction]
  for function in module.functions:
    let resolvedFunction = ? resolveFunction(app, shells, file, fileScope, module,
      function)
    resolvedFunctions.add(resolvedFunction)

  # `shells` always carries a shell for every parser Module in the app
  # (allocated by apps.nim's declare pass). Look it up and populate.
  assert(module in shells, fmt"UNREACHABLE: no shell allocated for module `{module.name.asl}`")
  let shell = shells[module]
  populateResolvedModule(shell, resolvedRequires, resolvedData, resolvedFunctions)
  ok(shell)

# ---- ResolvedGeneric: raw ctor + front-door ----

proc newResolvedGenericInternal(parsed: Generic,
    funcDefs: seq[ResolvedFunctionDef],
    funcDefIndex: Table[ResolvedFunctionDef, int],
    funcNameArityIndex: Table[Identifier, Table[int, seq[int]]]): ResolvedGeneric =
  ## Raw constructor used by the front-door `newResolvedGeneric`, which
  ## computes the two indices from the funcDef list.
  ResolvedGeneric(parsed: parsed, funcDefs: funcDefs,
    funcDefIndex: funcDefIndex, funcNameArityIndex: funcNameArityIndex)

proc newResolvedGeneric*(parsed: Generic, funcDefs: seq[ResolvedFunctionDef]): ResolvedGeneric =
  var funcDefIndex: Table[ResolvedFunctionDef, int]
  for id, funcDef in funcDefs:
    assert(funcDef notin funcDefIndex, "UNREACHABLE: generic resolution broke due to duplicated function definition")
    funcDefIndex[funcDef] = id
  newResolvedGenericInternal(parsed, funcDefs, funcDefIndex,
    buildFuncNameArityIndex(funcDefs))

proc parsed*(generic: ResolvedGeneric): Generic = generic.parsed
proc funcDefs*(generic: ResolvedGeneric): seq[ResolvedFunctionDef] = generic.funcDefs
proc funcDefIndex*(generic: ResolvedGeneric): Table[ResolvedFunctionDef, int] = generic.funcDefIndex
proc funcNameArityIndex*(generic: ResolvedGeneric): Table[Identifier, Table[int, seq[int]]] = generic.funcNameArityIndex
proc self*(generic: ResolvedGeneric): Generic = generic.parsed
proc public*(generic: ResolvedGeneric): bool = generic.parsed.public
proc name*(generic: ResolvedGeneric): Identifier = generic.parsed.name
proc loc*(generic: ResolvedGeneric): Location = generic.parsed.loc
proc hash*(a: ResolvedGeneric): Hash = a.parsed.hash
proc `==`*(a, b: ResolvedGeneric): bool = a.hash == b.hash

proc concreteImpls*(generic: ResolvedGeneric, concrete: ResolvedArgumentType): seq[ResolvedFunctionDef] =
  var concreteFuncDefs: seq[ResolvedFunctionDef]
  for def in generic.funcDefs:
    concreteFuncDefs.add(def.concreteFunctionDef(concrete, generic.parsed))
  return concreteFuncDefs

proc findFunctionDef*(generic: ResolvedGeneric, funcDef: ResolvedFunctionDef): Option[ResolvedFunctionDef] =
  if funcDef notin generic.funcDefIndex:
    none(ResolvedFunctionDef)
  else:
    some(generic.funcDefs[generic.funcDefIndex[funcDef]])

proc findFunctionDefs*(generic: ResolvedGeneric, name: Identifier, arity: int): Result[seq[ResolvedFunctionDef], string] =
  ## Overload-lookup for generic funcDefs — every funcDef inside a
  ## generic is implicitly public (per grammar), so no public filter.
  if name notin generic.funcNameArityIndex:
    err(fmt"{name.loc} generic `{generic.name.asl}` does not have a function named `{name.asl}`")
  elif arity notin generic.funcNameArityIndex[name]:
    err(fmt"{name.loc} generic `{generic.name.asl}` does not have a function named `{name.asl}` with arity `{arity}`")
  else:
    ok(generic.funcNameArityIndex[name][arity].mapIt(generic.funcDefs[it]))

proc resolveGeneric*(app: App, shells: ResolvedModuleShells, file: parser.File, fileScope: FileScope, generic: Generic): Result[ResolvedGeneric, string] =
  if generic.decorators.len > 0:
    return err(fmt"{generic.loc} todo: resolve generic decorators")

  var resolvedFunctionDefs: seq[ResolvedFunctionDef]
  for funcDef in generic.funcDefs:
    let resolvedFunctionDef = ? resolveFunctionDef(app, shells, file, fileScope, generic, funcDef)
    resolvedFunctionDefs.add(resolvedFunctionDef)

  ok(newResolvedGeneric(generic, resolvedFunctionDefs))

# =====================================================================
# DefinedType umbrella
# =====================================================================

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

proc name*(definedType: ResolvedDefinedType): Identifier =
  case definedType.kind:
  of rdtkModule: definedType.module.name
  of rdtkGeneric: definedType.generic.name

proc loc*(definedType: ResolvedDefinedType): Location =
  case definedType.kind:
  of rdtkModule: definedType.module.loc
  of rdtkGeneric: definedType.generic.loc

proc resolveDefinedType*(app: App, shells: ResolvedModuleShells, file: parser.File, fileScope: FileScope, id: int, definedType: DefinedType): Result[ResolvedDefinedType, string] =
  case definedType.kind:
  of dtkGeneric:
    let resolvedGeneric = ? resolveGeneric(app, shells, file, fileScope, definedType.generic)
    ok(newResolvedDefinedType(id, resolvedGeneric))
  of dtkModule:
    let resolvedModule = ? resolveModule(app, shells, file, fileScope, definedType.module)
    ok(newResolvedDefinedType(id, resolvedModule))
