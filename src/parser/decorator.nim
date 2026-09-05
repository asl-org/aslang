import strformat

import identifiers

# ============================================================
# Decorator
# ============================================================

type Decorator* = ref object
  name: Identifier

proc newDecorator*(name: Identifier): Decorator =
  Decorator(name: name)

proc asl*(decorator: Decorator): string =
  fmt"@{decorator.name.asl}"
