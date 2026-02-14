# Static metadata for C runtime functions (runtime.c).
#
# Only functions with non-default behavior are listed here.
# Functions not in this table are assumed to be reads_only
# (no allocation, no mutation, no ownership transfer).

import tables

import ../metadata

proc add_runtime_metadata*(metadata: var Table[string, FunctionMetadata]) =
  # --- Memory ---
  metadata["System_allocate"] = FunctionMetadata(
      allocates: true, returns_allocated: true,
      reads_only: false, alloc_kind: AK_PLAIN)

  # --- Boxing (allocates a Pointer wrapper for a primitive value) ---
  for typ in ["S8", "S16", "S32", "S64", "U8", "U16", "U32", "U64",
      "F32", "F64", "String", "Pointer"]:
    metadata["System_box_" & typ] = FunctionMetadata(
        allocates: true, returns_allocated: true,
        reads_only: false, alloc_kind: AK_PLAIN)

  # --- String ---
  metadata["String_get"] = FunctionMetadata(
      allocates: true, returns_allocated: true,
      reads_only: false, alloc_kind: AK_STATUS_OWNED)

  # --- Array ---
  metadata["Array_get"] = FunctionMetadata(
      allocates: true, returns_allocated: true,
      reads_only: false, alloc_kind: AK_STATUS_OWNED)
  metadata["Array_set"] = FunctionMetadata(
      allocates: true, returns_allocated: true,
      mutates_args: true, reads_only: false,
      alloc_kind: AK_STATUS_BORROWED)
