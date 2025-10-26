import results, strformat

import tokenizer/tokens
export tokens

const MAX_DIGITS_LENGTH = 256
const MAX_STRING_LENGTH = 1 shl 16

proc tokenize*(filename: string, content: string): Result[seq[Token], string] =
  var index = 0
  var location = new_location(filename)
  var tokens: seq[Token]

  while index < content.len:
    case content[index]:
    of '+':
      let token = new_token(TK_PLUS, $content[index], location)
      index += 1
      location = location.update(token.value)
      tokens.add(token)
    of '-':
      let token = new_token(TK_MINUS, $content[index], location)
      index += 1
      location = location.update(token.value)
      tokens.add(token)
    of ',':
      let token = new_token(TK_COMMA, $content[index], location)
      index += 1
      location = location.update(token.value)
      tokens.add(token)
    of '.':
      let token = new_token(TK_DOT, $content[index], location)
      index += 1
      location = location.update(token.value)
      tokens.add(token)
    of ':':
      let token = new_token(TK_COLON, $content[index], location)
      index += 1
      location = location.update(token.value)
      tokens.add(token)
    of '=':
      let token = new_token(TK_EQUAL, $content[index], location)
      index += 1
      location = location.update(token.value)
      tokens.add(token)
    of '\\':
      let token = new_token(TK_BACK_SLASH, $content[index], location)
      index += 1
      location = location.update(token.value)
      tokens.add(token)
    of '(':
      let token = new_token(TK_OPEN_PAREN, $content[index], location)
      index += 1
      location = location.update(token.value)
      tokens.add(token)
    of ')':
      let token = new_token(TK_CLOSE_PAREN, $content[index], location)
      index += 1
      location = location.update(token.value)
      tokens.add(token)
    of '{':
      let token = new_token(TK_OPEN_CURLY, $content[index], location)
      index += 1
      location = location.update(token.value)
      tokens.add(token)
    of '}':
      let token = new_token(TK_CLOSE_CURLY, $content[index], location)
      index += 1
      location = location.update(token.value)
      tokens.add(token)
    of '[':
      let token = new_token(TK_OPEN_SQUARE, $content[index], location)
      index += 1
      location = location.update(token.value)
      tokens.add(token)
    of ']':
      let token = new_token(TK_CLOSE_SQUARE, $content[index], location)
      index += 1
      location = location.update(token.value)
      tokens.add(token)
    of ' ':
      let token = new_token(TK_SPACE, $content[index], location)
      index += 1
      location = location.update(token.value)
      tokens.add(token)
    of '\n':
      let token = new_token(TK_NEW_LINE, $content[index], location)
      index += 1
      location = location.update(token.value)
      tokens.add(token)
    of '"':
      let start = index

      index += 1 # move past double quote

      # NOTE: this check is needed because in case it is not present while loop
      # will be skipped entirely resulting into an invalid string token.
      if index == content.len:
        return err(fmt"{location} [TE101] failed to parse malformed string literal")

      while index < content.len:
        if content[index] == '"':
          if index > 0 and content[index - 1] == '\\':
            index += 1
          else:
            break
        else:
          index += 1

        if index > start + MAX_STRING_LENGTH:
          return err(fmt"{location} [TE102] string literal exceeded maximum supported length of {MAX_STRING_LENGTH}")

      index += 1 # move past double quote again

      let token = new_token(TK_STRING, content.substr(start, index - 1), location)
      tokens.add(token)
    of '#':
      let start = index
      # consume everything up until newline
      while index < content.len and content[index] != '\n': index += 1
      let token = new_token(TK_COMMENT, content.substr(start, index - 1), location)
      location = location.update(token.value)
      tokens.add(token)
    of '0'..'9':
      let start = index
      while index < content.len and content[index] in '0'..'9':
        index += 1
        if index > start + MAX_DIGITS_LENGTH:
          return err(fmt"{location} [TE103] integer literal exceeded maximum supported length of {MAX_DIGITS_LENGTH}")
      let token = new_token(TK_DIGITS, content.substr(start, index - 1), location)
      location = location.update(token.value)
      tokens.add(token)
    of 'a'..'z', 'A'..'Z':
      let start = index
      while index < content.len and ((content[index] in 'a'..'z') or (content[
          index] in 'A'..'Z')):
        index += 1
      let token = new_token(TK_ALPHABETS, content.substr(start, index - 1), location)
      location = location.update(token.value)
      tokens.add(token)
    of '_':
      let token = new_token(TK_UNDERSCORE, $content[index], location)
      index += 1
      location = location.update(token.value)
      tokens.add(token)
    else:
      return err(fmt"[TE104] {location} Unexpected character `{content[index]}` encountered")

  # NOTE: Adding NEW_LINE Token to indicate end of token stream
  tokens.add(new_token(TK_NEW_LINE, "\n", location))

  ok(tokens)
