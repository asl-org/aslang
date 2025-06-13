import hashes, strformat

import token

type ArgumentDefinition* = ref object of RootObj
  arg_type*: Token
  arg_name*: Token

proc location*(arg_def: ArgumentDefinition): Location =
  arg_def.arg_type.location

proc hash*(arg_def: ArgumentDefinition): Hash = arg_def.arg_type.hash

proc `$`*(arg_def: ArgumentDefinition): string =
  fmt"{arg_def.arg_type} {arg_def.arg_name}"

proc new_argument_definition*(arg_type: Token,
    arg_name: Token): ArgumentDefinition =
  ArgumentDefinition(arg_type: arg_type, arg_name: arg_name)

proc new_argument_definition*(arg_type: string,
    arg_name: string): ArgumentDefinition =
  let arg_type_token = Token(kind: TK_ID, content: arg_type, location: Location())
  let arg_name_token = Token(kind: TK_ID, content: arg_name, location: Location())
  new_argument_definition(arg_type_token, arg_name_token)
