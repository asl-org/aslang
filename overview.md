# ASL Compiler Overview

## What is ASL?

ASL (a Software Language) is a statically-typed systems programming
language for mission-critical software. The syntax is
indentation-based with modules as the primary unit of organization.

```asl
import { User } from "./user.asl"

generic Eq:
  func eq(a: Eq, b: Eq): u8

public module App:
  struct:
    name: String
    age: u32

  public func start(sys: System): u8
    user = User { name: "Alice", age: 30 }
    result = match user.age:
      case 0:
        System.println("newborn")
      case other:
        System.println("older")
    u8 0
```

### Language Features

- **Modules**: top-level blocks containing an optional data block
  (struct or union) and functions
- **Structs**: product types with named fields (`struct: name: String`)
- **Unions**: sum types with named variants, each optionally carrying
  fields (`union: Free { usage: u32 }; Pro { credits: u32 }`)
- **Functions**: typed, overloadable by parameter signature. Method
  call syntax via `Type.method(args)`. Two kinds: user functions
  (with a body) and extern functions (`@extern("symbol")` linking
  to an external implementation)
- **Generics**: type-parameterized function signature blocks
  (`generic Eq: func eq(a: Eq, b: Eq): u8`)
- **Pattern matching**: `match` expressions with integer literals,
  variable bindings, and variant destructuring
  (`case Pro { credits: c }: ...`)
- **Imports**: cross-file module/generic imports with aliasing
  (`import { User as U } from "./user.asl"`)
- **Visibility**: `public` keyword on modules and functions to
  mark them as exported
- **Comments**: line comments starting with `#`

### Built-in Types

Fixed-width integers: `i8`, `i16`, `i32`, `i64`, `u8`, `u16`,
`u32`, `u64`. Floats: `f32`, `f64`. Pointer: `ptr`. Containers:
`String`, `List`, `Map`, `Array`, `Status`. System interface:
`System`.

## Compiler Pipeline

```
Source text
  │
  ▼
Tokenizer ─── seq[Token]
  │
  ▼
Parser ────── seq[File]     (raw AST, BFS multi-file, topo-sorted)
  │
  ▼
Validator ─── App           (Indexed* wrappers with Table indices)
  │
  ▼
Resolver ──── ResolvedApp   (Resolved* wrappers with integer IDs
  │                          and resolved type references)
  ▼
(future: type checker, codegen)
```

Orchestrated by `src/asl.nim`:
```nim
let app = ? parse(filepath, indentWidth, dumpTokens)
? resolve(app)
```

### Phase 1: Tokenization

`src/tokenizer/tokenizer.nim`

Single-character classifier. Intentionally simple — no keywords, no
multi-character tokens. All that complexity lives in the parser.
Produces `seq[Token]` where each token carries `kind` (punctuation,
space, newline, alphabet, digit, utf8), `value` (the character), and
`Location` (line:col).

Security: validates UTF-8 encoding and rejects bidirectional control
codepoints, zero-width characters, and invisible Unicode (Trojan
Source defense).

### Phase 2: Parsing

`src/parser/{ast, combinators, grammar, loader}.nim`

Recursive descent via composable `Spec[T]` combinators:

- `oneOf` — ordered alternatives with backtracking
- `any` / `atLeastOne` — repetition (zero-or-more / one-or-more)
- `optional` — zero-or-one
- `separatedBy` — comma-separated lists
- `contained` — delimited containers (`(...)`, `[...]`, `{...}`)
- `map` — transform parse result
- `blockSpec` / `decoratedBlockSpec` — indented blocks with headers

Backtracking via checkpoint/restore on `parser.index`. Fatal errors
in block bodies bypass backtracking for precise diagnostics.
Forward-declared specs enable mutual recursion
(`expressionSpec ↔ argumentListSpec`).

**Multi-file resolution** (`loader.nim`): BFS traversal of imports,
tokenize + parse each dependency, topological sort via DFS with
cycle detection. Parent-directory escape prevention
(`./sub/../../escape` caught by normalizing the resolved path).

### Phase 3: Validation & Indexing

`src/validator/{indexed, indexer}.nim`

Wraps each raw AST node in an `Indexed*` type carrying
`Table[string, int]` lookup indices. Building the index enforces
uniqueness for free — duplicate names error during insertion.

Rules enforced:
- Modules, generics, and imported names share one file-level
  namespace — no duplicates
- Files must contain at least one module or generic
- Modules must have a data block or at least one function
- No duplicate field names in structs or variants
- No duplicate variant names in unions
- Functions allow overloading (`Table[string, seq[int]]`)

### Phase 4: Resolution (WIP)

`src/resolver.nim`

Resolves names and types across the parsed AST. Builds a
`FileScope` per file with a native type registry, then resolves
each module's data blocks, function definitions (argument types
and return types), and function bodies (expressions, statements).

- **ResolvedType**: tagged union — `rtkNative` (built-in),
  `rtkModule` (file + module index), `rtkGeneric` (file + generic
  index)
- **ResolvedArgumentType**: resolved root type + recursively
  resolved impl type parameters
- **FunctionScope**: tracks function parameter bindings by name
  for variable resolution in expressions

Currently WIP — literal, variable, and function call expression
resolution are partially implemented; match, getter, initializer
are stubbed. Dispatches on `fkUser` / `fkExtern` function kinds.

Function bodies (`StatementList`) remain raw — expression-level
resolution requires type inference (Phase 3, not yet started).

## Project Structure

```
src/
  asl.nim                          entry point
  cli.nim                          CLI parsing via argparse
  utils.nim                        topological sort + cycle detection
  nim.cfg                          per-component module search paths
  resolver.nim                     WIP name/type resolution

  tokenizer/
    tokenizer.nim                  token types + tokenize()

  parser/
    parser.nim                     re-exports ast + loader
    ast.nim                        AST types + constructors + accessors + asl()
    combinators.nim                Spec[T] + combinator procs
    grammar.nim                    grammar specs + single-file parse
    loader.nim                     BFS multi-file resolution + parse*()

examples/
  base.asl                         standard library definition (extern functions)
  *.asl                            positive test fixtures
  errors/*.asl                     negative test fixtures (each documented)

test.sh                            regression runner (exit-code based)
bugs.md                            issue tracker (open + resolved)
lessons.md                         design retrospective
overview.md                        this file
```

Cross-component imports use bare names (`import tokenizer`,
`import parser`). `nim.cfg` adds each component directory to the
Nim compiler's module search path. No `../` parent imports anywhere.

## Design Patterns

**Result[T, E] error handling** — all fallible operations return
`Result`. Chained with `?` for early return. Error messages carry
`file:line:col`. The `[ERROR] -` prefix is added only at the
display boundary (`asl.nim`), not in library code.

**Private fields + readonly accessors** — types are `ref object`
with unexported fields. Public accessor procs (`proc name*(m): T`)
provide readonly access. Variant-field accessors assert the kind
before returning (`assert db.kind == dbkStruct`).

**Tagged unions** — `Expression`, `Statement`, `DataBlock`,
`Initializer`, `CasePattern`, `ResolvedArgumentType`,
`ResolvedData` all use `case kind:` discriminators with exhaustive
matching.

**Parallel wrapper types per phase** — raw AST → `Indexed*` →
`Resolved*`. Each layer adds information without mutating the
previous. Keeps phase concerns separated (parsing doesn't know
about indexing; indexing doesn't resolve types).

**Reverse construction** — compute children first into local vars,
then construct the parent once at the end via a `newX()` factory.
No mutation after construction.

**Identifier everywhere** — every name-bearing field in the AST
stores an `Identifier` (value + Location) rather than a bare
string, so error messages always have exact source positions.

## Testing

`./test.sh` — builds the project then runs every example:

- **Positive** (`examples/*.asl`): must exit 0
- **Negative** (`examples/errors/*.asl`): must exit non-zero

Each fixture has a leading `#` comment documenting what feature or
error condition it exercises. 35 tests total. Exit-code based —
no output pattern matching.

## What's Next

**PSR-41 Phase 3: Function body / expression resolution** — the
only major open item. Requires resolving `Assignment.target`,
`Expression.variable`, `Getter.source/property`, `FunctionCall`,
pattern bindings, and union initializers inside function bodies.
This crosses into type inference territory: `Getter.property` needs
the source expression's type, `VariantPattern.variantName` needs
the match subject's type, overload resolution needs argument types.
Effectively a compact type checker.

After resolution, the next major phases would be:
- **Type checking** — validate that resolved references are
  type-compatible (assignment types match, function call arguments
  match parameter types, match patterns cover the subject type)
- **IR generation** — lower the resolved AST into an intermediate
  representation suitable for optimization and code generation
- **Code generation** — emit target code (likely C or LLVM IR)
