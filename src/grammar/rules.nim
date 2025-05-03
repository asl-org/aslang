from rules/base import base_rules
from rules/symbol import symbol_rules
from rules/identifier import identifier_rules
from rules/argument import argument_rules
from rules/literal import literal_rules
from rules/statement import statement_rules
from rules/macro_header import macro_header_rules
from rules/line import line_rules
from rules/program import program_rules

var rules* = base_rules & symbol_rules & identifier_rules &
    argument_rules & literal_rules & statement_rules & macro_header_rules &
        line_rules & program_rules
