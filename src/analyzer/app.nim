## AnalyzedApp — the top-level container returned by `analyze`.
##
## Post-6c the analyzer has no separate def-level pass — every
## definition-level index and accessor is carried directly on the
## resolver's ResolvedApp / ResolvedFile / ResolvedModule / ResolvedGeneric
## / ResolvedStructDef / ResolvedUnionDef / ResolvedVariantDef. The facade's
## `analyze` walks the app tree file-by-file, seeds each file's scope
## from imports + local defined types, and drives per-module body
## analysis. Extern functions have no body to analyze — the walker
## skips them at the function layer.

import ./defanalyzer
import file

type AnalyzedApp* = ref object
  resolved: ResolvedApp
  files: seq[AnalyzedFile]

proc newAnalyzedApp*(resolved: ResolvedApp, files: seq[AnalyzedFile]): AnalyzedApp =
  AnalyzedApp(resolved: resolved, files: files)

