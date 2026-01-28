import tables, results

type Error*[T] = ref object of RootObj
  current: T
  previous: T

proc new_error[T](current: T, previous: T): Error[T] =
  Error[T](current: current, previous: previous)

proc current*[T](error: Error[T]): T = error.current
proc previous*[T](error: Error[T]): T = error.previous

type Key[K, V] = proc(value: V): K {.nimcall.}

type Repo*[K, V] = ref object of RootObj
  key: Key[K, V]
  items: seq[V]
  items_map: Table[K, int]

proc new_repo*[K, V](items: seq[V], key: Key[K, V]): Result[Repo[K, V], Error[V]] =
  var items_map: Table[K, int]
  for index, item in items:
    let k = key(item)
    if k in items_map: return err(new_error(item, items[items_map[k]]))
    items_map[k] = index
  ok(Repo[K, V](key: key, items: items, items_map: items_map))

proc new_repo*[V](items: seq[V]): Result[Repo[V, V], Error[V]] =
  new_repo[V, V](items, proc(x: V): V = x)

proc items*[K, V](repo: Repo[K, V]): seq[V] = repo.items

proc find*[K, V](repo: Repo[K, V], key: K): Result[V, void] =
  if key notin repo.items_map: err()
  else: ok(repo.items[repo.items_map[key]])

proc find*[K, V](repo: Repo[K, V], index: int): Result[V, void] =
  if index < 0 or index > repo.items.len: err()
  else: ok(repo.items[index])
