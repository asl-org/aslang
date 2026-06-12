## Function references for call-site resolution: given an
## ArgumentType + (name, arity), look up the candidate function
## definitions inside the target generic or module. The resolver
## collects candidates only; overload selection is the Analyzer's job.
##
## Also owns FunctionScope (HashSet[Identifier]) — the body-level
## variable name set — since resolveFunctionRef is the first proc
## that needs it as a parameter.

import results, sets, strformat, tables

import tokenizer
import parser
import argtypes

# FunctionScope alias — names of variables currently in scope inside
# a function body. body.nim and decls.nim each import this.
type FunctionScope* = HashSet[Identifier]

proc resolveGenericTypeRef(generic: Generic, name: Identifier,
    arity: int, loc: Location): Result[void, string] =
  let funcDefs = ? generic.findFunctionDefs(name, arity)
  if funcDefs.len == 0:
    err(fmt"{loc} generic `{generic.name.asl}` does not have any function named `{name.asl}` with arity `{arity}`")
  else:
    ok()

proc resolveModuleTypeRef(module: Module, name: Identifier,
    arity: int, loc: Location): Result[void, string] =
  let funcs = ? module.findFunctions(name, arity)
  if funcs.len == 0:
    err(fmt"{loc} module `{module.name.asl}` does not have any function named `{name.asl}` with arity `{arity}`")
  else:
    ok()

proc resolveDefinedTypeRef(definedType: DefinedType, name: Identifier,
    arity: int, loc: Location): Result[void, string] =
  case definedType.kind:
  of dtkModule: resolveModuleTypeRef(definedType.module, name, arity, loc)
  of dtkGeneric: resolveGenericTypeRef(definedType.generic, name, arity, loc)

type
  ResolvedFunctionRef* = ref object
    parsed: FunctionCall
    argType: ResolvedArgumentType

proc newResolvedFunctionRef*(parsed: FunctionCall, argType: ResolvedArgumentType): ResolvedFunctionRef =
  ResolvedFunctionRef(parsed: parsed, argType: argType)

proc parsed*(funcRef: ResolvedFunctionRef): FunctionCall = funcRef.parsed
proc argType*(funcRef: ResolvedFunctionRef): ResolvedArgumentType = funcRef.argType
proc name*(funcRef: ResolvedFunctionRef): Identifier = funcRef.parsed.name
proc arity*(funcRef: ResolvedFunctionRef): int = funcRef.parsed.args.len
proc loc*(funcRef: ResolvedFunctionRef): Location = funcRef.parsed.loc

proc resolveFunctionRef*(app: App, file: parser.File, fileScope: FileScope,
    module: Module, scope: FunctionScope,
    fncall: FunctionCall): Result[ResolvedFunctionRef, string] =
  let resolvedArgType = ? resolveArgumentType(app, file, fileScope, module, fncall.argType)

  let rootModule = ? file.findType(fncall.argType.root)
  case rootModule.kind:
  of tkImported:
    let impType = rootModule.imported
    if impType.binding notin fileScope:
      err(fmt"{impType.loc} type `{impType.binding.asl}` does not exist in file scope")
    else:
      let impDefinedType = fileScope[impType.binding]
      ? resolveDefinedTypeRef(impDefinedType, fncall.name, fncall.args.len, fncall.loc)
      ok(newResolvedFunctionRef(fncall, resolvedArgType))
  of tkDefined:
    ? resolveDefinedTypeRef(rootModule.definedType, fncall.name, fncall.args.len, fncall.loc)
    ok(newResolvedFunctionRef(fncall, resolvedArgType))
