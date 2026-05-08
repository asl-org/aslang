## Function references for call-site resolution: given an
## ArgumentType + (name, arity), look up the candidate function
## definitions inside the target generic or module. The resolver
## collects candidates only; overload selection is the Analyzer's job.
##
## Also owns FunctionScope (HashSet[Identifier]) — the body-level
## variable name set — since resolveFunctionRef is the first proc
## that needs it as a parameter.

import results, sets, strformat, tables

import parser
import argtypes

# FunctionScope alias — names of variables currently in scope inside
# a function body. body.nim and decls.nim each import this.
type FunctionScope* = HashSet[Identifier]

# ResolvedGenericTypeRef
type ResolvedGenericTypeRef* = ref object
  generic: Generic
  funcDefs: seq[FunctionDefinition]

proc newResolvedGenericTypeRef*(generic: Generic,
    funcDefs: seq[FunctionDefinition]): ResolvedGenericTypeRef =
  ResolvedGenericTypeRef(generic: generic, funcDefs: funcDefs)

proc resolveGenericTypeRef(generic: Generic, name: Identifier,
    arity: int): Result[ResolvedGenericTypeRef, string] =
  let funcDefs = ? generic.findFunctionDefs(name, arity)
  ok(newResolvedGenericTypeRef(generic, funcDefs))

# ResolvedModuleTypeRef
type ResolvedModuleTypeRef* = ref object
  module: Module
  functions: seq[Function]

proc newResolvedModuleTypeRef*(module: Module,
    functions: seq[Function]): ResolvedModuleTypeRef =
  ResolvedModuleTypeRef(module: module, functions: functions)

proc resolveModuleTypeRef(typeModule: Module, name: Identifier,
    arity: int): Result[ResolvedModuleTypeRef, string] =
  let functions = ? typeModule.findFunctions(name, arity)
  ok(newResolvedModuleTypeRef(typeModule, functions))

# ResolvedDefinedTypeRef
type
  ResolvedDefinedTypeRefKind* = enum
    rdtrkGeneric, rdtrkModule
  ResolvedDefinedTypeRef* = ref object
    case kind: ResolvedDefinedTypeRefKind
    of rdtrkGeneric: generic: ResolvedGenericTypeRef
    of rdtrkModule: module: ResolvedModuleTypeRef

proc newResolvedDefinedTypeRef*(
    generic: ResolvedGenericTypeRef): ResolvedDefinedTypeRef =
  ResolvedDefinedTypeRef(kind: rdtrkGeneric, generic: generic)

proc newResolvedDefinedTypeRef*(
    module: ResolvedModuleTypeRef): ResolvedDefinedTypeRef =
  ResolvedDefinedTypeRef(kind: rdtrkModule, module: module)

proc resolveDefinedTypeRef(definedType: DefinedType, name: Identifier,
    arity: int): Result[ResolvedDefinedTypeRef, string] =
  case definedType.kind:
  of dtkModule:
    let resolvedModuleTypeRef = ? resolveModuleTypeRef(definedType.module, name,
      arity)
    ok(newResolvedDefinedTypeRef(resolvedModuleTypeRef))
  of dtkGeneric:
    let resolvedGenericTypeRef = ? resolveGenericTypeRef(definedType.generic,
      name, arity)
    ok(newResolvedDefinedTypeRef(resolvedGenericTypeRef))

# ResolvedFunctionRef — currently only the rfrkDefined arm; an
# rfrkImported arm would mirror the imported path inside.
type
  ResolvedFunctionRefKind* = enum
    rfrkDefined
  ResolvedFunctionRef* = ref object
    case kind: ResolvedFunctionRefKind
    of rfrkDefined: definedRef: ResolvedDefinedTypeRef

proc newResolvedFunctionRef*(
    definedRef: ResolvedDefinedTypeRef): ResolvedFunctionRef =
  ResolvedFunctionRef(kind: rfrkDefined, definedRef: definedRef)

proc resolveFunctionRef*(app: App, file: parser.File, fileScope: FileScope,
    module: Module, scope: FunctionScope, argType: ArgumentType,
    name: Identifier, arity: int): Result[ResolvedFunctionRef, string] =
  discard ? resolveArgumentType(app, file, fileScope, module, argType)

  let rootModule = ? file.findType(argType.root)
  case rootModule.kind:
  of tkImported:
    let impType = rootModule.imported
    if impType.binding notin fileScope:
      err(fmt"{impType.loc} type `{impType.binding.asl}` does not exist in file scope")
    else:
      let impDefinedType = fileScope[impType.binding]
      let resolvedDefinedRef = ? resolveDefinedTypeRef(impDefinedType, name,
        arity)
      ok(newResolvedFunctionRef(resolvedDefinedRef))
  of tkDefined:
    let resolvedDefinedRef = ? resolveDefinedTypeRef(rootModule.definedType,
      name, arity)
    ok(newResolvedFunctionRef(resolvedDefinedRef))
