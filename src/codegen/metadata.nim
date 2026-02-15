type
  AllocKind* = enum
    AK_PLAIN            ## _init, System_box_*, System_allocate
    AK_STATUS_OWNED     ## String_get, Array_get (inner pointer is owned)
    AK_STATUS_BORROWED  ## Array_set (inner pointer is borrowed)

  FunctionMetadata* = ref object of RootObj
    allocates*: bool
    mutates_args*: bool
    reads_only*: bool
    returns_allocated*: bool
    alloc_kind*: AllocKind
    consumes_args*: bool

proc new_function_metadata*(): FunctionMetadata =
  FunctionMetadata(allocates: false, mutates_args: false,
      reads_only: true, returns_allocated: false,
      alloc_kind: AK_PLAIN, consumes_args: false)
