import options, results, strformat, tables, hashes

import parser/main as parser
import defanalyzer/main as defanalyzer
import analyzer/main as analyzer

# Works out the concrete types for a call's target. A call records the types
# it passes (`fncallImpls`), but inside a generic function those can still
# mention the function's own type parameters. `funcImpls` says what this copy
# of the function set them to, so filling it in gives the fully concrete types
# that name the exact callee copy.
proc calleeImpls(fncallImpls: AnalyzedImplMap, funcImpls: AnalyzedImplMap): AnalyzedImplMap =
  var concreteImpls: AnalyzedImplMap
  for generic, impl in fncallImpls:
    concreteImpls[generic] = impl.concrete(funcImpls)
  concreteImpls

type
  # FunctionId — one fully-typed copy of a function; numbers are unique program-wide.
  FunctionId* = distinct int

  # ValueId — one value inside a single function copy; numbered from zero per copy.
  ValueId = distinct int

  # FunctionRef — which function copy we mean: module + concrete function + impls.
  FunctionRefKind = enum frkUser, frkExtern, frkGenerated
  FunctionRef = ref object
    module: AnalyzedModule
    impls: AnalyzedImplMap
    case kind: FunctionRefKind
    of frkUser: user: AnalyzedUserFunction
    of frkExtern: extern: AnalyzedExternFunction
    of frkGenerated: generated: AnalyzedFunctionDef

  # FunctionCallNode — a call step; the callee copy and the values passed to it.
  FunctionCallNode = ref object
    callee: FunctionId
    args: seq[ValueId]

  # BranchNode / MatchNode — a match on a value and the branches it covers.
  # Each branch owns the `nodes` of its body, so they are evaluated only when
  # that branch is taken.
  BranchNode = object
    pattern: AnalyzedCasePattern
    nodes: seq[Node]
    resultId: ValueId
  MatchNode = ref object
    subject: ValueId
    branches: seq[BranchNode]

  # TryNode — a call whose Err result returns from the enclosing function.
  TryNode = ref object
    call: FunctionCallNode
    returns: AnalyzedArgumentType

  # LiteralNode — a parsed constant and the module type it adopted.
  LiteralNode = ref object
    literal: Literal
    returns: AnalyzedArgumentType

  # InitField — one field of an aggregate initializer: the field name + its value.
  InitField = object
    field: Identifier
    value: ValueId

  # UnionInitNode — constructs a union value: finalized type, variant, field values.
  UnionInitNode = ref object
    returns: AnalyzedArgumentType
    variant: Identifier
    fields: seq[InitField]

  # StructInitNode — constructs a struct value: finalized type + field values (no variant).
  StructInitNode = ref object
    returns: AnalyzedArgumentType
    fields: seq[InitField]

  # VariantFieldNode — projects one field out of a matched union value: the
  # matched `subject`, the `variant` it matched as, the `field` pulled out, and
  # that field's finalized type.
  VariantFieldNode = ref object
    subject: ValueId
    variant: Identifier
    field: Identifier
    returns: AnalyzedArgumentType

  # StructFieldNode — reads one field out of a struct value: the `source` value,
  # the `field` read, and that field's finalized type. (The struct twin of
  # VariantFieldNode — no variant, since a struct has none.)
  StructFieldNode = ref object
    source: ValueId
    field: Identifier
    returns: AnalyzedArgumentType

  # StructSetterNode — a functional field update: a new struct equal to `source`
  # with `field` replaced by `value`. `returns` is the (struct) result type.
  StructSetterNode = ref object
    source: ValueId
    field: Identifier
    value: ValueId
    returns: AnalyzedArgumentType

  # Node — one value-producing step in a copy's body, tagged by kind.
  NodeKind = enum
    nkCall, nkMatch, nkTry, nkLiteral, nkUnion, nkStruct, nkVariantField, nkStructField, nkStructSetter
  Node = object
    id: ValueId
    case kind: NodeKind
    of nkCall: fncall: FunctionCallNode
    of nkMatch: match: MatchNode
    of nkTry: tryCall: TryNode
    of nkLiteral: literal: LiteralNode
    of nkUnion: unionInit: UnionInitNode
    of nkStruct: structInit: StructInitNode
    of nkVariantField: variantField: VariantFieldNode
    of nkStructField: structField: StructFieldNode
    of nkStructSetter: structSetter: StructSetterNode

  # MonoUserFunction — the built body of one user-function copy.
  MonoUserFunction = ref object
    params: seq[ValueId]
    nodes: seq[Node]
    resultId: ValueId

  # MonoExternFunction — one extern copy: the FFI declaration and the concrete
  # types its generics were set to (what a kind-tagged C wrapper will need).
  MonoExternFunction = ref object
    extern: AnalyzedExternFunction
    impls: AnalyzedImplMap

  # MonoInstance — one monomorphized function copy, what a FunctionId names.
  MonoInstanceKind* = enum mikUser, mikExtern
  MonoInstance* = object
    case kind: MonoInstanceKind
    of mikUser: user: MonoUserFunction
    of mikExtern: extern: MonoExternFunction

  # FunctionScope — the work area for building one function copy.
  FunctionScope = ref object
    counter: int
    argMap: Table[Identifier, ValueId]
    nodes: seq[Node]

  # Monomorphizer — drives the whole pass; one for the entire program.
  Monomorphizer = ref object
    counter: int
    visiting: Table[FunctionRef, FunctionId]
    visited: Table[FunctionRef, FunctionId]
    instances: Table[FunctionId, MonoInstance]

  # MonoApp — the monomorphized program: every built copy keyed by id,
  # plus the entry copy's id.
  MonoApp* = object
    instances: Table[FunctionId, MonoInstance]
    entry: FunctionId

# FunctionId — a generic function used with different concrete types becomes
# several copies, each with its own program-unique number.
proc `==`*(a, b: FunctionId): bool {.borrow.}
proc hash*(a: FunctionId): Hash {.borrow.}

# FunctionRef — two calls that pick the same module, function, and types give an
# equal FunctionRef, so each copy is built only once. The function is held by
# its concrete kind, so each later stage sees exactly the shape it handles
# instead of re-casing on an AnalyzedFunction.
proc newFunctionRef(module: AnalyzedModule, user: AnalyzedUserFunction, impls: AnalyzedImplMap): FunctionRef =
  FunctionRef(kind: frkUser, module: module, impls: impls, user: user)

proc newFunctionRef(module: AnalyzedModule, extern: AnalyzedExternFunction, impls: AnalyzedImplMap): FunctionRef =
  FunctionRef(kind: frkExtern, module: module, impls: impls, extern: extern)

proc newFunctionRef(module: AnalyzedModule, generated: AnalyzedFunctionDef, impls: AnalyzedImplMap): FunctionRef =
  FunctionRef(kind: frkGenerated, module: module, impls: impls, generated: generated)

proc hash(funcRef: FunctionRef): Hash =
  let functionHash =
    case funcRef.kind:
    of frkUser: funcRef.user.hash
    of frkExtern: funcRef.extern.hash
    of frkGenerated: funcRef.generated.hash
  var acc = funcRef.module.hash !& funcRef.kind.ord.hash !& functionHash
  for _, impl in funcRef.impls:
    acc = acc !& impl.hash
  return acc

proc `==`(a, b: FunctionRef): bool = a.hash == b.hash

# FunctionCallNode — one call step inside a copy's body; the node's own id is
# the value it returns.
proc newFunctionCallNode(callee: FunctionId, args: seq[ValueId]): FunctionCallNode =
  FunctionCallNode(callee: callee, args: args)

# MatchNode — each BranchNode names the pattern it covers and the value it
# produces; the match node's own id is the value of whichever branch runs.
proc newMatchNode(subject: ValueId, branches: seq[BranchNode]): MatchNode =
  MatchNode(subject: subject, branches: branches)

# TryNode — like a call, but an Err result returns from the enclosing function.
# `returns` is the finalized type of the unwrapped Ok value; codegen emits the
# early return on an Err.
proc newTryNode(call: FunctionCallNode, returns: AnalyzedArgumentType): TryNode =
  TryNode(call: call, returns: returns)

# LiteralNode — a literal value and its finalized type.
proc newLiteralNode(literal: Literal, returns: AnalyzedArgumentType): LiteralNode =
  LiteralNode(literal: literal, returns: returns)

# UnionInitNode — constructs a union value.
proc newUnionInitNode(returns: AnalyzedArgumentType, variant: Identifier, fields: seq[InitField]): UnionInitNode =
  UnionInitNode(returns: returns, variant: variant, fields: fields)

# StructInitNode — constructs a struct value (a struct has no variant — the
# only difference from UnionInitNode).
proc newStructInitNode(returns: AnalyzedArgumentType, fields: seq[InitField]): StructInitNode =
  StructInitNode(returns: returns, fields: fields)

# VariantFieldNode — projects one field out of a matched union value.
proc newVariantFieldNode(subject: ValueId, variant: Identifier, field: Identifier, returns: AnalyzedArgumentType): VariantFieldNode =
  VariantFieldNode(subject: subject, variant: variant, field: field, returns: returns)

# StructFieldNode — reads one field out of a struct value.
proc newStructFieldNode(source: ValueId, field: Identifier, returns: AnalyzedArgumentType): StructFieldNode =
  StructFieldNode(source: source, field: field, returns: returns)

# StructSetterNode — a functional field update producing a new struct.
proc newStructSetterNode(source: ValueId, field: Identifier, value: ValueId, returns: AnalyzedArgumentType): StructSetterNode =
  StructSetterNode(source: source, field: field, value: value, returns: returns)

# Node — wraps each node kind with the ValueId it produces.
proc newNode(id: ValueId, fncall: FunctionCallNode): Node =
  Node(kind: nkCall, id: id, fncall: fncall)

proc newNode(id: ValueId, match: MatchNode): Node =
  Node(kind: nkMatch, id: id, match: match)

proc newNode(id: ValueId, tryCall: TryNode): Node =
  Node(kind: nkTry, id: id, tryCall: tryCall)

proc newNode(id: ValueId, literal: LiteralNode): Node =
  Node(kind: nkLiteral, id: id, literal: literal)

proc newNode(id: ValueId, unionInit: UnionInitNode): Node =
  Node(kind: nkUnion, id: id, unionInit: unionInit)

proc newNode(id: ValueId, structInit: StructInitNode): Node =
  Node(kind: nkStruct, id: id, structInit: structInit)

proc newNode(id: ValueId, variantField: VariantFieldNode): Node =
  Node(kind: nkVariantField, id: id, variantField: variantField)

proc newNode(id: ValueId, structField: StructFieldNode): Node =
  Node(kind: nkStructField, id: id, structField: structField)

proc newNode(id: ValueId, structSetter: StructSetterNode): Node =
  Node(kind: nkStructSetter, id: id, structSetter: structSetter)

# MonoUserFunction — the params' ValueIds (in signature order), the body nodes,
# and the ValueId the tail produced (the value the copy returns).
proc newMonoUserFunction(params: seq[ValueId], nodes: seq[Node], resultId: ValueId): MonoUserFunction =
  MonoUserFunction(params: params, nodes: nodes, resultId: resultId)

# MonoExternFunction — the extern declaration plus the concrete impls of its copy.
proc newMonoExternFunction(extern: AnalyzedExternFunction, impls: AnalyzedImplMap): MonoExternFunction =
  MonoExternFunction(extern: extern, impls: impls)

# MonoInstance — wraps a built copy with the kind of function it is.
proc newMonoInstance(user: MonoUserFunction): MonoInstance =
  MonoInstance(kind: mikUser, user: user)

proc newMonoInstance(extern: MonoExternFunction): MonoInstance =
  MonoInstance(kind: mikExtern, extern: extern)

# FunctionScope — hands out the copy's ValueIds (`counter`), remembers the value
# each in-scope variable stands for (`argMap`), and collects the body's nodes.
proc newFunctionScope(): FunctionScope = FunctionScope()

proc nextId(scope: FunctionScope): ValueId =
  let id = ValueId(scope.counter)
  scope.counter += 1
  id

# A child scope for a case arm: it takes its own copy of argMap and a fresh,
# empty node list, so bindings and body nodes added inside the arm do not leak
# to the parent, sibling arms, or the code after the match.
proc branch(scope: FunctionScope): FunctionScope =
  FunctionScope(counter: scope.counter, argMap: scope.argMap, nodes: @[])

# Monomorphizer — tracks which copies are finished (`visited`) and in progress
# (`visiting`), hands out the next FunctionId (`counter`), and keeps each
# finished copy's built body (`instances`).
proc newMonomorphizer(): Monomorphizer = Monomorphizer()

proc nextId(mono: Monomorphizer): FunctionId =
  let id = FunctionId(mono.counter)
  mono.counter += 1
  id

# MonoInstance — which kind of copy this is (user body vs extern declaration).
proc kind*(instance: MonoInstance): MonoInstanceKind = instance.kind

# MonoApp — read access to the built program for downstream passes.
proc newMonoApp(instances: Table[FunctionId, MonoInstance], entry: FunctionId): MonoApp =
  MonoApp(instances: instances, entry: entry)

proc instances*(app: MonoApp): Table[FunctionId, MonoInstance] = app.instances
proc entry*(app: MonoApp): FunctionId = app.entry

proc monomorphize(mono: Monomorphizer, app: AnalyzedApp, funcRef: FunctionRef): Result[FunctionId, string]
proc monomorphize(scope: FunctionScope, mono: Monomorphizer, app: AnalyzedApp, statement: AnalyzedStatement, impls: AnalyzedImplMap): Result[ValueId, string]
proc monomorphize(scope: FunctionScope, mono: Monomorphizer, app: AnalyzedApp, expression: AnalyzedExpression, impls: AnalyzedImplMap): Result[ValueId, string]

proc monomorphize(scope: FunctionScope, mono: Monomorphizer, app: AnalyzedApp, fncall: AnalyzedFunctionCall, impls: AnalyzedImplMap): Result[ValueId, string] =
  var args: seq[ValueId]
  for arg in fncall.args:
    let argId = ? monomorphize(scope, mono, app, arg, impls)
    args.add(argId)

  var callee: FunctionId
  case fncall.localType.kind:
  of altkModule:
    let module = app.findModule(fncall.localType.module)
    let function = module.findFunction(fncall.funcDef)
    let concreteImpls = fncall.impls.calleeImpls(impls)
    let funcRef =
      case function.kind:
      of afkUser: newFunctionRef(module, function.user, concreteImpls)
      of afkExtern: newFunctionRef(module, function.extern, concreteImpls)
      of afkGenerated: newFunctionRef(module, function.generated, concreteImpls)
    callee = ? monomorphize(mono, app, funcRef)
  of altkGeneric:
    # Resolve the generic target to the concrete type bound for this call. The
    # binding can come from the enclosing copy's impls (a context generic, e.g.
    # Behavior in Runtime[Behavior]) or from the call's own inferred impls (a
    # generic inferred from an argument, e.g. Shape in Shape.sides(x)), so
    # resolve against both. The binding may itself be a generic (one generic
    # satisfying another), so follow the chain to a concrete module, translating
    # the called funcDef through each hop's index. Only `callee` is produced
    # here; the shared tail builds the node, so a `try` is handled there.
    var resolveImpls = impls
    for generic, impl in fncall.impls.calleeImpls(impls):
      resolveImpls[generic] = impl
    var impl = resolveImpls[fncall.localType.generic.resolved]
    var funcDef = impl.defs[fncall.funcDef.resolved]
    while impl.argType.kind == aatkGeneric:
      impl = resolveImpls[impl.argType.generic.generic]
      funcDef = impl.defs[funcDef]
    let module = app.findModule(impl.argType.module.module)
    let function = module.findFunction(funcDef)
    let concreteImpls = impl.argType.module.impls
    let funcRef =
      case function.kind:
      of afkUser: newFunctionRef(module, function.user, concreteImpls)
      of afkExtern: newFunctionRef(module, function.extern, concreteImpls)
      of afkGenerated: newFunctionRef(module, function.generated, concreteImpls)
    callee = ? monomorphize(mono, app, funcRef)

  let id = scope.nextId()
  let node =
    case fncall.kind:
    of afckDefault:
      newNode(id, newFunctionCallNode(callee, args))
    of afckTry:
      let tryCall = newTryNode(newFunctionCallNode(callee, args), fncall.returns.concrete(impls))
      newNode(id, tryCall)

  scope.nodes.add(node)
  ok(id)


proc monomorphize(scope: FunctionScope, mono: Monomorphizer, app: AnalyzedApp, expression: AnalyzedExpression, impls: AnalyzedImplMap): Result[ValueId, string] =
  case expression.kind:
  of aekFunctionCall:
    ok(? monomorphize(scope, mono, app, expression.fncall, impls))
  of aekMatchExpr:
    let subjectId = ? monomorphize(scope, mono, app, expression.match.subject, impls)
    var branches: seq[BranchNode]
    for caseBlock in expression.match.cases:
      let branchScope = scope.branch()
      for binding in caseBlock.pattern.bindings:
        case binding.kind:
        of abkVariable:
          # A whole-subject binding (a `case other:`) names the matched value.
          branchScope.argMap[binding.name] = subjectId
        of abkVariantField:
          # A variant-field binding projects one field out of the matched
          # subject; the projection is scoped to this arm.
          let variant = caseBlock.pattern.variant.variant
          let fieldId = branchScope.nextId()
          branchScope.nodes.add(newNode(fieldId, newVariantFieldNode(subjectId, variant.name, binding.variantField.field.name, binding.argType.concrete(impls))))
          branchScope.argMap[binding.name] = fieldId
      var branchResult: ValueId
      for statement in caseBlock.statements:
        branchResult = ? monomorphize(branchScope, mono, app, statement, impls)
      branches.add(BranchNode(pattern: caseBlock.pattern, nodes: branchScope.nodes, resultId: branchResult))
    let id = scope.nextId()
    scope.nodes.add(newNode(id, newMatchNode(subjectId, branches)))
    ok(id)
  of aekInitializer:
    case expression.init.kind:
    of aikLiteral:
      let lit = expression.init.literal
      let id = scope.nextId()
      scope.nodes.add(newNode(id, newLiteralNode(lit.literal, lit.argType.concrete(impls))))
      ok(id)
    of aikStruct:
      let structInit = expression.init.struct
      var fields: seq[InitField]
      for kwarg in structInit.kwargs:
        let value = ? monomorphize(scope, mono, app, kwarg.expression, impls)
        fields.add(InitField(field: kwarg.field.name, value: value))
      let id = scope.nextId()
      scope.nodes.add(newNode(id, newStructInitNode(expression.argType.concrete(impls), fields)))
      ok(id)
    of aikUnion:
      let union = expression.init.union
      var fields: seq[InitField]
      for kwarg in union.kwargs:
        let value = ? monomorphize(scope, mono, app, kwarg.expression, impls)
        fields.add(InitField(field: kwarg.field.name, value: value))
      let id = scope.nextId()
      scope.nodes.add(newNode(id, newUnionInitNode(expression.argType.concrete(impls), union.variant, fields)))
      ok(id)
  of aekStructGetter:
    let getter = expression.structGetter
    assert(getter.sourceName in scope.argMap, "[BUG] - struct getter source out of scope during monomorphization")
    let id = scope.nextId()
    scope.nodes.add(newNode(id, newStructFieldNode(scope.argMap[getter.sourceName], getter.property.name, expression.argType.concrete(impls))))
    ok(id)
  of aekVariable:
    # A variable is not a node — it resolves to the value its binding produced.
    let name = expression.variable.name
    assert(name in scope.argMap, "[BUG] - variable out of scope during monomorphization")
    ok(scope.argMap[name])

proc monomorphize(scope: FunctionScope, mono: Monomorphizer, app: AnalyzedApp, statement: AnalyzedStatement, impls: AnalyzedImplMap): Result[ValueId, string] =
  case statement.kind:
  of askNone:
    monomorphize(scope, mono, app, statement.expression, impls)
  of askVariable:
    let value = ? monomorphize(scope, mono, app, statement.expression, impls)
    let target = statement.target
    assert(target.isSome, "[BUG] - rskVariable statement has no target")
    scope.argMap[target.get] = value
    ok(value)
  of askGetter:
    # A field setter is a functional update: build a new struct equal to the
    # source with the field replaced, then rebind the source variable to it so
    # later statements see the updated struct.
    let getter = statement.getter
    let value = ? monomorphize(scope, mono, app, statement.expression, impls)
    assert(getter.sourceName in scope.argMap, "[BUG] - setter source out of scope during monomorphization")
    let id = scope.nextId()
    scope.nodes.add(newNode(id, newStructSetterNode(scope.argMap[getter.sourceName], getter.property.name, value, newAnalyzedArgumentType(getter.source).concrete(impls))))
    scope.argMap[getter.sourceName] = id
    ok(id)

proc monomorphize(mono: Monomorphizer, app: AnalyzedApp, funcRef: FunctionRef, function: AnalyzedUserFunction): Result[MonoUserFunction, string] =
  let scope = newFunctionScope()
  var params: seq[ValueId]
  for arg in function.def.args:
    let paramId = scope.nextId()
    scope.argMap[arg.name] = paramId
    params.add(paramId)

  # The function's value is the value its last statement produces — its tail.
  var resultId: ValueId
  for statement in function.statements:
    resultId = ? monomorphize(scope, mono, app, statement, funcRef.impls)

  ok(newMonoUserFunction(params, scope.nodes, resultId))

proc monomorphize(mono: Monomorphizer, app: AnalyzedApp, funcRef: FunctionRef): Result[FunctionId, string] =
  if funcRef in mono.visited:
    ok(mono.visited[funcRef])
  else:
    # Recursion is handled here: if we reach a function copy that is still
    # being built, this is a recursive call back into it, so return the id we
    # already gave it and let the cycle close instead of looping forever.
    if funcRef in mono.visiting:
      ok(mono.visiting[funcRef])
    # TODO(growth-check): this depth bound is a stopgap for type-growing
    # recursion (grow[i32] -> grow[Array[i32]] -> ... enlarges the type each
    # step, so `visiting` never closes). 128 is kept well under Nim's 2000
    # call-depth limit, since reaching the bound recurses that deep. Replace
    # with a proper occurs check: before minting, reject a copy whose type
    # argument strictly contains that of a same-function ancestor already in
    # `visiting` — it fires at the first growing step, not only at a fixed
    # depth, and has no call-depth interaction.
    elif mono.visiting.len >= 128:
      let loc =
        case funcRef.kind:
        of frkUser: funcRef.user.loc
        of frkExtern: funcRef.extern.loc
        of frkGenerated: funcRef.generated.loc
      err(fmt"{loc} monomorphization depth limit (128) exceeded, likely type-growing recursion")
    else:
      case funcRef.kind:
      of frkGenerated:
        # Generated functions come only from the (not-yet-implemented)
        # try->match expansion, so monomorphization can never reach one.
        assert(false, fmt"{funcRef.generated.loc} [BUG] - generated functions are not reachable during monomorphization")
        err("[BUG] - unreachable generated function")
      of frkExtern:
        # An extern function is an FFI declaration with no body, so there is
        # nothing to walk and no recursion knot to tie: mint its id and
        # memoize it directly.
        # TODO(extern-generic-wrapper): a generic extern needs a per-instance
        # kind-tagged C wrapper driven by `funcRef.impls` — a concrete scalar
        # passed into a generic slot lowers to `(value, kindTag, &out)`. If (and
        # only if) the extern reports failure, that flag is lifted back into a
        # Status.Ok/Err; an extern need not return a status.
        let id = mono.nextId()
        mono.instances[id] = newMonoInstance(newMonoExternFunction(funcRef.extern, funcRef.impls))
        mono.visited[funcRef] = id
        ok(id)
      of frkUser:
        let id = mono.nextId()
        mono.visiting[funcRef] = id

        let instance = ? monomorphize(mono, app, funcRef, funcRef.user)
        mono.instances[id] = newMonoInstance(instance)

        mono.visited[funcRef] = id
        mono.visiting.del(funcRef)

        ok(id)

proc monomorphize*(app: AnalyzedApp): Result[MonoApp, string] =
  let entry = ? app.entry
  assert(entry.function.kind == afkUser, "[BUG] - entry function must always be a user function")
  assert(entry.function.def.args.len == 0, "[BUG] - entry function should not accept any arguments")

  let mono = newMonomorphizer()
  let funcRef = newFunctionRef(entry.module, entry.function.user, default(AnalyzedImplMap))
  let entryId = ? monomorphize(mono, app, funcRef)
  ok(newMonoApp(mono.instances, entryId))