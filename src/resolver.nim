import results

import parser, validator
export parser, validator

# Disambiguate against syncio.File
type File = parser.File

# ============================================================
# Resolved App
# ============================================================

type
  ResolvedApp* = ref object

proc resolve*(app: App): Result[ResolvedApp, string] =
  ok(ResolvedApp())
