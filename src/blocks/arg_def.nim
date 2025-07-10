import hashes, strformat

import token

type ArgumentDefinition* = ref object of RootObj
  arg_type*: Token
  arg_name*: Token

proc location*(arg_def: ArgumentDefinition): Location = arg_def.arg_type.location
proc hash*(arg_def: ArgumentDefinition): Hash = arg_def.arg_type.hash
proc `$`*(arg_def: ArgumentDefinition): string = fmt"{arg_def.arg_type} {arg_def.arg_name}"

proc byte_size*(arg_def: ArgumentDefinition): uint =
  case $(arg_def.arg_type):
  of "U8", "S8": 1
  of "U16", "S16": 2
  of "U32", "S32", "F32": 4
  of "U64", "S64", "F64", "Pointer": 8
  else: 8

proc native_type*(arg_def: ArgumentDefinition): string =
  case $(arg_def.arg_type):
  of "U8", "U16", "U32", "U64", "S8", "S16", "S32", "S64", "F32", "F64",
      "Pointer": $(arg_def.arg_type)
  else: "Pointer"

proc c*(arg_def: ArgumentDefinition): string =
  fmt"{arg_def.native_type} {arg_def.arg_name}"

proc new_argument_definition*(arg_type: Token,
    arg_name: Token): ArgumentDefinition =
  ArgumentDefinition(arg_type: arg_type, arg_name: arg_name)

proc new_argument_definition*(arg_type: string,
    arg_name: string): ArgumentDefinition =
  let arg_type_token = new_id_token(arg_type)
  let arg_name_token = new_id_token(arg_name)
  new_argument_definition(arg_type_token, arg_name_token)
