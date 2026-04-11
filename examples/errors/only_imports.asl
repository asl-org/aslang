# NEGATIVE TEST — file with only an import and no module/generic.
# Should fail rule #2 with "file must have at least one module
# or generic".
import { X } from "./dep.asl"
