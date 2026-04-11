# Support file — a minimal valid dependency imported by the
# negative fixtures only_imports.asl, import_module_collide.asl,
# and alias_collide.asl. Not a negative test on its own; exists so
# the importing files can actually resolve their `import { X }`
# clause before the validator catches the target error.
module X:
  func start(y: i64): i64
    y
