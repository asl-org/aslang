## Parser-level ANF expansion (kept as reference — not yet wired in).
##
## Lowers a parsed function body into A-normal form: every nested
## subexpression (a function argument, a kwarg value, a match subject)
## is lifted into its own preceding `__asl_arg_N = <expr>` assignment,
## and every top-level statement becomes an Assignment or a Setter so
## downstream layers reason about a single uniform shape.
##
## TODO(post-analysis-expander): re-wire expansion after the analyzer
## once the post-analysis expander lands (see
## plans/plan_post_analysis_expansion.md). The expand* procs below are
## kept as reference for that move.

import identifiers
import statement

proc expand(expression: Expression, start: int, replace: bool): (seq[Statement], Expression, int)
proc expand(expression: Expression, start: int): (seq[Statement], Expression, int)
proc expand(expression: InlineExpression, start: int, replace: bool): (seq[Statement], InlineExpression, int)
proc expand(expression: InlineExpression, start: int): (seq[Statement], InlineExpression, int)
proc expand(statement: Statement, start: int): (seq[Statement], int)

proc expand(fncall: FunctionCall, start: int): (seq[Statement], FunctionCall, int) =
  var expandedStmts: seq[Statement]
  var expandedArgs: seq[InlineExpression]
  var counter = start

  for arg in fncall.args:
    let (updatedStmts, updatedArg, updatedCounter) = arg.expand(counter)
    expandedStmts.add(updatedStmts)
    expandedArgs.add(updatedArg)
    counter = updatedCounter

  let generatedArgList = newArgumentList(expandedArgs, fncall.argList.loc)
  let generatedFunctionCall = newFunctionCall(fncall.root, fncall.name, generatedArgList)
  (expandedStmts, generatedFunctionCall, counter)

proc expand(structInit: StructInitializer, start: int): (seq[Statement], StructInitializer, int) =
  var expandedStmts: seq[Statement]
  var expandedkwargs: seq[KeywordArgument]
  var counter = start
  for kwarg in structInit.kwargs:
    let (updatedStmts, updatedValue, updatedCounter) = kwarg.expression.expand(counter)
    expandedStmts.add(updatedStmts)
    expandedkwargs.add(newKeywordArgument(kwarg.name, updatedValue, kwarg.loc))
    counter = updatedCounter

  let generatedkwargList = newGeneratedKeywordArgumentList(expandedkwargs, structInit.kwargList.loc)
  let generatedStructInit = newStructInitializer(structInit.structRef, generatedkwargList)
  (expandedStmts, generatedStructInit, counter)

proc expand(unionInit: UnionInitializer, start: int): (seq[Statement], UnionInitializer, int) =
  var expandedStmts: seq[Statement]
  var expandedkwargs: seq[KeywordArgument]
  var counter = start
  for kwarg in unionInit.kwargs:
    let (updatedStmts, updatedValue, updatedCounter) = kwarg.expression.expand(counter)
    expandedStmts.add(updatedStmts)
    expandedkwargs.add(newKeywordArgument(kwarg.name, updatedValue, kwarg.loc))
    counter = updatedCounter

  let generatedkwargList = newGeneratedKeywordArgumentList(expandedkwargs, unionInit.kwargList.loc)
  let generatedUnionInit = newUnionInitializer(unionInit.unionRef, generatedkwargList)
  (expandedStmts, generatedUnionInit, counter)

proc expand(initializer: Initializer, start: int): (seq[Statement], Initializer, int) =
  case initializer.kind:
  of ikStruct:
    let (expandedStmts, expandedStructInit, counter) = initializer.struct.expand(start)
    return (expandedStmts, newInitializer(expandedStructInit), counter)
  of ikLiteral:
    return (newSeq[Statement](), initializer, start)
  of ikUnion:
    let (expandedStmts, expandedUnionInit, counter) = initializer.union.expand(start)
    return (expandedStmts, newInitializer(expandedUnionInit), counter)

proc expand(caseBlock: CaseBlock, start: int): (CaseBlock, int) =
  var expanded: seq[Statement]
  var counter = start
  for statement in caseBlock.statements:
    let (expandedStmts, updatedCounter) = statement.expand(counter)
    expanded.add(expandedStmts)
    counter = updatedCounter

  let expandedCaseBlock = newCaseBlock(caseBlock.pattern, newStatementList(expanded), caseBlock.loc)
  (expandedCaseBlock, counter)

proc expand(match: MatchExpression, start: int): (seq[Statement], MatchExpression, int) =
  var expandedStmts: seq[Statement]
  var counter = start
  let (expandedSubjectStmts, expandedSubjectExpr, updatedCounter) = match.subject.expand(counter)
  expandedStmts.add(expandedSubjectStmts)
  counter = updatedCounter

  var expandedCases: seq[CaseBlock]
  for caseBlock in match.cases:
    let (expandedCase, updatedCounter) = caseBlock.expand(counter)
    expandedCases.add(expandedCase)
    counter = updatedCounter

  let expandedMatchExpr = newMatchExpression(expandedSubjectExpr, expandedCases, match.loc)
  (expandedStmts, expandedMatchExpr, counter)

proc replace(expression: InlineExpression, start: int): (Statement, InlineExpression, int) =
  let generatedTarget = newGeneratedIdentifier(start, expression.loc)
  let generatedAssignment = newAssignment(generatedTarget, newExpression(expression), expression.loc)
  (newStatement(generatedAssignment), newInlineExpression(generatedTarget), start + 1)

proc replace(expression: Expression, start: int): (Statement, Expression, int) =
  let generatedTarget = newGeneratedIdentifier(start, expression.loc)
  let generatedAssignment = newAssignment(generatedTarget, expression, expression.loc)
  (newStatement(generatedAssignment), newExpression(generatedTarget), start + 1)

proc expand(expression: InlineExpression, start: int, replace: bool): (seq[Statement], InlineExpression, int) =
  case expression.kind:
  of iekLiteral, iekVariable:
    # Literals and variables are already terminal — no sub-expressions
    # to lift and no useful transformation from binding them to a temp:
    # a literal at a value position needs to reach `analyzeBareLiteral`
    # with its expected context intact (Approach C's concrete-adopt);
    # a variable is already a named binding, so wrapping in another
    # temp would just add noise. Left as-is regardless of `replace`.
    (@[], expression, start)
  of iekGetter:
    # A Getter has no sub-expressions to lift (source and property are
    # both Identifiers), but at a value position we still want to bind
    # its read result to a temp so the ANF invariant holds: every
    # value-position expression downstream is a Variable or a Literal.
    # The `replace = false` path (assignment / setter RHS) leaves it
    # alone because the enclosing construct is already the binding.
    if replace:
      var (replacedStmt, replacedExpr, replacedCounter) = expression.replace(start)
      (@[replacedStmt], replacedExpr, replacedCounter)
    else:
      (@[], expression, start)
  of iekFnCall:
    var (expandedStmts, expandedFncall, counter) = expression.fncall.expand(start)
    if replace:
      var (replacedStmt, replacedExpr, replacedCounter) = expandedFncall.newInlineExpression().replace(counter)
      expandedStmts.add(replacedStmt)
      (expandedStmts, replacedExpr, replacedCounter)
    else:
      (expandedStmts, expandedFncall.newInlineExpression(), counter)
  of iekInitializer:
    var (expandedStmts, expandedInitializer, counter) = expression.initializer.expand(start)
    if replace:
      var (replacedStmt, replacedExpr, replacedCounter) = expandedInitializer.newInlineExpression().replace(counter)
      expandedStmts.add(replacedStmt)
      (expandedStmts, replacedExpr, replacedCounter)
    else:
      (expandedStmts, expandedInitializer.newInlineExpression(), counter)

proc expand(expression: InlineExpression, start: int): (seq[Statement], InlineExpression, int) =
  expand(expression, start, true)

proc expand(expression: Expression, start: int, replace: bool): (seq[Statement], Expression, int) =
  case expression.kind:
  of ekInline:
    var (expandedStmts, expandedInlineExpr, counter) = expression.inline.expand(start, replace)
    (expandedStmts, newExpression(expandedInlineExpr), counter)
  of ekMatch:
    var (expandedStmts, expandedMatchExpr, counter) = expression.match.expand(start)
    if replace:
      var (replacedStmt, replacedExpr, replacedCounter) = expandedMatchExpr.newExpression().replace(counter)
      expandedStmts.add(replacedStmt)
      (expandedStmts, replacedExpr, replacedCounter)
    else:
      (expandedStmts, newExpression(expandedMatchExpr), counter)

proc expand(expression: Expression, start: int): (seq[Statement], Expression, int) =
  expand(expression, start, true)

proc expand(assignment: Assignment, start: int): (seq[Statement], Assignment, int) =
  let (expandedStmts, expandedExpr, counter) = assignment.expression.expand(start, replace = false)
  (expandedStmts, newAssignment(assignment.target, expandedExpr, assignment.loc), counter)

proc expand(setter: Setter, start: int): (seq[Statement], Setter, int) =
  let (expandedStmts, expandedExpr, counter) = setter.expression.expand(start, replace = false)
  (expandedStmts, newSetter(setter.target, expandedExpr, setter.loc), counter)

proc expand(statement: Statement, start: int): (seq[Statement], int) =
  case statement.kind:
  of skAssignment:
    var (expandedStmts, expandedAssignment, updatedCounter) = statement.assignment.expand(start)
    expandedStmts.add(newStatement(expandedAssignment))
    (expandedStmts, updatedCounter)
  of skSetter:
    var (expandedStmts, expandedSetter, updatedCounter) = statement.setter.expand(start)
    expandedStmts.add(newStatement(expandedSetter))
    (expandedStmts, updatedCounter)
  of skExpr:
    # Every bare-expression statement is explicitly wrapped in a
    # synthesized `__asl_arg_N = <expr>` assignment. Two steps:
    #   1. `expression.expand(start, replace = false)` lifts nested
    #      *subexpressions* (function args, kwarg values, match
    #      subjects) into their own preceding temp assignments. The
    #      outer expression is NOT wrapped at this step — that's what
    #      `replace = false` signals, matching how `expand(assignment)`
    #      and `expand(setter)` treat their RHS.
    #   2. `.replace(counter)` on the resulting outer expression binds
    #      it to a fresh temp, producing the final assignment.
    #
    # Note the asymmetry between expressions and statements: bare
    # literal / variable EXPRESSIONS (as subexpressions) are never
    # expanded — the `ekLiteral, ekVariable` arm of `expression.expand`
    # returns them unchanged regardless of `replace`, because they're
    # already terminal (a literal reaches `analyzeBareLiteral` with its
    # expected context intact under Approach C; a variable is already
    # a named binding). Getters ARE lifted at value positions
    # (`replace = true`) but pass through unchanged at RHS positions
    # (`replace = false`). But when any of these shapes — literal,
    # variable, or getter — appear as the *outer* expression of a
    # bare-expression STATEMENT, we still wrap them here at the
    # statement level via the explicit `.replace(counter)` below.
    # That keeps the invariant that every top-level statement in a
    # function body is an Assignment or a Setter, never a raw
    # bare-expression — downstream layers reason about a uniform
    # ANF shape.
    #
    # Two failure modes without the wrap:
    # - A bare `value` in a case body would vanish (empty case block
    #   trips body.nim:326's non-empty-statements assertion) because
    #   the top-level `expand(Expression)` returns the variable
    #   unchanged and the skExpr arm has nothing to add.
    # - The uniform ANF invariant would leak: a mix of assignments and
    #   bare expressions in the same body forces downstream code to
    #   handle two shapes per position.
    var (expandedStmts, expandedExpr, counter) = statement.expression.expand(start, replace = false)
    let (replacedStmt, _, replacedCounter) = expandedExpr.replace(counter)
    expandedStmts.add(replacedStmt)
    (expandedStmts, replacedCounter)

proc expand*(sl: StatementList): StatementList =
  var expanded: seq[Statement]
  var counter: int = 0
  for statement in sl.statements:
    let (expandedStmts, updatedCounter) = statement.expand(counter)
    expanded.add(expandedStmts)
    counter = updatedCounter
  newStatementList(expanded)
