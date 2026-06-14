# Enum-variant dispatch audit

## Principle

Code duplication tends to be branch-specific: a single tagged union
gets `case x.kind: of A: ... of B: ...` dispatched on at N call sites,
and any change to one arm needs to be mirrored at all N. This doc
counts how many times each enum variant appears across `src/` so we
can spot high-fanout enums and refactor incrementally.

Higher usage count = more dispatch sites = more code that depends on
that arm's shape. A refactor that consolidates dispatch (helper
extraction, accessor delegation, kind-asserted unwrapping) reduces
the dispatch surface.

## Method

For each enum in `src/`:
1. Extract every variant identifier.
2. Count `grep -rE '\bVARIANT\b' src/ --include=*.nim` matches.
3. Subtract 1 (the variant's own declaration line).

The remaining count includes:
- `case x.kind: of VARIANT: ...` arms (1 per arm).
- `Foo(kind: VARIANT, ...)` constructors.
- `if x.kind == VARIANT: ...` comparisons.
- Any other source mention.

A `case` dispatch on an N-variant enum contributes N usages — so an
enum's total is approximately N × (number of dispatch sites). The
per-variant usage tells you which arm is the heaviest (or lightest,
e.g. todo/unwired arms).

## Snapshot (as of 2026-06-14)

### Top 10 by total dispatch surface

| Enum | File | Total | Per-variant |
|------|------|------:|-------------|
| `DataBlockKind` | parser/data.nim | **34** | `dbkLiteral` 11 · `dbkStruct` 12 · `dbkUnion` 11 |
| `DefinedTypeKind` | parser/decls.nim | **28** | `dtkModule` 14 · `dtkGeneric` 14 |
| `AnalyzedDefinedArgumentTypeKind` | analyzer/argtypes.nim | **24** | `adatkModule` 12 · `adatkGeneric` 12 |
| `ResolvedDefinedArgumentTypeKind` | resolver/argtypes.nim | **24** | `rdatkModule` 12 · `rdatkGeneric` 12 |
| `ResolvedArgumentTypeKind` | resolver/argtypes.nim | **24** | `ratkImported` 11 · `ratkDefined` 13 |
| `ResolvedCasePatternKind` | resolver/patterns.nim | **24** | `rcpkInteger` 8 · `rcpkVariable` 8 · `rcpkVariant` 8 |
| `StatementKind` | parser/body.nim | **24** | `skAssignment` 8 · `skExpr` 8 · `skMutation` 8 |
| `AnalyzedArgumentTypeKind` | analyzer/argtypes.nim | **22** | `aatkImported` 10 · `aatkDefined` 12 |
| `ResolvedDefinedTypeKind` | resolver/decls.nim | **22** | `rdtkModule` 11 · `rdtkGeneric` 11 |
| `CasePatternKind` | parser/patterns.nim | **21** | `cpkIntegerLiteral` 7 · `cpkVariable` 7 · `cpkVariant` 7 |

### Full table

| Enum | File | Variant | Usages |
|------|------|---------|------:|
| `AslCommandKind` | cli.nim | `ackBuild` | 5 |
| `AslCommandKind` | cli.nim | `ackHelp` | 5 |
| `TokenKind` | tokenizer/tokenizer.nim | `tkPunctuation` | 2 |
| `TokenKind` | tokenizer/tokenizer.nim | `tkSpace` | 3 |
| `TokenKind` | tokenizer/tokenizer.nim | `tkNewline` | 5 |
| `TokenKind` | tokenizer/tokenizer.nim | `tkAlphabet` | 2 |
| `TokenKind` | tokenizer/tokenizer.nim | `tkDigit` | 2 |
| `TokenKind` | tokenizer/tokenizer.nim | `tkUtf8` | 1 |
| `StructRefKind` | parser/body.nim | `srkDefault` | 7 |
| `StructRefKind` | parser/body.nim | `srkImpl` | 7 |
| `InitializerKind` | parser/body.nim | `ikLiteral` | 6 |
| `InitializerKind` | parser/body.nim | `ikStruct` | 6 |
| `InitializerKind` | parser/body.nim | `ikUnion` | 6 |
| `ExpressionKind` | parser/body.nim | `ekLiteral` | 6 |
| `ExpressionKind` | parser/body.nim | `ekFnCall` | 6 |
| `ExpressionKind` | parser/body.nim | `ekGetter` | 6 |
| `ExpressionKind` | parser/body.nim | `ekInitializer` | 6 |
| `ExpressionKind` | parser/body.nim | `ekVariable` | 6 |
| `ExpressionKind` | parser/body.nim | `ekMatch` | 9 |
| `StatementKind` | parser/body.nim | `skAssignment` | 8 |
| `StatementKind` | parser/body.nim | `skExpr` | 8 |
| `StatementKind` | parser/body.nim | `skMutation` | 8 |
| `LiteralKind` | parser/literals.nim | `lkString` | 7 |
| `LiteralKind` | parser/literals.nim | `lkInteger` | 7 |
| `LiteralKind` | parser/literals.nim | `lkFloat` | 7 |
| `FunctionKind` | parser/funcs.nim | `fkUser` | 9 |
| `FunctionKind` | parser/funcs.nim | `fkExtern` | 9 |
| `IntegerLiteralKind` | parser/numbers.nim | `ilkSigned` | 6 |
| `IntegerLiteralKind` | parser/numbers.nim | `ilkUnsigned` | 6 |
| `DefinedTypeKind` | parser/decls.nim | `dtkModule` | 14 |
| `DefinedTypeKind` | parser/decls.nim | `dtkGeneric` | 14 |
| `TypeKind` | parser/decls.nim | `tkImported` | 7 |
| `TypeKind` | parser/decls.nim | `tkDefined` | 7 |
| `DataBlockKind` | parser/data.nim | `dbkLiteral` | 11 |
| `DataBlockKind` | parser/data.nim | `dbkStruct` | 12 |
| `DataBlockKind` | parser/data.nim | `dbkUnion` | 11 |
| `CasePatternKind` | parser/patterns.nim | `cpkIntegerLiteral` | 7 |
| `CasePatternKind` | parser/patterns.nim | `cpkVariable` | 7 |
| `CasePatternKind` | parser/patterns.nim | `cpkVariant` | 7 |
| `AnalyzedStructRefKind` | analyzer/body.nim | `asrkDefault` | 3 |
| `AnalyzedStructRefKind` | analyzer/body.nim | `asrkImpl` | 4 |
| `AnalyzedInitializerKind` | analyzer/body.nim | `aikUnion` | 5 |
| `AnalyzedInitializerKind` | analyzer/body.nim | `aikStruct` | 5 |
| `AnalyzedExpressionKind` | analyzer/body.nim | `aekVariable` | 5 |
| `AnalyzedExpressionKind` | analyzer/body.nim | `aekFunctionCall` | 5 |
| `AnalyzedExpressionKind` | analyzer/body.nim | `aekLiteral` | 5 |
| `AnalyzedExpressionKind` | analyzer/body.nim | `aekMatchExpr` | 5 |
| `AnalyzedExpressionKind` | analyzer/body.nim | `aekInitializer` | 5 |
| `AnalyzedExpressionKind` | analyzer/body.nim | `aekGetter` | 5 |
| `AnalyzedStatementKind` | analyzer/body.nim | `askExpr` | 6 |
| `AnalyzedStatementKind` | analyzer/body.nim | `askAssignment` | 6 |
| `AnalyzedStatementKind` | analyzer/body.nim | `askMutation` | 6 |
| `AnalyzedFunctionKind` | analyzer/funcs.nim | `afkUser` | 3 |
| `AnalyzedFunctionKind` | analyzer/funcs.nim | `afkExtern` | 3 |
| `AnalyzedDefinedArgumentTypeKind` | analyzer/argtypes.nim | `adatkModule` | 12 |
| `AnalyzedDefinedArgumentTypeKind` | analyzer/argtypes.nim | `adatkGeneric` | 12 |
| `AnalyzedArgumentTypeKind` | analyzer/argtypes.nim | `aatkImported` | 10 |
| `AnalyzedArgumentTypeKind` | analyzer/argtypes.nim | `aatkDefined` | 12 |
| `AnalyzedDataKind` | analyzer/data.nim | `adkLiteral` | 9 |
| `AnalyzedDataKind` | analyzer/data.nim | `adkStruct` | 9 |
| `AnalyzedDataKind` | analyzer/data.nim | `adkUnion` | 9 |
| `AnalyzedLiteralPatternScopeKind` | analyzer/patterns.nim | `alpskU8` | 3 |
| `AnalyzedLiteralPatternScopeKind` | analyzer/patterns.nim | `alpskU16` | 3 |
| `AnalyzedLiteralPatternScopeKind` | analyzer/patterns.nim | `alpskU32` | 3 |
| `AnalyzedLiteralPatternScopeKind` | analyzer/patterns.nim | `alpskU64` | 3 |
| `AnalyzedLiteralPatternScopeKind` | analyzer/patterns.nim | `alpskI8` | 3 |
| `AnalyzedLiteralPatternScopeKind` | analyzer/patterns.nim | `alpskI16` | 3 |
| `AnalyzedLiteralPatternScopeKind` | analyzer/patterns.nim | `alpskI32` | 3 |
| `AnalyzedLiteralPatternScopeKind` | analyzer/patterns.nim | `alpskI64` | 3 |
| `AnalyzedCasePatternKind` | analyzer/patterns.nim | `acpkVariant` | 3 |
| `AnalyzedCasePatternKind` | analyzer/patterns.nim | `acpkInteger` | 3 |
| `AnalyzedCasePatternKind` | analyzer/patterns.nim | `acpkVariable` | 3 |
| `AnalyzedDefinedTypeKind` | analyzer/modules.nim | `adtkModule` | 7 |
| `AnalyzedDefinedTypeKind` | analyzer/modules.nim | `adtkGeneric` | 7 |
| `ResolvedStructRefKind` | resolver/body.nim | `rsrkDefault` | 4 |
| `ResolvedStructRefKind` | resolver/body.nim | `rsrkImpl` | 5 |
| `ResolvedInitializerKind` | resolver/body.nim | `rikStruct` | 5 |
| `ResolvedInitializerKind` | resolver/body.nim | `rikUnion` | 5 |
| `ResolvedInitializerKind` | resolver/body.nim | `rikLiteral` | 4 |
| `ResolvedExpressionKind` | resolver/body.nim | `rekFunctionCall` | 5 |
| `ResolvedExpressionKind` | resolver/body.nim | `rekVariable` | 5 |
| `ResolvedExpressionKind` | resolver/body.nim | `rekLiteral` | 5 |
| `ResolvedExpressionKind` | resolver/body.nim | `rekInitializer` | 5 |
| `ResolvedExpressionKind` | resolver/body.nim | `rekGetter` | 5 |
| `ResolvedExpressionKind` | resolver/body.nim | `rekMatchExpr` | 5 |
| `ResolvedStatementKind` | resolver/body.nim | `rskAssignment` | 6 |
| `ResolvedStatementKind` | resolver/body.nim | `rskExpr` | 6 |
| `ResolvedStatementKind` | resolver/body.nim | `rskMutation` | 6 |
| `ResolvedLiteralType` | resolver/literals.nim | `rltkU8` | 3 |
| `ResolvedLiteralType` | resolver/literals.nim | `rltkU16` | 3 |
| `ResolvedLiteralType` | resolver/literals.nim | `rltkU32` | 3 |
| `ResolvedLiteralType` | resolver/literals.nim | `rltkU64` | 3 |
| `ResolvedLiteralType` | resolver/literals.nim | `rltkI8` | 3 |
| `ResolvedLiteralType` | resolver/literals.nim | `rltkI16` | 3 |
| `ResolvedLiteralType` | resolver/literals.nim | `rltkI32` | 3 |
| `ResolvedLiteralType` | resolver/literals.nim | `rltkI64` | 3 |
| `ResolvedLiteralType` | resolver/literals.nim | `rltkF32` | 3 |
| `ResolvedLiteralType` | resolver/literals.nim | `rltkF64` | 3 |
| `ResolvedLiteralType` | resolver/literals.nim | `rltkString` | 3 |
| `ResolvedLiteralType` | resolver/literals.nim | `rltkPointer` | 3 |
| `ResolvedFunctionKind` | resolver/funcs.nim | `rfkExtern` | 6 |
| `ResolvedFunctionKind` | resolver/funcs.nim | `rfkUser` | 6 |
| `ResolvedDefinedTypeKind` | resolver/decls.nim | `rdtkModule` | 11 |
| `ResolvedDefinedTypeKind` | resolver/decls.nim | `rdtkGeneric` | 11 |
| `ResolvedDataKind` | resolver/data.nim | `rdkLiteral` | 5 |
| `ResolvedDataKind` | resolver/data.nim | `rdkStruct` | 5 |
| `ResolvedDataKind` | resolver/data.nim | `rdkUnion` | 5 |
| `ResolvedCasePatternKind` | resolver/patterns.nim | `rcpkInteger` | 8 |
| `ResolvedCasePatternKind` | resolver/patterns.nim | `rcpkVariable` | 8 |
| `ResolvedCasePatternKind` | resolver/patterns.nim | `rcpkVariant` | 8 |

## Reading the numbers

- **Asymmetric variant counts within one enum** (e.g. `aatkDefined` 12 vs
  `aatkImported` 10) flag where one arm has TODOs or `assert(false)`
  stubs that don't appear in every dispatch — see audit_derivation.md
  for the imported-arm holes still to wire.
- **Cross-layer duplication**: `DefinedTypeKind` (parser, 32) →
  `ResolvedDefinedTypeKind` (22) → `AnalyzedDefinedTypeKind` (14) is the
  same module/generic decision made three times. Each layer's
  dispatch is a candidate for accessor delegation through the
  `parsed:` / `resolved:` chain.
- **Top-N concentration**: the parser/data.nim `DataBlockKind` (34)
  and `DefinedTypeKind` (32) carry the most arms across the codebase
  — touching their semantics tends to ripple.

## How to update this doc

Re-run the per-variant counts after a refactor lands. The script
(stored inline in `audit_enum_dispatch.md`'s git history under the
prompt that produced this snapshot) is a single Python pass over
`src/` with a `grep -rE` per variant.
