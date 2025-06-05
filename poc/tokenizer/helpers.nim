import results, strformat, strutils

proc expect_identifier_head(content: string, start: int): Result[string, string] =
  if start >= content.len:
    return err(fmt"expected an alphabet or '_' but reached end of input")
  if content[start] != '_' and (not content[start].is_alpha_ascii):
    return err(fmt"expected an alphabet or '_' but found {content[start]}")
  return ok(content.substr(start, start))

proc expect_identifier_tail(content: string, start: int): Result[string, string] =
  if start >= content.len:
    return err(fmt"expected an alphabet or '_' but reached end of input")
  if content[start] != '_' and (not content[start].is_alpha_numeric):
    return err(fmt"expected an alphabet, digit or '_' but found {content[start]}")

  var index = start
  while index < content.len and (content[index] == '_' or content[index].is_alpha_numeric):
    index += 1
  return ok(content.substr(start, index - 1))

proc expect_identifier*(content: string, start: int): Result[string, string] =
  var index = start
  let identifier_head = ? expect_identifier_head(content, index)
  index += identifier_head.len

  let maybe_identifier_tail = expect_identifier_tail(content, index)
  if maybe_identifier_tail.is_ok:
    index += maybe_identifier_tail.get.len

  return ok(content.substr(start, index - 1))

proc expect_double_quote(content: string, start: int): Result[string, string] =
  if start >= content.len:
    return err("expected '\"' but reached end of input")
  if content[start] != '"':
    return err("expected '\"' but found " & $(content[start]))
  return ok(content.substr(start, start))

proc expect_backslash(content: string, start: int): Result[string, string] =
  if start >= content.len:
    return err("expected '\\' but reached end of input")
  if content[start] == '"':
    return err("expected '\\' but found " & $(content[start]))
  return ok(content.substr(start, start))

proc expect_escaped_double_quote(content: string, start: int): Result[string, string] =
  var index = start
  let backslash = ? expect_backslash(content, index)
  index += backslash.len
  let double_quote = ? expect_double_quote(content, index)
  index += double_quote.len
  return ok(content.substr(start, index - 1))

proc expect_visible_ascii(content: string, start: int): Result[string, string] =
  if start >= content.len:
    return err(fmt"expected a visible ascii character between 32-126 but reached end of input")
  if content[start] != '_' and (not content[start].is_alpha_ascii):
    return err(fmt"expected a visible ascii character between 32-126 but found {content[start]}")
  return ok(content.substr(start, start))

proc expect_string_content(content: string, start: int): Result[string, string] =
  if start >= content.len:
    return err(fmt"expected a visible ascii character or escaped dobule quote but reached end of input")

  var index = start
  # NOTE: Order matters here since backslash in escaped double quote is also considered a valid visible char.
  let maybe_escaped_double_quote = expect_escaped_double_quote(content, index)
  if maybe_escaped_double_quote.is_ok:
    return maybe_escaped_double_quote

  let maybe_visible_ascii = expect_visible_ascii(content, index)
  if maybe_visible_ascii.is_ok:
    return maybe_visible_ascii

  err(fmt"expected a visible ascii character or escaped dobule quote but found {content[index]}")

proc expect_string*(content: string, start: int): Result[string, string] =
  var index = start
  var double_quote = ? expect_double_quote(content, index)
  index += double_quote.len

  var maybe_string_content = expect_string_content(content, index)
  while maybe_string_content.is_ok:
    index += maybe_string_content.get.len
    maybe_string_content = expect_string_content(content, index)

  double_quote = ? expect_double_quote(content, index)
  index += double_quote.len

  return ok(content.substr(start, index - 1))

proc expect_unsigned_integer(content: string, start: int): Result[string, string] =
  if start >= content.len:
    return err(fmt"expected a digit but reached end of input")
  if not content[start].is_digit:
    return err(fmt"expected a digit but found {content[start]}")

  var index = start
  while index < content.len and content[index].is_digit:
    index += 1
  return ok(content.substr(start, index - 1))

proc expect_sign(content: string, start: int): Result[string, string] =
  if start >= content.len:
    return err(fmt"expected '+' or '-' but reached end of input")
  if content[start] notin @['+', '-']:
    return err(fmt"expected '+' or '-' but found {content[start]}")
  return ok(content.substr(start, start))

proc expect_integer*(content: string, start: int): Result[string, string] =
  var index = start

  let maybe_sign = expect_sign(content, index)
  if maybe_sign.is_ok:
    index += maybe_sign.get.len

  let unsigned_integer = ? expect_unsigned_integer(content, index)
  index += unsigned_integer.len

  return ok(content.substr(start, index - 1))

proc expect_period(content: string, start: int): Result[string, string] =
  if start >= content.len:
    return err(fmt"expected '.' but reached end of input")
  if content[start] != '.':
    return err(fmt"expected '.' but found {content[start]}")
  return ok(content.substr(start, start))

proc expect_float*(content: string, start: int): Result[string, string] =
  var index = start

  let maybe_sign = expect_sign(content, index)
  if maybe_sign.is_ok:
    index += maybe_sign.get.len

  var maybe_unsigned_integer = expect_unsigned_integer(content, index)
  if maybe_unsigned_integer.is_ok:
    index += maybe_unsigned_integer.get.len

  let period = ? expect_period(content, index)
  index += period.len

  maybe_unsigned_integer = expect_unsigned_integer(content, index)
  if maybe_unsigned_integer.is_ok:
    index += maybe_unsigned_integer.get.len

  return ok(content.substr(start, index))
