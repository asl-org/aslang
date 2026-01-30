import tables, options, sequtils, hashes, results, strformat

type Error*[T] = ref object of RootObj
  current: T
  previous: T

proc new_error[T](current: T, previous: T): Error[T] =
  Error[T](current: current, previous: previous)

proc current*[T](error: Error[T]): T = error.current
proc previous*[T](error: Error[T]): T = error.previous

type
  IndexNodeKind = enum
    INK_LEAF, INK_NON_LEAF
  IndexNode = ref object of RootObj
    case kind: IndexNodeKind
    of INK_LEAF: ids: seq[int]
    of INK_NON_LEAF: children: Table[Hash, IndexNode]

proc new_index_node(): IndexNode = IndexNode(kind: INK_NON_LEAF)
proc new_index_node(id: int): IndexNode = IndexNode(kind: INK_LEAF, ids: @[id])
proc insert(index_node: IndexNode, id: int): IndexNode =
  do_assert index_node.kind == INK_LEAF, "IndexNode insertion failed"
  index_node.ids.add(id)
  return index_node

type
  SingletonKey = concept x
    hash(x) is Hash
  # NOTE: Represents non-empty tuple
  CompositeKey = concept x
    x is tuple
    compiles(x[0])

  IndexKey = SingletonKey | CompositeKey

proc normalize(key: IndexKey): seq[Hash] =
  when key is SingletonKey:
    @[hash(key)]
  elif key is CompositeKey:
    for k in key.fields: result.add(hash(k))

type Index*[T] = ref object of RootObj
  name: string
  primary: bool
  root: IndexNode
  key: proc(item: T): seq[Hash]

proc new_index*[T](name: string, key: proc(item: T): IndexKey,
    primary: bool): Index[T] =
  let normalized_key = proc(item: T): seq[Hash] = normalize(key(item))
  Index[T](name: name, primary: primary, root: new_index_node(),
      key: normalized_key)

proc new_index*[T](name: string, key: proc(item: T): IndexKey): Index[T] =
  new_index[T](name, key, false)

proc insert[T](index: Index[T], id: int, item: T): Result[Index[T], (int, int)] =
  var parent: Option[IndexNode]
  var node = index.root
  var hvals = index.key(item)
  for h in hvals:
    do_assert node.kind == INK_NON_LEAF, "[ERROR]: Failed insert item into index `{index.name}`"
    parent = some(node)
    node = node.children.mget_or_put(h, new_index_node())

  case node.kind:
  of INK_LEAF:
    if index.primary:
      err((id, node.ids[0]))
    else:
      node = node.insert(id)
      ok(index)
  of INK_NON_LEAF:
    do_assert parent.is_some, "[ERROR]: Failed insert item into index `{index.name}`"
    parent.get.children[hvals[^1]] = new_index_node(id)
    ok(index)

proc find[T](index: Index[T], keys: IndexKey): Result[seq[int], string] =
  var node = index.root
  for k in normalize(keys):
    case node.kind:
    of INK_LEAF: return err("[ERROR]: Failed find item in index `{index.name}`")
    of INK_NON_LEAF:
      if k notin node.children:
        return err("[ERROR]: Failed find item in index `{index.name}`")
      node = node.children[k]

  case node.kind:
  of INK_NON_LEAF:
    err("[ERROR]: Failed find item in index `{index.name}`")
  of INK_LEAF:
    ok(node.ids)

type Repo*[T] = ref object of RootObj
  items: seq[T]
  index_map: Table[string, Index[T]]

proc new_repo*[T](items: seq[T], indexes: seq[Index[T]]): Result[
    Repo[T], Error[T]] =
  var index_map: Table[string, Index[T]]
  for index in indexes:
    if index.name in index_map:
      do_assert index.name notin index_map, fmt"[ERROR]: Duplicate index encountered `{index.name}`"
    index_map[index.name] = index

    for id, item in items:
      let maybe_inserted = index.insert(id, item)
      if maybe_inserted.is_err:
        let (current, previous) = maybe_inserted.error
        return err(new_error[T](items[current], items[previous]))
  ok(Repo[T](items: items, index_map: index_map))

proc items*[T](repo: Repo[T]): seq[T] = repo.items

proc find_id*[T](repo: Repo[T], index: string, keys: IndexKey): Result[seq[int], string] =
  if index notin repo.index_map:
    err(fmt"Index `{index}` is not present in the repo")
  else:
    repo.index_map[index].find(keys)

proc find*[T](repo: Repo[T], index: string, keys: IndexKey): Result[seq[T], string] =
  let ids = ? repo.find_id(index, keys)
  ok(ids.map_it(repo.items[it]))
