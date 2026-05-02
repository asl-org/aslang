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
Parser ────── App           (raw AST + uniqueness/structural checks
  │                          enforced in constructors, BFS multi-file
  │                          resolution, topo-sorted leaves-first,
  │                          per-file typeIndex covering both imports
  │                          and defined types)
  ▼
Resolver ──── (WIP rewrite) Name/shape resolution only. For each
  │                          file, validates that every ArgumentType
  │                          inside data blocks and function
  │                          signatures refers to something in scope.
  │                          Function bodies are NOT resolved here —
  │                          that belongs to the Analyzer.
  ▼
(future)
  Analyzer  ── function-body resolution, overload resolution, generic
               constraint satisfaction (unification + substitution).
  Codegen   ── target emission (C or LLVM IR).
```

Orchestrated by `src/asl.nim`:
```nim
let app = ? parse(filepath, indentWidth, dumpTokens)
? resolve(app)
```

There is no separate `Validator` phase. Every uniqueness / structural
rule the validator used to enforce (duplicate names, empty blocks,
import collisions, duplicate fields/variants) is now a precondition
inside an AST constructor (`newStruct`, `newUnion`, `newModule`,
`newFile`, etc.). Invalid AST nodes cannot be constructed, so no
separate validation pass is needed.

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

### Phase 3: Parser-level indexing (absorbed)

The parser itself performs the uniqueness / structural checks that
used to live in a separate validator. The lookup indices it builds
during construction double as the validation mechanism (`Table`
insertion fails on duplicate key).

Indices on AST nodes:
- `File.typeIndex` — `Identifier -> int` covering **both** imported
  types and defined types (modules + generics) in one namespace.
- `Module.functionIndex` / `Generic.funcDefIndex` — allow function
  overloading by keying on `seq[int]`.
- `Struct.fieldIndex`, `Union.variantIndex`, `VariantDefinition.fieldIndex`,
  `ArgumentDefinitionList.argDefIndex` — per-block duplicate detection.
- `App.fileIndex` — absolute path → file index.

Every `Type` in a file (imported or defined) is wrapped in a common
`Type` umbrella (`tkImported | tkDefined`) so a single `typeIndex`
lookup serves the resolver.

### Phase 4: Resolution (WIP)

`src/resolver.nim`

Returns a `ResolvedApp` containing a `ResolvedFile` per source file,
which in turn holds resolved imports plus a `ResolvedDefinedType` for
each module/generic. As of 2026-05-02 27/35 fixtures resolve clean —
`base.asl`, `problem001`–`problem010`, and `sample.asl` all green.
Remaining failures are fixture-maintenance (`multi_import_same_path`
plus six stale fixtures missing base.asl imports) and one non-public
`Sample` module. Open resolver stubs cluster around decorators and
the generic-context `resolveModuleArgumentType` for explicit
`requires(...)` / `dbkStruct`. Scope:

- **Two-pass walk per file** (files come topo-sorted leaves-first
  from the loader, so imports are always resolved before use).
  - Pass A (declare): register every defined-type name and every
    imported-binding into a `FileScope` as `ResolvedRef`s (file id
    + module/generic kind + index within file).
  - Pass B (define): for each module, resolve its `requires(...)`
    clause (if any, declaring explicit type parameters), its data
    block (struct/union/literal), and each function signature. For
    each generic, resolve each function signature. Every
    `ArgumentType` root must look up in the scope; impls resolve
    recursively. When a module has no explicit `requires` but its
    struct/union fields reference a generic, that generic is treated
    as an inferred type parameter at use sites.
- **Generic signature rule** — inside a generic block, a fn
  argument/return type root may only resolve to the current generic
  itself (self-reference) or a module. Other generics are rejected
  at resolve time, keeping each generic's type world bounded.
- **Body-level name resolution** — the resolver also walks user-
  function bodies: each statement is dispatched, each expression is
  resolved, and every function call is matched against candidate
  function definitions by `(name, arity)` against the target type.
  A `FunctionScope` (HashSet[Identifier]) tracks the names of
  variables currently in scope; the type of each variable is the
  Analyzer's concern. The resolver collects candidate overloads but
  does not pick the unique one — that's the Analyzer.
- **Not the resolver's job**: overload selection (picking the unique
  candidate after matching arg types), generic constraint
  satisfaction (does an impl actually implement the generic), and
  type-correctness checks. Those belong to the Analyzer phase.
- **No structural-size check** — all struct values are pointer-backed
  at runtime, so mutual struct containment does not create infinite
  types. Name cycles are the only cycles, and Pass A dissolves them.

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
`Initializer`, `CasePattern`, `Function`, `DefinedType`, `Type` all
use `case kind:` discriminators with exhaustive matching.

**Uniqueness via indexed construction** — the parser builds
`Table[Identifier, int]` lookup tables inside every constructor that
takes a list of named children (fields, variants, function args,
file-level types, ...). Duplicate insertion errors immediately, so
the same index that speeds up downstream lookups also enforces
uniqueness. No separate validation pass.

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

**Finish the Resolver rewrite** (`src/resolver.nim`) — narrow scope:
two-pass walk per file, name and shape resolution only, enforce the
generic-signature rule. No function-body work, no constraint
satisfaction, no resolved type tree returned yet (produced later when
an Analyzer consumer exists).

**Build the Analyzer** — new phase after the Resolver. The resolver
already does body-level name resolution and collects candidate
overloads by (name, arity); the Analyzer takes those candidates and:
- Performs overload selection: unify each candidate's parameter
  types with the call site's argument types and pick the unique
  survivor (reject on ambiguity for v1).
- Generic constraint satisfaction: after unification binds a type
  parameter (e.g., `Any := u8`), verify the bound type implements
  every function signature the generic requires. Cache results.
- Literal type inference: pin down `5` to `u8` / `u32` / etc. from
  the expected parameter type at the call site.
- Type-correctness checks across statements (assignment compatibility,
  match exhaustiveness, etc.).

After analysis:
- **IR generation** — lower the analyzed AST into an intermediate
  representation suitable for optimization and code generation.
- **Code generation** — emit target code (likely C or LLVM IR).
