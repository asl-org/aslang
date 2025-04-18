import os, results

import grammar
import parser
import transformer

when is_main_module:
  let maybe_parsed = rules.parse("example.asl".absolute_path, "program")
  if maybe_parsed.is_err:
    echo maybe_parsed.error
  else:
    echo $(maybe_parsed.get)
