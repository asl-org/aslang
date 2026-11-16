# NEGATIVE TEST — file with only an import and no module/generic.
# A file needs at least one module or generic, so the parser fails
# with "expected 'module' but reached end of token stream".
# The one error fixture without a `Driver` entry module, on purpose:
# adding one would give the file a module and remove what it tests.
import { X } from "./dep.asl"
