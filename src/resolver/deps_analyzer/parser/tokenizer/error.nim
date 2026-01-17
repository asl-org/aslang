import strformat

type TokenizerError* = ref object of RootObj
  index: int
  message: string

proc `<`*(self: TokenizerError, other: TokenizerError): bool = self.index < other.index
proc `>`*(self: TokenizerError, other: TokenizerError): bool = self.index > other.index
proc `==`*(self: TokenizerError, other: TokenizerError): bool = self.index == other.index
proc `$`*(err: TokenizerError): string = err.message

proc new_tokenizer_error(index: int, message: string): TokenizerError =
  TokenizerError(index: index, message: message)

proc err_tokenizer_reached_eof*(index: int): TokenizerError =
  new_tokenizer_error(index, "tokenizer reached end of file")

proc err_tokenizer_expectation_mismatch*(index: int, expected: string,
    found: string): TokenizerError =
  new_tokenizer_error(index, fmt"expected `{expected}` found `{found}`")

proc err_tokenizer_unexpected_escape_sequence*(index: int,
    escape_seq: string): TokenizerError =
  new_tokenizer_error(index, fmt"unexpected string escape sequence encountered: `{escape_seq}`")

proc err_tokenizer_new_line_in_string*(index: int): TokenizerError =
  new_tokenizer_error(index, fmt"encountered new line character while parsing string literal")
