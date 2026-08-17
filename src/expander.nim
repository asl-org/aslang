import options

import analyzer

proc expand*(app: AnalyzedApp) =
  for file in app.files:
    echo file.path
    for module in file.modules:
      echo "\t" & module.name.asl
      if module.data.isSome:
        let data = module.data.get
        case data.kind:
        of adkLiteral:
          echo "\t\t" & "LITERAL"
        of adkStruct:
          echo "\t\t" & "STRUCT"
        of adkUnion:
          echo "\t\t" & "UNION"
    for generic in file.generics:
      echo "\t" & generic.name.asl