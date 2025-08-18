import unittest
import ../src/tokenizer/lexer
import ../src/tokenizer/token

suite "ASLang Lexer Tests":
  test "Tokenizes single-character operators":
    let source = "(){}[],.-+*/:="
    let lexer = new_lexer("test.asl", source)
    let tokens = lexer.scan_tokens()
    let expected_kinds = [
      tkLeftParen, tkRightParen, tkLeftBrace, tkRightBrace, tkLeftBracket, tkRightBracket,
      tkComma, tkDot, tkMinus, tkPlus, tkStar, tkSlash, tkColon, tkEqual, tkEof
    ]

    check(tokens.len == expected_kinds.len)
    for i, kind in expected_kinds:
      check(tokens[i].kind == kind)

  test "Tokenizes keywords and identifiers":
    let source = "module fn my_var struct"
    let lexer = new_lexer("test.asl", source)
    let tokens = lexer.scan_tokens()
    let expected_kinds = [tkModule, tkFn, tkIdentifier, tkStruct, tkEof]

    check(tokens.len == expected_kinds.len)
    check(tokens[0].kind == tkModule)
    check(tokens[0].lexeme == "module")
    check(tokens[1].kind == tkFn)
    check(tokens[1].lexeme == "fn")
    check(tokens[2].kind == tkIdentifier)
    check(tokens[2].lexeme == "my_var")
    check(tokens[3].kind == tkStruct)
    check(tokens[3].lexeme == "struct")

  test "Tokenizes numbers: integers and floats":
    let source = "123 987.654 123."
    let lexer = new_lexer("test.asl", source)
    let tokens = lexer.scan_tokens()

    check(tokens.len == 5) # 123, 987.654, 123, ., EOF
    check(tokens[0].kind == tkInteger)
    check(tokens[0].lexeme == "123")
    check(tokens[1].kind == tkFloat)
    check(tokens[1].lexeme == "987.654")
    check(tokens[2].kind == tkInteger)
    check(tokens[2].lexeme == "123")
    check(tokens[3].kind == tkDot)
    check(tokens[3].lexeme == ".")

  test "Tokenizes strings":
    let source = "\"hello world\" \"\""
    let lexer = new_lexer("test.asl", source)
    let tokens = lexer.scan_tokens()

    check(tokens.len == 3)
    check(tokens[0].kind == tkString)
    check(tokens[0].lexeme == "\"hello world\"")
    check(tokens[1].kind == tkString)
    check(tokens[1].lexeme == "\"\"")

  test "Handles unterminated strings":
    let source = "\"this string never ends"
    let lexer = new_lexer("test.asl", source)
    let tokens = lexer.scan_tokens()

    check(tokens.len == 2)
    check(tokens[0].kind == tkIllegal)

  test "Tokenizes whitespace: indents and newlines":
    let source = "fn\n  match"
    let lexer = new_lexer("test.asl", source)
    let tokens = lexer.scan_tokens()
    let expected_kinds = [tkFn, tkNewline, tkIndent, tkMatch, tkEof]

    check(tokens.len == expected_kinds.len)
    for i, kind in expected_kinds:
      check(tokens[i].kind == kind)

  test "Handles illegal characters":
    let source = "@ # %"
    let lexer = new_lexer("test.asl", source)
    let tokens = lexer.scan_tokens()

    check(tokens.len == 4) # @, #, %, EOF
    check(tokens[0].kind == tkIllegal)
    check(tokens[1].kind == tkIllegal)
    check(tokens[2].kind == tkIllegal)

  test "A complex example from problem 1":
    let source = """
module Solver:
  fn sum(a): a
"""
    let lexer = new_lexer("test.asl", source)
    let tokens = lexer.scan_tokens()
    let expected_kinds = [
      tkModule, tkIdentifier, tkColon, tkNewline,
      tkIndent, tkFn, tkIdentifier, tkLeftParen, tkIdentifier, tkRightParen, tkColon, tkIdentifier, tkNewline,
      tkEof
    ]

    check(tokens.len == expected_kinds.len)
    for i, kind in expected_kinds:
      check(tokens[i].kind == kind)
