## Phase-B analysis contexts — the nested ladder threaded through the body
## walk so each walker takes ONE context instead of (file, module,
## function) separately:
##
##   AnalyzedFileContext  ←  AnalyzedModuleContext  ←  AnalyzedUserFunctionContext
##
## Each wraps the one below and delegates type lookups down to it; the
## function context additionally holds the variable scope. Every lookup is
## identity-keyed (ResolvedLocalType -> AnalyzedLocalType) — name
## resolution happened at resolve time, so by the time the analyzer runs
## each reference already carries its identity.
##
## AnalyzedFileContext resolves a file's in-scope types: imported types to
## the analyzed twin from their SOURCE file (`appDef.importedTypes(imp)`),
## local types via this file's own def bundle (`file.findType`). A file may
## import each source path at most once (rejected at parse time), so every
## imported type enters the index exactly once — the construction assert is
## a can't-happen [BUG] guard, not user-facing.

import strformat, tables, options, results

import ../parser/main as parser
import ../resolver/main as resolver
import ../defanalyzer/main as defanalyzer

import statement
import pattern

type AnalyzedFileContext* = ref object
  app: AnalyzedDefApp
  file: AnalyzedDefFile
  importedTypeIndex: Table[ResolvedLocalType, AnalyzedLocalType]

proc newAnalyzedFileContext*(app: AnalyzedDefApp, file: AnalyzedDefFile): AnalyzedFileContext =
  var importedTypeIndex: Table[ResolvedLocalType, AnalyzedLocalType]
  for imp in file.imports:
    for impType in app.importedTypes(imp):
      assert(impType.resolved notin importedTypeIndex, fmt"[BUG] - {impType.resolved.loc} conflicting entries for type `{impType.resolved.name.asl}` in the file context")
      importedTypeIndex[impType.resolved] = impType
  AnalyzedFileContext(app: app, file: file, importedTypeIndex: importedTypeIndex)

proc findType*(context: AnalyzedFileContext, resolved: ResolvedLocalType): AnalyzedLocalType =
  if resolved in context.importedTypeIndex: context.importedTypeIndex[resolved]
  else: context.file.findType(resolved)

proc findModule*(context: AnalyzedFileContext, module: ResolvedModule): AnalyzedDefModule =
  let typ = context.findType(newResolvedLocalType(module))
  assert(typ.kind == altkModule, fmt"[BUG] - {module.loc} `{module.name.asl}` was analyzed as a module in phase A")
  typ.module

type AnalyzedModuleContext* = ref object
  file: AnalyzedFileContext
  module: AnalyzedDefModule

proc newAnalyzedModuleContext*(file: AnalyzedFileContext, module: AnalyzedDefModule): AnalyzedModuleContext =
  AnalyzedModuleContext(file: file, module: module)

proc findType*(context: AnalyzedModuleContext, resolved: ResolvedLocalType): AnalyzedLocalType = context.file.findType(resolved)
proc findModule*(context: AnalyzedModuleContext, module: ResolvedModule): AnalyzedDefModule = context.file.findModule(module)

type AnalyzedUserFunctionContext* = ref object
  module: AnalyzedModuleContext
  function: AnalyzedDefUserFunction
  scope: Table[Identifier, AnalyzedBinding]

proc newAnalyzedUserFunctionContext*(module: AnalyzedModuleContext, function: AnalyzedDefUserFunction): AnalyzedUserFunctionContext =
  var scope: Table[Identifier, AnalyzedBinding]
  for argDef in function.def.args:
    assert(argDef.name notin scope, fmt"{argDef.loc}: [BUG] duplicate function argument names encountered")
    scope[argDef.name] = newAnalyzedBinding(argDef.name, argDef.argType)
  AnalyzedUserFunctionContext(module: module, function: function, scope: scope)

proc module*(context: AnalyzedUserFunctionContext): AnalyzedDefModule = context.module.module
proc findType*(context: AnalyzedUserFunctionContext, resolved: ResolvedLocalType): AnalyzedLocalType = context.module.findType(resolved)
proc findModule*(context: AnalyzedUserFunctionContext, module: ResolvedModule): AnalyzedDefModule = context.module.findModule(module)

proc update*(funcCtx: AnalyzedUserFunctionContext, statement: AnalyzedStatement): AnalyzedUserFunctionContext =
  if statement.arg.isSome:
    let arg = statement.arg.get
    funcCtx.scope[arg.name] = arg
  return funcCtx

proc update*(funcCtx: AnalyzedUserFunctionContext, pattern: AnalyzedCasePattern): AnalyzedUserFunctionContext =
  for binding in pattern.bindings:
    funcCtx.scope[binding.name] = binding
  return funcCtx

proc get*(funcCtx: AnalyzedUserFunctionContext, name: Identifier): Result[AnalyzedBinding, string] =
  if name in funcCtx.scope: ok(funcCtx.scope[name])
  else: err(fmt"{name.loc} variable `{name.asl}` does not exist in scope")