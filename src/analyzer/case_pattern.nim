import results, strformat, tables, hashes, sets

import resolver
import module_ref
import arg_def
import file_def
import func_ref
import struct_pattern

type
  AnalyzedCasePatternKind* = enum
    RCPK_LITERAL, RCPK_STRUCT
  AnalyzedCasePattern* = ref object of RootObj
    location: Location
    case kind: AnalyzedCasePatternKind
    of RCPK_LITERAL:
      module: ResolvedModule
      literal: Literal
    of RCPK_STRUCT:
      struct: AnalyzedStructPattern

proc new_analyzed_case_pattern(module: ResolvedModule,
    literal: Literal, location: Location): AnalyzedCasePattern =
  AnalyzedCasePattern(kind: RCPK_LITERAL, module: module,
      literal: literal, location: location)

proc new_analyzed_case_pattern(struct: AnalyzedStructPattern,
    location: Location): AnalyzedCasePattern =
  AnalyzedCasePattern(kind: RCPK_STRUCT, struct: struct, location: location)

proc kind*(pattern: AnalyzedCasePattern): AnalyzedCasePatternKind = pattern.kind
proc literal*(pattern: AnalyzedCasePattern): Literal =
  do_assert pattern.kind == RCPK_LITERAL, "expected literal pattern"
  pattern.literal
proc struct*(pattern: AnalyzedCasePattern): AnalyzedStructPattern =
  do_assert pattern.kind == RCPK_STRUCT, "expected struct pattern"
  pattern.struct

proc hash*(pattern: AnalyzedCasePattern): Hash =
  case pattern.kind:
  of RCPK_LITERAL: pattern.literal.asl.hash
  of RCPK_STRUCT: pattern.struct.hash

proc `==`*(self: AnalyzedCasePattern, other: AnalyzedCasePattern): bool =
  self.hash == other.hash

proc generic_impls*(pattern: AnalyzedCasePattern): Table[ResolvedModule, seq[
    HashSet[AnalyzedImpl]]] =
  var impl_set: Table[ResolvedModule, seq[HashSet[AnalyzedImpl]]]
  case pattern.kind:
  of RCPK_LITERAL: discard
  of RCPK_STRUCT: impl_set = impl_set.merge(pattern.struct.generic_impls)
  return impl_set

proc asl*(case_pattern: AnalyzedCasePattern): string =
  case case_pattern.kind:
  of RCPK_LITERAL: case_pattern.literal.asl
  of RCPK_STRUCT: case_pattern.struct.asl

proc analyze*(file_def: AnalyzedFileDefinition, scope: FunctionScope,
    operand: AnalyzedModuleRef, pattern: CasePattern): Result[
    AnalyzedCasePattern, string] =
  case pattern.kind:
  of CPK_LITERAL:
    let literal = ? pattern.literal
    case operand.kind:
    of AMRK_GENERIC:
      err(fmt"{pattern.location} match expression does not support generic operands")
    of AMRK_MODULE:
      let module = operand.module
      case module.name.asl:
      of "S8", "S16", "S32", "S64", "U8", "U16", "U32", "U64":
        ? module.validate(literal)
        ok(new_analyzed_case_pattern(module, literal, pattern.location))
      else:
        err(fmt"{pattern.location} only integer literals are supported in the case pattern")
  of CPK_STRUCT:
    let struct = ? pattern.struct
    let analyzed_struct_pattern = ? analyze(file_def, scope, operand, struct)
    ok(new_analyzed_case_pattern(analyzed_struct_pattern, pattern.location))

proc analyze*(scope: FunctionScope, variable: ResolvedVariable): Result[
    AnalyzedArgumentDefinition, string] =
  let analyzed_module_ref = ? scope.get(variable.name)
  ok(new_analyzed_argument_definition(analyzed_module_ref, variable.name,
      variable.location))
