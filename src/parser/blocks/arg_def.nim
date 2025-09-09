import hashes, strformat, sequtils, strutils

import token

type ArgumentType* = ref object of RootObj
  parent*: Token
  children*: seq[ArgumentType]

proc new_argument_type*(parent: Token): ArgumentType =
  ArgumentType(parent: parent)

proc new_argument_type*(parent: Token, children: seq[
    ArgumentType]): ArgumentType =
  ArgumentType(parent: parent, children: children)

proc location*(arg_type: ArgumentType): Location =
  arg_type.parent.location

proc `$`*(arg_type: ArgumentType): string =
  let children = arg_type.children.map_it($(it)).join(", ")
  if children.len == 0: return $(arg_type.parent)
  return fmt"{arg_type.parent}[{children}]"

proc hash*(arg_type: ArgumentType): Hash =
  let parent_hash = hash(arg_type.parent)
  var children_hash: Hash
  for child in arg_type.children:
    children_hash = children_hash !& hash(child)
  parent_hash !& children_hash

type ArgumentDefinition* = ref object of RootObj
  typ*: ArgumentType
  name*: Token

proc new_argument_definition*(typ: ArgumentType,
    name: Token): ArgumentDefinition =
  ArgumentDefinition(typ: typ, name: name)

proc new_argument_definition*(arg_type: string,
    arg_name: string): ArgumentDefinition =
  let arg_type_token = new_argument_type(new_id_token(arg_type))
  let arg_name_token = new_id_token(arg_name)
  new_argument_definition(arg_type_token, arg_name_token)

proc location*(arg_def: ArgumentDefinition): Location = arg_def.typ.location
proc hash*(arg_def: ArgumentDefinition): Hash = arg_def.typ.hash
proc `$`*(arg_def: ArgumentDefinition): string = fmt"{arg_def.typ} {arg_def.name}"

proc byte_size*(arg_def: ArgumentDefinition): uint =
  case $(arg_def.typ):
  of "U8", "S8": 1
  of "U16", "S16": 2
  of "U32", "S32", "F32": 4
  of "U64", "S64", "F64", "Pointer": 8
  else: 8

proc native_type*(arg_def: ArgumentDefinition): string =
  case $(arg_def.typ):
  of "U8", "U16", "U32", "U64", "S8", "S16", "S32", "S64", "F32", "F64",
      "Pointer": $(arg_def.typ)
  else: "Pointer"

proc c*(arg_def: ArgumentDefinition): string =
  fmt"{arg_def.native_type} {arg_def.name}"
