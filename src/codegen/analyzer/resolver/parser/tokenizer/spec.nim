import results, strutils

import constants
import error

proc match_string*(content: string, start: int): Result[
    int, Error] =
  var index = start
  if index >= content.len: return err(err_tokenizer_reached_eof(index))

  if content[index] != DOUBLE_QUOTE:
    return err(err_tokenizer_expectation_mismatch(index, $DOUBLE_QUOTE,
        $content[index]))

  index += 1
  if index >= content.len: return err(err_tokenizer_reached_eof(index))

  while index < content.len:
    if content[index] == BACK_SLASH_OP:
      if index + 1 >= content.len:
        return err(err_tokenizer_reached_eof(index + 1))
      if content[index + 1] notin STRING_ESCAPE_SEQS:
        let escape_seq = content.substr(index, index + 1)
        return err(err_tokenizer_unexpected_escape_sequence(index, escape_seq))
      index += 2
    elif content[index] == DOUBLE_QUOTE:
      if index + 1 - start > MAX_STRING_LENGTH:
        return err(err_tokenizer_max_length_exceeded(start, "string",
            MAX_STRING_LENGTH))
      return ok(index + 1)
    elif content[index] == NEW_LINE:
      return err(err_tokenizer_new_line_in_string(index))
    else:
      index += 1

  err(err_tokenizer_reached_eof(index))

proc match_comment*(content: string, start: int): Result[
    int, Error] =
  var index = start
  if index >= content.len: return err(err_tokenizer_reached_eof(index))

  if content[index] != HASHTAG:
    return err(err_tokenizer_expectation_mismatch(index, $HASHTAG, $content[index]))

  while index < content.len and content[index] != NEW_LINE:
    index += 1

  ok(index)

proc match_digit*(content: string, start: int): Result[
    int, Error] =
  var index = start
  if index >= content.len: return err(err_tokenizer_reached_eof(index))

  if not content[index].is_digit:
    return err(err_tokenizer_expectation_mismatch(index, "digit", $content[index]))

  while index < content.len and content[index].is_digit:
    if index - start > MAX_DIGITS_LENGTH:
      return err(err_tokenizer_max_length_exceeded(start, "numeric",
          MAX_DIGITS_LENGTH))
    index += 1
  ok(index)

proc match_alphabet*(content: string, start: int): Result[
    int, Error] =
  var index = start
  if index >= content.len: return err(err_tokenizer_reached_eof(index))

  if not content[index].is_alpha_ascii:
    return err(err_tokenizer_expectation_mismatch(index, "alphabet", $content[index]))

  while index < content.len and content[index].is_alpha_ascii:
    index += 1
  ok(index)
