## AnalyzedImplMap operations. The type itself lives with the argument
## types in ./argtype (it IS a module argtype's `impls` — the ordered
## slot→impl map). This file owns the two operations over it:
##
## `merge` combines two maps and detects conflicts (same generic bound
## to two different concrete types) — the strict one-to-one guarantee.
## `concrete` substitutes any free generic in `argType` for its
## bound value from `implMap`, recursing through module impls.

import results, strformat, tables

import ./resolver

import ./genericargtype
import ./argtype

proc merge*(global: var AnalyzedImplMap, local: AnalyzedImplMap): Result[AnalyzedImplMap, string] =
  # TODO(union-inference): eagerly collapse substitution chains.
  # When inserting `K → u8`, also rewrite any existing values in the
  # map that mention K as a free generic (e.g. an earlier
  # `Sample → K` becomes `Sample → u8`). This keeps `concrete()` a
  # single-pass lookup and prevents free generics from getting stuck
  # half-resolved when one use site binds another generic that they
  # depend on. Also: the `!=` conflict check on the next line needs
  # to become a unification check once free generics can appear on
  # either side (a bound u8 vs a free K should not "conflict" — K
  # should unify to u8).
  for generic, impl in local:
    if generic in global and global[generic] != impl:
      return err(fmt"{impl.loc} generic `{generic.name.asl}` already bound to `{global[generic].asl}` (at {global[generic].loc}) but here resolves to `{impl.asl}` — one generic binds to one concrete type per construction; declare a second generic if you need independent types")
    else:
      global[generic] = impl
  ok(global)

proc concrete*(argType: AnalyzedArgumentType, implMap: AnalyzedImplMap): AnalyzedArgumentType =
  # TODO(union-inference): handle substitution chains. A single use
  # site can produce an implMap with both `Sample → K` and `K → u8`
  # (e.g. `func f(a: Box[u8, K], b: K)` called as
  # `f(boxFirst, u8 5)`). Today getOrDefault returns the immediate
  # map value, so `Sample` rewrites to `K`, not `u8`. Prefer eager
  # chain-collapsing in `merge` (cheaper, single pass) — see the TODO
  # there — over recursive lookup here.
  case argType.kind:
  of aatkModule:
    let moduleArgType = argType.module
    # Rebuild the ordered slot→impl map, concretizing each impl and
    # keeping the same slot keys and order.
    var concreteImpls: AnalyzedImplMap
    for generic, impl in moduleArgType.impls:
      concreteImpls[generic] = impl.concrete(implMap)
    let concreteModuleArgType = newAnalyzedModuleArgumentType(moduleArgType.resolved, moduleArgType.module, concreteImpls)
    return newAnalyzedArgumentType(concreteModuleArgType)
  of aatkGeneric:
    let genericArgType = argType.generic
    return implMap.getOrDefault(genericArgType.generic, argType)
