import results, strutils, strformat

import constants

proc match_string*(content: string, start: int): Result[
    int, string] =
  var index = start
  if index >= content.len:
    return err("reached eof")

  if content[index] != DOUBLE_QUOTE:
    return err(fmt"expected `{DOUBLE_QUOTE}` found `{content[index]}`")

  index += 1
  if index >= content.len:
    return err("reached eof")

  while index < content.len and content[index] != DOUBLE_QUOTE:
    if content[index] == BACK_SLASH_OP:
      if index + 1 >= content.len:
        return err("reached eof")
      if content[index + 1] notin STRING_ESCAPE_SEQS:
        return err("unknown string escape characters encountered")
      index += 2
    else:
      index += 1
  return ok(index + 1)

proc match_comment*(content: string, start: int): Result[
    int, string] =
  var index = start
  if index >= content.len:
    return err("reached eof")

  if content[index] != HASHTAG:
    return err(fmt"expected `{HASHTAG}` found `{content[index]}`")

  while index < content.len and content[index] != NEW_LINE:
    index += 1

  ok(index)

proc match_digit*(content: string, start: int): Result[
    int, string] =
  var index = start
  if index >= content.len:
    return err("reached eof")

  if not content[index].is_digit:
    return err(fmt"expected a digit found `{content[index]}`")

  while index < content.len and content[index].is_digit:
    index += 1
  ok(index)

proc match_alphabet*(content: string, start: int): Result[
    int, string] =
  var index = start
  if index >= content.len:
    return err("reached eof")

  if not content[index].is_alpha_ascii:
    return err(fmt"expected a digit found `{content[index]}`")

  while index < content.len and content[index].is_alpha_ascii:
    index += 1
  ok(index)
