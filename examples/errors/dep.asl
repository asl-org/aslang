# Support file — a minimal valid dependency imported by the
# negative fixtures only_imports.asl, import_module_collide.asl,
# alias_collide.asl and dup_name_in_import.asl. Not a negative test on
# its own (test.sh doesn't build it, so it has no entry module). `X` is
# public so that each importer's targeted error is the only thing wrong.
public module X:
  func start(y: i64): i64
    y
