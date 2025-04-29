from rules/symbol import symbol_rules
from rules/word import word_rules
from rules/numeric_literal import numeric_literal_rules
from rules/string_literal import string_literal_rules
from rules/separator import separator_rules
from rules/identifier import identifier_rules
from rules/native_argument import native_argument_rules
from rules/literal import literal_rules
from rules/initializer import initializer_rules
from rules/function_call import function_call_rules
from rules/statement import statement_rules
from rules/macro_header import macro_header_rules
from rules/line import line_rules
from rules/program import program_rules

var rules* = symbol_rules & word_rules & numeric_literal_rules &
    string_literal_rules & separator_rules & identifier_rules &
    native_argument_rules & literal_rules & initializer_rules &
    function_call_rules & statement_rules & macro_header_rules & line_rules & program_rules
