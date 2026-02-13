# Standard library imports
import results

# Parser submodules (ordered by dependency)
import parser/tokenizer
export tokenizer

import parser/core
export core

import parser/identifier
export identifier

import parser/module_ref
export module_ref

import parser/defs
export defs

import parser/literal
export literal

import parser/struct
export struct

import parser/arg
export arg

import parser/initializer
export initializer

import parser/pattern
export pattern

import parser/expression
export expression

import parser/generic
export generic

import parser/function
export function

import parser/module
export module

import parser/file
export file

proc parse*(path: string, tokens: seq[Token]): Result[file.File, string] =
  let parser = new_parser(path, tokens)
  let maybe_parsed = file_spec(parser)
  if maybe_parsed.is_ok: ok(maybe_parsed.get)
  else: err($(maybe_parsed.error))
