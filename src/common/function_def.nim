import strformat, strutils, results

import identifier, variable

type Signature = ref object of RootObj
  returns: Identifier
  variables: seq[Variable]

proc variables*(sign: Signature): seq[Variable] = sign.variables
proc returns*(sign: Signature): Identifier = sign.returns

proc `$`*(signature: Signature): string =
  var acc: seq[string]
  for variable in signature.variables:
    acc.add($(variable))

  var call_args = acc.join(", ")
  fmt"({call_args}) returns {signature.returns}"

proc `==`*(self: Signature, other: Signature): bool =
  if self.variables.len != other.variables.len:
    return false

  for index, self_var in self.variables:
    if other.variables[index].module != self_var.module:
      return false

  return true

proc new_signature*(return_module: string, variables: seq[
    Variable]): Signature =
  Signature(returns: new_identifier(return_module), variables: variables)

type FunctionDef* = ref object of RootObj
  name: Identifier
  signatures: seq[Signature]

proc signatures*(def: FunctionDef): seq[Signature] = def.signatures

proc `$`*(def: FunctionDef): string =
  var acc: seq[string]
  for sign in def.signatures:
    acc.add(fmt"fn {def.name}{sign}")
  acc.join("\n")

proc name*(def: FunctionDef): Identifier = def.name

proc new_function_def*(name: string): FunctionDef =
  FunctionDef(name: new_identifier(name))

proc find_signature(def: FunctionDef, signature: Signature): Result[Signature, string] =
  for sign in def.signatures:
    if sign == signature:
      return ok(sign)
  return err(fmt"Signature {signature} not found")

proc add_signature*(def: FunctionDef, signature: Signature): Result[FunctionDef, string] =
  let maybe_signature = def.find_signature(signature)
  if maybe_signature.is_ok:
    return err(fmt"Signature {signature} already exists")
  def.signatures.add(signature)
  ok(def)

proc match_variables*(signature: Signature, variables: seq[Variable]): Result[
    Identifier, string] =
  if signature.variables.len != variables.len:
    return err(fmt"Argument length does not match with signature {signature}")

  for index, sign_var in signature.variables:
    if sign_var.module != variables[index].module:
      return err(fmt"Expected {sign_var} but found {variables[index].module}")

  return ok(signature.returns)
