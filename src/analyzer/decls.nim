## File / App + the public analyze* entry point. AnalyzedDefinedType
## and analyzeDefinedType live in modules.nim alongside their arms.

import results

import resolver
import filedefs

# AnalyzedAppDefinition + entry
type AnalyzedAppDefinition* = ref object
  resolved: ResolvedApp
  files: seq[AnalyzedFileDefinition]

proc newAnalyzedAppDefinition*(resolved: ResolvedApp, files: seq[AnalyzedFileDefinition]): AnalyzedAppDefinition =
  AnalyzedAppDefinition(resolved: resolved, files: files)

proc resolved*(a: AnalyzedAppDefinition): ResolvedApp = a.resolved
proc files*(a: AnalyzedAppDefinition): seq[AnalyzedFileDefinition] = a.files

proc analyze*(app: ResolvedApp): Result[AnalyzedAppDefinition, string] =
  var analyzedFileDefinitions: seq[AnalyzedFileDefinition]
  for file in app.files:
    let analyzedFileDefinition = ? analyzeFileDefinition(app, file)
    analyzedFileDefinitions.add(analyzedFileDefinition)
  ok(newAnalyzedAppDefinition(app, analyzedFileDefinitions))
