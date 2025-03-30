program                           ::= statement+
statement                         ::= initializer | function_call

initializer                       ::= datatype space+ identifier space* equal space* literal
function_call                     ::= identifier space* equal space* identifier space* argument_list
argument_list                     ::= open_parenthesis leading_argument* argument close_parenthesis
leading_argument                  ::= space* identifier space* comma
argument                          ::= space* identifier space*

datatype                          ::= leading_datatype* identifier
leading_datatype                  ::= identifier period

identifier                        ::= identifier_head identifier_tail*
identifier_head                   ::= alphabet | underscore
identifier_tail                   ::= alphanumeric | underscore

literal                           ::= string_literal | float_literal | integer_literal # Order matters here
integer_literal                   ::= digit+                # upto uin64
float_literal                     ::= digit+ period digit+  # upto float64
string_literal                    ::= double_quote escaped_string_content double_quote

escaped_string_content            ::= (escaped_double_quote | any_character_except_double_quote)*
escaped_double_quote              ::= backslash double_quote
any_character_except_double_quote ::= [^"]+                 # anything except double quote

alphanumeric                      ::= alphabet | digit
alphabet                          ::= lowercase_alphabet | uppercase_alphabet

lowercase_alphabet                ::= [a-z]
uppercase_alphabet                ::= [A-Z]
digit                             ::= [0-9]

space                             ::= ' '
equal                             ::= '='
underscore                        ::= '_'
period                            ::= '.'
double_quote                      ::= '"'
open_parenthesis                  ::= '('
close_parenthesis                 ::= ')'
backslash                         ::= '\'
