## utils.nim - Cross-cutting utilities for the ASLang compiler
##
## Provides:
##   variant - Pattern matching macro for Nim case objects
##   unwrap  - Early return operator for Result[T,E] and Option[T]
##   struct  - Sugar for ref object of RootObj definitions
##   union   - Sugar for discriminated union (enum + case object) definitions

import std/macros
import std/options
import results

# =============================================================================
# unwrap - Early return for Result and Option
# =============================================================================

template unwrap*[T, E](self: Result[T, E]): auto =
  ## Early return on Result error. Mirrors the `?` operator from results.
  let temp = self
  if temp.isErr:
    return err(temp.error)
  temp.get

template unwrap*(self: Result[void, string]): void =
  ## Early return on void Result error.
  let temp = self
  if temp.isErr:
    return err(temp.error)

template unwrap*[T](self: Option[T]): T =
  ## Early return on Option None. Enclosing proc must return Result[_, string].
  let temp = self
  if temp.isNone:
    return err("unexpected None")
  temp.get

# =============================================================================
# variant - Pattern matching macro for case objects
# =============================================================================

proc findRecCase(n: NimNode): NimNode =
  ## Recursively walk a type implementation to find the nnkRecCase node.
  if n.kind == nnkRecCase:
    return n
  for i in 0 ..< n.len:
    let found = findRecCase(n[i])
    if found != nil:
      return found
  return nil

proc stripPostfix(n: NimNode): string =
  ## Extract identifier name, stripping export marker (*) if present.
  if n.kind == nnkPostfix:
    $n[1]
  else:
    $n

proc getIdentDefsNames(node: NimNode): seq[string] =
  ## Extract all identifier names from an IdentDefs node.
  ## IdentDefs has N identifiers followed by type and default value.
  for i in 0 ..< node.len - 2:
    result.add(stripPostfix(node[i]))

proc getFieldsForBranch(branch: NimNode): seq[string] =
  ## Extract field names from an OfBranch body.
  ## Single-field branches have IdentDefs directly; multi-field have RecList.
  let body = branch[^1]
  if body.kind == nnkRecList:
    for child in body:
      if child.kind == nnkIdentDefs:
        result.add(getIdentDefsNames(child))
  elif body.kind == nnkIdentDefs:
    result.add(getIdentDefsNames(body))

proc getEnumValsForBranch(branch: NimNode,
    ordinalMap: seq[string]): seq[string] =
  ## Extract enum value names from an OfBranch (all children except the last).
  ## Handles both nnkIdent/nnkSym (from getImpl) and nnkIntLit (from getTypeImpl).
  for i in 0 ..< branch.len - 1:
    let node = branch[i]
    if node.kind == nnkIntLit:
      result.add(ordinalMap[node.intVal.int])
    else:
      result.add($node)

proc buildOrdinalMap(enumTypeSym: NimNode): seq[string] =
  ## Build a mapping from ordinal values to enum value names.
  let enumImpl = enumTypeSym.getTypeImpl()
  # EnumTy: Empty, Sym "VAL_A", Sym "VAL_B", ...
  for i in 1 ..< enumImpl.len:
    result.add($enumImpl[i])

macro variant*(subject: typed, branches: varargs[untyped]): untyped =
  ## Pattern match on a Nim case object with automatic field extraction.
  ## Renamed from `match` to avoid shadowing variables named `match`.
  ##
  ## Usage:
  ##   variant expression:
  ##     of REK_MATCH(m):        # let m = expression.match
  ##       m.returns
  ##     of REK_FNCALL(f):       # let f = expression.fncall
  ##       f.returns
  ##     of REK_VARIABLE:        # no binding
  ##       discard
  ##
  ## Generates an underlying `case obj.kind:` statement.
  ## Exhaustive checking is enforced by the Nim compiler.

  # --- Step 1: Introspect the type ---
  let typeNode = subject.getType()

  var typeSym: NimNode
  if typeNode.kind == nnkBracketExpr and $typeNode[0] == "ref":
    typeSym = typeNode[1]
  else:
    typeSym = typeNode

  let typeImpl = typeSym.getTypeImpl()

  # --- Step 2: Find the RecCase node ---
  let recCase = findRecCase(typeImpl)
  if recCase.isNil:
    error("variant: type does not have a case discriminant", subject)

  # --- Step 3: Get discriminant field name (e.g., "kind") ---
  let discName = if recCase[0].kind == nnkIdentDefs:
    stripPostfix(recCase[0][0])
  else:
    stripPostfix(recCase[0])

  # --- Step 3b: Build ordinal-to-name map for the discriminant enum ---
  let discTypeSym = if recCase[0].kind == nnkIdentDefs:
    recCase[0][1]
  else:
    recCase[0]
  let ordinalMap = buildOrdinalMap(discTypeSym)

  # --- Step 4: Build field map: enum_value_name → [field_names] ---
  var fieldMap: seq[(string, seq[string])]
  for i in 1 ..< recCase.len:
    let branch = recCase[i]
    if branch.kind == nnkOfBranch:
      let fields = getFieldsForBranch(branch)
      let enumVals = getEnumValsForBranch(branch, ordinalMap)
      for ev in enumVals:
        fieldMap.add((ev, fields))

  # --- Step 5: Create temp variable ---
  let tmp = genSym(nskLet, "variantSubj")

  # --- Step 6: Build case statement ---
  var caseStmt = nnkCaseStmt.newTree(
    newDotExpr(tmp, ident(discName))
  )

  # --- Step 7: Process each branch ---
  for branch in branches:
    if branch.kind == nnkOfBranch:
      var newBranch = nnkOfBranch.newTree()
      var stmts = nnkStmtList.newTree()

      # Detect {} destructuring vs () positional vs bare enum
      let firstMatchNode = branch[0]

      if firstMatchNode.kind == nnkCurlyExpr:
        # {} destructuring: of Type{kind: ENUM_VAL, field: binding, shorthand}:
        # curly[0] = type name (documentation only, ignored)
        # Remaining children: nnkExprColonExpr or nnkIdent
        var enumVal: NimNode
        var fieldBindings: seq[(string, string)]  # (field_name, binding_name)

        for i in 1 ..< firstMatchNode.len:
          let child = firstMatchNode[i]
          if child.kind == nnkExprColonExpr:
            let fieldName = $child[0]
            if fieldName == discName:
              # Dispatch value: kind: ENUM_VAL
              enumVal = child[1]
            else:
              # Field binding: field: binding_name
              fieldBindings.add((fieldName, $child[1]))
          elif child.kind == nnkIdent:
            # Shorthand: field (binding name = field name)
            let name = $child
            fieldBindings.add((name, name))
          else:
            error("variant: unexpected node in {} destructuring")

        if enumVal.isNil:
          error("variant: {} destructuring requires `" & discName &
                ": ENUM_VALUE`", firstMatchNode)

        newBranch.add(enumVal)

        for (fieldName, bindingName) in fieldBindings:
          stmts.add(
            nnkLetSection.newTree(
              nnkIdentDefs.newTree(
                ident(bindingName),
                newEmptyNode(),
                newDotExpr(tmp, ident(fieldName))
              )
            )
          )
      else:
        # () positional bindings or bare enum values
        var firstEnumName = ""
        var bindings: seq[string]

        for i in 0 ..< branch.len - 1:
          let node = branch[i]
          if node.kind == nnkCall:
            if firstEnumName == "":
              firstEnumName = $node[0]
            newBranch.add(node[0])
            for j in 1 ..< node.len:
              bindings.add($node[j])
          else:
            if firstEnumName == "":
              firstEnumName = $node
            newBranch.add(node)

        if bindings.len > 0:
          var fields: seq[string]
          for (name, f) in fieldMap:
            if name == firstEnumName:
              fields = f
              break

          if bindings.len > fields.len:
            error("variant: too many bindings for " & firstEnumName &
                  " (expected " & $fields.len & ", got " & $bindings.len & ")")

          for i in 0 ..< bindings.len:
            stmts.add(
              nnkLetSection.newTree(
                nnkIdentDefs.newTree(
                  ident(bindings[i]),
                  newEmptyNode(),
                  newDotExpr(tmp, ident(fields[i]))
                )
              )
            )

      let branchBody = branch[^1]
      if branchBody.kind == nnkStmtList:
        for stmt in branchBody:
          stmts.add(stmt)
      else:
        stmts.add(branchBody)

      newBranch.add(stmts)
      caseStmt.add(newBranch)

    elif branch.kind == nnkElse:
      caseStmt.add(branch)

  # --- Step 8: Assemble result ---
  result = nnkBlockStmt.newTree(
    newEmptyNode(),
    nnkStmtList.newTree(
      nnkLetSection.newTree(
        nnkIdentDefs.newTree(
          tmp,
          newEmptyNode(),
          subject
        )
      ),
      caseStmt
    )
  )

# =============================================================================
# struct - Sugar for ref object of RootObj definitions
# =============================================================================

macro struct*(name: untyped, body: untyped): untyped =
  ## Sugar for defining a ref object of RootObj with exported fields.
  ##
  ## Usage:
  ##   struct MyStruct:
  ##     field1: Type1
  ##     field2: Type2
  ##
  ## Expands to:
  ##   type MyStruct* = ref object of RootObj
  ##     field1*: Type1
  ##     field2*: Type2

  var recList = nnkRecList.newTree()

  for child in body:
    if child.kind == nnkCall and child.len == 2:
      # field: Type → nnkCall(nnkIdent("field"), nnkStmtList(nnkIdent("Type")))
      let fieldName = nnkPostfix.newTree(ident("*"), child[0])
      let fieldType = child[1][0]
      recList.add(
        nnkIdentDefs.newTree(fieldName, fieldType, newEmptyNode())
      )
    else:
      error("struct: expected `field: Type`", child)

  result = nnkTypeSection.newTree(
    nnkTypeDef.newTree(
      nnkPostfix.newTree(ident("*"), name),
      newEmptyNode(),
      nnkRefTy.newTree(
        nnkObjectTy.newTree(
          newEmptyNode(),
          nnkOfInherit.newTree(ident("RootObj")),
          recList
        )
      )
    )
  )

# =============================================================================
# union - Sugar for discriminated union (enum + case object) definitions
# =============================================================================

macro union*(name: untyped, body: untyped): untyped =
  ## Sugar for defining a discriminated union with auto-generated enum.
  ##
  ## Usage:
  ##   union CType:
  ##     CTK_VOID
  ##     CTK_NAMED:
  ##       name: string
  ##     CTK_POINTER
  ##
  ## With shared fields:
  ##   union AnalyzedMatch:
  ##     location: Location
  ##     RMK_CASE_ONLY
  ##     RMK_COMPLETE:
  ##       else_block: AnalyzedElse
  ##
  ## Expands to:
  ##   type
  ##     CTypeKind* = enum CTK_VOID, CTK_NAMED, CTK_POINTER
  ##     CType* = ref object of RootObj
  ##       case kind*: CTypeKind
  ##       of CTK_VOID: discard
  ##       of CTK_NAMED: name*: string
  ##       of CTK_POINTER: discard

  var sharedFieldDefs: seq[NimNode]
  var enumValues: seq[NimNode]
  var ofBranches: seq[NimNode]
  var inVariants = false

  for child in body:
    if child.kind == nnkIdent:
      # Bare identifier: empty variant (of VARIANT: discard)
      inVariants = true
      enumValues.add(child)
      ofBranches.add(nnkOfBranch.newTree(child, newNilLit()))

    elif child.kind == nnkCommand and child.len == 2 and
        child[1].kind == nnkTableConstr:
      # Inline shorthand: VARIANT { field: Type, field: Type }
      # Parsed as nnkCommand(nnkIdent, nnkTableConstr(nnkExprColonExpr...))
      inVariants = true
      enumValues.add(child[0])
      var branchBody = nnkRecList.newTree()
      for entry in child[1]:
        if entry.kind == nnkExprColonExpr:
          let fn = nnkPostfix.newTree(ident("*"), entry[0])
          let ft = entry[1]
          branchBody.add(nnkIdentDefs.newTree(fn, ft, newEmptyNode()))
        else:
          error("union: expected `field: Type` in {} shorthand", entry)
      if branchBody.len == 0:
        ofBranches.add(nnkOfBranch.newTree(child[0], newNilLit()))
      else:
        ofBranches.add(nnkOfBranch.newTree(child[0], branchBody))

    elif child.kind == nnkCall and child.len == 2:
      let childName = $child[0]
      let isUpper = childName.len > 0 and childName[0] in {'A'..'Z'}

      if not inVariants and not isUpper:
        # Shared field: name: Type
        let fieldName = nnkPostfix.newTree(ident("*"), child[0])
        let fieldType = child[1][0]
        sharedFieldDefs.add(
          nnkIdentDefs.newTree(fieldName, fieldType, newEmptyNode()))
      else:
        # Variant with fields (indented block)
        inVariants = true
        enumValues.add(child[0])
        var branchBody = nnkRecList.newTree()
        for fieldNode in child[1]:
          if fieldNode.kind == nnkCall and fieldNode.len == 2:
            let fn = nnkPostfix.newTree(ident("*"), fieldNode[0])
            let ft = fieldNode[1][0]
            branchBody.add(nnkIdentDefs.newTree(fn, ft, newEmptyNode()))
        if branchBody.len == 0:
          ofBranches.add(nnkOfBranch.newTree(child[0], newNilLit()))
        else:
          ofBranches.add(nnkOfBranch.newTree(child[0], branchBody))

    else:
      error("union: unexpected node", child)

  # Build enum type: <Name>Kind
  let kindName = ident($name & "Kind")

  var enumTy = nnkEnumTy.newTree(newEmptyNode())
  for ev in enumValues:
    enumTy.add(ev)

  # Build RecCase: case kind*: <Name>Kind
  var recCase = nnkRecCase.newTree(
    nnkIdentDefs.newTree(
      nnkPostfix.newTree(ident("*"), ident("kind")),
      kindName,
      newEmptyNode()
    )
  )
  for branch in ofBranches:
    recCase.add(branch)

  # Build RecList with shared fields + case discriminant
  var objRecList = nnkRecList.newTree()
  for sf in sharedFieldDefs:
    objRecList.add(sf)
  objRecList.add(recCase)

  result = nnkTypeSection.newTree(
    nnkTypeDef.newTree(
      nnkPostfix.newTree(ident("*"), kindName),
      newEmptyNode(),
      enumTy
    ),
    nnkTypeDef.newTree(
      nnkPostfix.newTree(ident("*"), name),
      newEmptyNode(),
      nnkRefTy.newTree(
        nnkObjectTy.newTree(
          newEmptyNode(),
          nnkOfInherit.newTree(ident("RootObj")),
          objRecList
        )
      )
    )
  )
