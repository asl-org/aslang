import unittest
import ../src/tokenizer/lexer
import ../src/tokenizer/token

suite "ASLang Lexer Tests":
  test "Tokenizes single-character operators":
    let source = "(){}[],.-+*/:="
    let lexer = new_lexer("test.asl", source)
    let tokens = lexer.scan_tokens()
    let expected_kinds = [
      LeftParen, RightParen, LeftBrace, RightBrace, LeftBracket, RightBracket,
      Comma, Dot, Minus, Plus, Star, Slash, Colon, Equal, Eof
    ]

    check(tokens.len == expected_kinds.len)
    for i, kind in expected_kinds:
      check(tokens[i].kind == kind)

  test "Tokenizes keywords and identifiers":
    let source = "module fn my_var struct"
    let lexer = new_lexer("test.asl", source)
    let tokens = lexer.scan_tokens()
    let expected_kinds = [Module, Fn, Identifier, Struct, Eof]

    check(tokens.len == expected_kinds.len)
    check(tokens[0].kind == Module)
    check(tokens[0].lexeme == "module")
    check(tokens[1].kind == Fn)
    check(tokens[1].lexeme == "fn")
    check(tokens[2].kind == Identifier)
    check(tokens[2].lexeme == "my_var")
    check(tokens[3].kind == Struct)
    check(tokens[3].lexeme == "struct")

  test "Tokenizes numbers: integers and floats":
    let source = "123 987.654 123."
    let lexer = new_lexer("test.asl", source)
    let tokens = lexer.scan_tokens()

    check(tokens.len == 5) # 123, 987.654, 123, ., EOF
    check(tokens[0].kind == Integer)
    check(tokens[0].lexeme == "123")
    check(tokens[1].kind == Float)
    check(tokens[1].lexeme == "987.654")
    check(tokens[2].kind == Integer)
    check(tokens[2].lexeme == "123")
    check(tokens[3].kind == Dot)
    check(tokens[3].lexeme == ".")

  test "Tokenizes strings":
    let source = "\"hello world\" \"\""
    let lexer = new_lexer("test.asl", source)
    let tokens = lexer.scan_tokens()

    check(tokens.len == 3)
    check(tokens[0].kind == String)
    check(tokens[0].lexeme == "\"hello world\"")
    check(tokens[1].kind == String)
    check(tokens[1].lexeme == "\"\"")

  test "Handles unterminated strings":
    let source = "\"this string never ends"
    let lexer = new_lexer("test.asl", source)
    let tokens = lexer.scan_tokens()

    check(tokens.len == 2)
    check(tokens[0].kind == Illegal)

  test "Tokenizes whitespace: indents and newlines":
    let source = "fn\n  match"
    let lexer = new_lexer("test.asl", source)
    let tokens = lexer.scan_tokens()
    let expected_kinds = [Fn, Newline, Indent, Match, Eof]

    check(tokens.len == expected_kinds.len)
    for i, kind in expected_kinds:
      check(tokens[i].kind == kind)

  test "Handles illegal characters":
    let source = "@ # %"
    let lexer = new_lexer("test.asl", source)
    let tokens = lexer.scan_tokens()

    check(tokens.len == 4) # @, #, %, EOF
    check(tokens[0].kind == Illegal)
    check(tokens[1].kind == Illegal)
    check(tokens[2].kind == Illegal)

  test "A complex example from problem 1":
    let source = """
module Solver:
  fn sum(a): a
"""
    let lexer = new_lexer("test.asl", source)
    let tokens = lexer.scan_tokens()
    let expected_kinds = [
      Module, Identifier, Colon, Newline,
      Indent, Fn, Identifier, LeftParen, Identifier, RightParen, Colon, Identifier, Newline,
      Eof
    ]

    check(tokens.len == expected_kinds.len)
    for i, kind in expected_kinds:
      check(tokens[i].kind == kind)
