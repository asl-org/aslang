import strformat

type Error* = ref object of RootObj
  index: int
  message: string

proc `<`*(self: Error, other: Error): bool = self.index < other.index
proc `>`*(self: Error, other: Error): bool = self.index > other.index
proc `==`*(self: Error, other: Error): bool = self.index == other.index
proc `$`*(err: Error): string = err.message

proc new_tokenizer_error(index: int, message: string): Error =
  Error(index: index, message: message)

proc err_tokenizer_reached_eof*(index: int): Error =
  new_tokenizer_error(index, "tokenizer reached end of file")

proc err_tokenizer_expectation_mismatch*(index: int, expected: string,
    found: string): Error =
  new_tokenizer_error(index, fmt"expected `{expected}` found `{found}`")

proc err_tokenizer_unexpected_escape_sequence*(index: int,
    escape_seq: string): Error =
  new_tokenizer_error(index, fmt"unexpected string escape sequence encountered: `{escape_seq}`")

proc err_tokenizer_new_line_in_string*(index: int): Error =
  new_tokenizer_error(index, fmt"encountered new line character while parsing string literal")

proc err_tokenizer_max_length_exceeded*(index: int, kind: string,
    max_length: int): Error =
  new_tokenizer_error(index, fmt"{kind} literal exceeds maximum length of {max_length}")

proc err_tokenizer_tab_not_allowed*(index: int): Error =
  new_tokenizer_error(index, "tab characters are not allowed, use spaces for indentation")
