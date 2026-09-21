# ASL — Syntactic and Semantic Validations

Catalog of every validation the compiler enforces, sourced by reading
the unit + integration test suites (`tests/test_*.nim`). Each rule
below has at least one test that asserts the rejection or acceptance.
Grouped by pipeline phase — lexer, parser (AST constructors + grammar
specs), loader, resolver, analyzer, CLI. Each entry names the test
file that pins the rule down.

Coverage as of this document: **289 unit tests + 33/35 integration
fixtures.** The two failing fixtures are a pre-existing analyzer TODO
(the equality-vs-unification gap) documented in
`overview.md`'s "What's Next".

---

## 1. Lexical validations (tokenizer)

Source: `tests/test_tokenizer.nim`.

### 1.1 Token structure

- The token stream **always ends in a synthetic `tkNewline`**, even
  for empty input or input already ending in a newline (the trailing
  synthetic is a separate token from any trailing literal newlines).
- The tokenizer emits whole lexemes. The two run-batched
  ("collective") kinds are `tkSpace` and `tkNewline`; the whole-lexeme
  kinds (`tkIdentifier`, `tkInteger`, `tkFloat`, `tkString`,
  `tkComment`) are matched greedily into one token. In each case the
  whole run/lexeme lives in `.value`. Concretely:
  - `tkSpace` — four spaces → one token, `.value.len == 4`. The
    parser's `indentationSpec` relies on this count for level
    checks.
  - `tkNewline` — three literal newlines → one token,
    `.value.len == 3`. Blank-line grammar rules count runs off this.
  - `tkIdentifier` — `"abc"` → one token, `.value == "abc"` (an
    identifier is `[_A-Za-z][_A-Za-z0-9]*`).
  - `tkInteger` — `"0123456789"` → one token,
    `.value == "0123456789"`.
  - `tkFloat` — a numeric float, or a special value `nan` / `inf` /
    `+inf` / `-inf`, is one token.
- **Runs of different kinds do NOT merge.** `"  \n\n"` yields
  `tkSpace("  ")` then `tkNewline("\n\n")` then the trailing synthetic
  newline — batching is per-kind, not cross-kind.
- Each defined punctuation character (`!@,()=[]{}:.`) produces exactly
  one `tkPunctuation` token — punctuation is individual, never
  collective. `+` and `-` are NOT punctuation: a sign is consumed as
  part of a number (`-5`) or an inf literal (`-inf`), and a lone sign
  followed by neither digits nor `inf` is an unsupported token.

### 1.2 Trojan Source defense

The tokenizer rejects source containing any of the following
Unicode codepoints — they are the invisible-manipulation classes
Trojan Source attacks exploit.

- **Bidirectional overrides** — `U+202E` (right-to-left override) and
  every entry in the compiler's `BidiCodepoints` sweep:
  `U+200E`, `U+200F`, `U+202A–U+202E`, `U+2066–U+2069`.
- **Zero-width codepoints** — `U+200B` (zero-width space), `U+FEFF`
  (BOM), and every entry in `ZeroWidthCodepoints`: `U+200B`, `U+200C`,
  `U+200D`, `U+FEFF`.
- **Invisible codepoints** — `U+00AD` (soft hyphen) and every entry in
  `InvisibleCodepoints`: soft hyphen, combining grapheme joiner,
  Arabic letter mark, Hangul choseong/jungseong fillers, Khmer inherent
  vowels, word joiner, invisible math operators, deprecated formatting
  characters (`U+2060–U+206F`).

The compiler's `InvisibleCodepoints` array is swept exhaustively by
one test — every entry must reject.

### 1.3 Whitespace validation

Only these whitespace characters are permitted: `space` (`0x20`) and
`newline` (`\n`). Every other whitespace-adjacent codepoint is rejected
with an "unsupported token" error:

- `TAB` (`\t`)
- Carriage return (`\r`)
- Vertical tab (`\x0B`)
- Form feed (`\x0C`)
- NUL byte (`\x00`)

### 1.4 UTF-8

Identifiers and numbers are ASCII-only. A bare multi-byte UTF-8 rune
outside a string or comment (e.g. Hiragana `あ` = `U+3042`) is an
"unsupported token" error — there is no `tkUtf8` kind. Non-ASCII text
is valid only inside a string literal or a comment, where it is still
swept for the Trojan-Source / invisible-codepoint classes above.

### 1.5 Error location

Tokenizer errors always include the source file path in the
diagnostic message.

---

## 2. Identifier invariants (AST)

Source: `tests/test_ast.nim`.

- **Length ≤ 256 characters.** A 256-char identifier is accepted; 257
  is rejected with `max length 256` in the error message.
- **Reserved `__asl` prefix.** Any identifier that starts with `__asl`
  is rejected — including the bare literal `__asl` and any longer
  suffix like `__aslSecret`. `__as` (one character short of `__asl`)
  is accepted.
- **Equality is text-based.** Two identifiers are equal iff their
  textual value is equal.
- **Hash is text-based.** `id.hash == id.value.hash`; equal identifiers
  hash identically.

---

## 3. AST constructor invariants (parser)

Source: `tests/test_ast.nim`. These are the "cannot construct" rules
that the `newXxx` factories enforce — the type system prevents an
invalid AST value from ever existing.

### 3.1 `StructDef`

- Rejects an **empty field list** — a struct with zero fields is
  meaningless.
- Rejects **duplicate field names** within the same struct.

### 3.2 `VariantDef` (union arm)

- Rejects **duplicate field names within a variant.**
- **Accepts an empty field list** — variants can have zero fields
  (the tag itself is the information). This is the deliberate
  asymmetry with `StructDef`.

### 3.3 `UnionDef`

- Rejects **duplicate variant names** within the same union.

### 3.4 `ArgumentDefList`

- Rejects **duplicate argument names** within a single parameter list.
- **Accepts an empty list** (zero-argument functions are legal).

### 3.5 `UnionPattern`

- Rejects **duplicate field names** in a single pattern (`case Ok
  { value: a, value: b }`).
- Rejects **duplicate binding names** across fields (`case Ok
  { value: x, error: x }`).
- **Accepts an empty fields list** (`case Ok`).

### 3.6 `Import`

- Rejects **duplicate names within a single `import { ... } from`
  statement.**
- Rejects **alias collisions** — two imports aliased to the same
  binding name (`{ Foo as B, Bar as B }`).
- Rejects **an original name colliding with another entry's alias**
  (`{ Foo, Bar as Foo }`).

### 3.7 `KeywordArgumentList`

- Rejects **duplicate kwarg names.**
- **Accepts an empty list.** Emptiness is a per-initializer concern,
  not a list-level one. `StructInitializer`'s "no empty structs" rule
  falls out of `newStructDef` (≥ 1 field guaranteed by construction)
  plus the resolver's `kwargs.len != fields.len` count check.
  `UnionInitializer` needs empty to be legal so `Variant {}` works
  against a zero-field variant.

### 3.8 `Module`

- Rejects a module with **neither a data block nor any functions.**
- **Accepts** a module with only a data block (e.g. an aslr literal
  type) or only functions.

### 3.9 `File` (per parsed source file)

- Rejects **duplicate module names** within a single file.
- Rejects **file with only imports and no defined types** — a file
  must contribute something to the type table.
- Rejects **a local module whose name collides with an imported
  binding.** Detected at `newAslFile` construction time (the parser's
  cross-index duplicate check across `typeIndex` and
  `importedNameIndex`).

---

## 4. Grammar-level validations (parser specs)

Source: `tests/test_grammar.nim` and `tests/test_ast.nim`.

### 4.1 File-kind rules

- **`.aslr` files reject `import` lines** — `aslrFileSpec` parses only
  modules and generics; a leading `import` line fails the parse.
- **`@extern` functions are allowed in both file kinds** — an earlier
  rule rejected externs in `.asl` files; that restriction was removed,
  so `.asl` and `.aslr` modules may both declare `@extern` functions.

### 4.2 File shape

- **File must contain at least one module or generic.** A file
  consisting only of blank lines and comments is rejected.
- **Blank lines and `# ...` comments between top-level items are
  tolerated** anywhere the grammar allows a break.

### 4.3 Import syntax

- **Duplicate names within one `import { ... }` are rejected** at
  parse time (via the `newImport` constructor).
- **Alias-binding collisions** (`{ Foo as B, Bar as B }`) rejected.

### 4.4 Publicness

- `public` may prefix `module`, `func`, and `generic` declarations
  (each parsed via `presence(keywordSpec("public"))`).
- Absence of `public` = private (default).
- **All function definitions inside a `generic` block are implicitly
  public** — generics are interface types, so their signatures are
  always callable across module boundaries. This is a documentation
  rule; no test enforces it because grammar has no way to *deny*
  privacy.

### 4.5 Function overloading

- **Overloading by parameter arity is allowed** in one module — two
  `func go` with different argument counts coexist.

### 4.6 Variant definitions require braces

- **`Timeout` alone (no braces) is rejected.** Every variant
  declaration inside a `union:` block must carry `{...}`. Zero-field
  variants must be written `Timeout { }`. This mirrors the
  case-pattern side (`case Timeout { }:`) — braces on the definition
  match braces on the pattern, so `case Timeout:` (bare) is
  unambiguous as a variable binding rather than a variant match.
  Locked in by `bare-identifier variant definition is rejected`
  (test_grammar.nim) and `variant definition with empty braces
  parses`.

### 4.7 Decorators

- **`@extern("symbol")` is the only decorator with defined semantics.**
  Other decorator names parse but currently produce a "todo: resolve
  decorators" error at the resolver.

### 4.8 Argument-type shorthand — `T!` = `Status[T, Error]`

A `!` on an argument type is sugar for the two-parameter
`Status[Value, Error]` (the value type and the error type). `Value!Error`
sets both; `Value!` defaults the error to the built-in `Error`. Parsed
once at `argumentTypeSpec`, so every argument-type position — function
args, return types, kwarg field types, initializer type prefixes —
picks it up uniformly.

- **Binding is tight.** `!` attaches to the type it immediately
  follows:
  - `u8!` → `Status[u8, Error]`
  - `u8!MyError` → `Status[u8, MyError]`
  - `Array[u32]!` → `Status[Array[u32], Error]`
  - `Array[u32!]` → `Array[Status[u32, Error]]`
  - `Status[u32]!` → `Status[Status[u32], Error]` (syntactically legal)
- **AST is unchanged.** The sugar collapses at parse time. Downstream
  (resolver, analyzer) sees a plain `Status[...]` ArgumentType — no
  distinct variant.
- **Downstream constraint checks still fire.** Whatever satisfiability
  rules apply to `Status[T, E]` (Ok's value being `Any`-compatible,
  the error being `Failure`-compatible) apply identically to `T!`. The
  sugar does not relax type-system invariants.

Locked in by `grammar — argument type shorthand` (test_grammar.nim,
6 tests) and `analyzer — argument type shorthand end-to-end`
(test_analyzer.nim, 3 tests).

### 4.9 Kwarg + union-pattern shorthand

Sugar at the parser layer for the "field and same-named local share a
name" idiom.

- **Initializer kwarg shorthand.** `Struct { x }` desugars to
  `Struct { x: x }`; missing `: expression` is synthesized as a bare
  Variable of the same name at the same source location. Applies
  uniformly to struct and union initializers, and can be mixed with
  explicit kwargs (`Struct { a, b: u8 5 }`).
- **Union-pattern field-binding shorthand.** `case Ok { value }`
  desugars to `case Ok { value: value }`; missing `: binding` is
  synthesized as an Identifier binding of the same name.
- **AST is unchanged** — both surfaces collapse into the same
  `KeywordArgument` / `UnionPatternField` shape the resolver and
  analyzer have always seen. Duplicate-field detection (§3.7 and
  `UnionPattern`'s per-name check) and every downstream rule work
  transparently. Locked in by `grammar — kwarg + pattern shorthand`
  (test_grammar.nim, 5 tests) and `analyzer — kwarg + pattern
  shorthand end-to-end` (test_analyzer.nim, 3 tests).

### 4.10 A-normal form expansion (post-parse AST normalization)

Not a validation — a *transformation* that normalizes nested calls into
A-normal form. The `expand*` procs live in `src/parser/statement.nim`.

Status: currently NOT wired into parsing — `statementListConsumer`
(`src/parser/index.nim`) builds the `StatementList` without expanding,
and the `expand*` procs are kept as reference pending a post-analysis
expander (see `plans/plan_post_analysis_expansion.md`). When re-enabled,
expansion runs after the AST is built so downstream (resolver,
analyzer) sees only the normalized form.

**Invariants the transformation establishes:**

- **Every value-position expression is a `Variable` or `Literal`.**
  Function-call arguments, keyword-argument values, and match subjects
  can never carry a nested `FunctionCall` / `Initializer` / `Getter` /
  `MatchExpression`. Those get lifted into preceding synthetic
  assignments and replaced with `Variable(__asl_arg_N)`.
- **After expansion, every top-level statement has a target.** A statement
  is one `Statement` node — a variable assignment (`x = e`), a getter
  assignment (`x.y = e`), or a bare expression — and this pass wraps the
  bare-expression form in a synthetic assignment: `foo(x)` as a statement
  becomes `__asl_arg_N = foo(x)`.
- **Sub-expressions inside nested scopes recurse.** Case block bodies
  are their own `StatementList` and receive their own expansion pass.

**Lift rules by expression kind:**

- `ekLiteral` — never lifted. A literal at a value position must reach
  `analyzeBareLiteral` (§8.3a) with its expected context intact.
- `ekVariable` — never lifted. Already a named binding; wrapping in
  another temp would just add noise.
- `ekGetter` — lifted at value positions (`p.a` in `foo(p.a)` becomes
  `t = p.a; foo(t)`), passed through at assignment / getter-assignment RHS
  positions (`x = p.a` stays `x = p.a`; the enclosing construct is
  already the binding).
- `ekFnCall`, `ekInitializer`, `ekMatch` — always recurse into sub-
  expressions; the outer expression is lifted at value positions,
  passed through at RHS positions.

**Synthetic identifier naming.** Compiler-generated temps use the
`__asl_arg_N` prefix (per-function counter). `newIdentifier` rejects
this prefix for user code, so no collision is possible by
construction; compiler-internal callers use `newGeneratedIdentifier`
in `identifiers.nim` which bypasses the check.

**Interaction with Approach C (§8.3a).** Literals stay unlifted
precisely so `analyzeBareLiteral`'s concrete-adopt behavior keeps
working — `foo(10)` where `foo(a: u8)` still adopts u8 for the bare
`10`. If literals were lifted (`t = 10; foo(t)`), the assignment's
`expected = none` would default t to i32 and the call would mismatch.

---

## 5. Loader / import-path validations

Source: `tests/test_loader.nim`.

### 5.1 Path resolution

- **Bare-relative path (`./foo.asl`)** — resolved against the
  importing file's directory.
- **Vendor path (`@name/...`)** — looked up in `VendorRoots`; unknown
  vendor names rejected with the list of known vendors in the error.
- **Extension fallback.** `.asl` (or `.aslr`) is appended when the
  bare path doesn't exist:
  - `import { X } from "./helper"` finds `./helper.asl` if it exists.
  - Same for shorthand `import "./helper"`.
  - Also tries `.aslr` when no `.asl` file exists at either path.
- **Unrecognized extensions with no fallback are rejected.**
  `./bar.txt` without a corresponding `./bar.txt.asl` errors.

### 5.2 Directory safety

- **Parent-directory escape via `../` is rejected.** The resolved path
  must live under (or at) the importing file's dir. Both direct
  (`../escape.asl`) and sneaky (`./sub/../../escape.asl`) forms fail.

### 5.3 Self-import

- **A file importing itself is rejected** at parse time (`newAslFile`
  compares `imp.absPath == path`) with message *"importing the source
  file in itself is disallowed"*.

### 5.4 Cross-file walk

- **Cyclic imports are detected** by `topoSort` and reported with the
  full cycle path (`A -> B -> A`).
- **Missing imported files** are reported by absolute path.
- **Diamond imports** load each file exactly once (BFS dedup on
  absolute path).
- **Diamond dedup with extension normalization** — `./x` and `./x.asl`
  resolve to the same absolute path so are one file.

### 5.5 Vendor auto-injection

- **`import "@std"` is auto-injected into every `.asl` file** when
  the CLI supplies a `std` vendor entry (default:
  `examples/base.aslr`). Applies whether the file has other imports or
  not.
- **Auto-injection does NOT apply to `.aslr` files** (they carry no
  imports by construction).

---

## 6. File-scope resolution validations

Source: `tests/test_ast.nim` (parser API), `tests/test_resolver.nim`.

### 6.1 Type lookup

- **`findType(name)`** returns *locally-defined* types only; an
  imported binding is not surfaced here.
- **`findImportedName(name)`** returns imported bindings; unimported
  names produce a "not imported" error.
- **`findImportedName` on `.aslr` files always errors** (structurally:
  aslr files have no imports).
- **`findExportedType`** returns a locally-defined `public` type.
  Non-public types are rejected with "non-public"; missing names with
  the standard "not defined" error.

### 6.2 Import binding collisions

Caught either at parser construction time or by
`validateNoDuplicateBindings` in the resolver:

- **Locally-defined + explicit-import same name** → rejected at parse
  time.
- **Locally-defined + shorthand-imported same name** → rejected at
  resolve time with "duplicate type declaration".
- **Explicit-import + shorthand-import same name** → rejected at
  resolve time.
- **Two shorthand imports with overlapping public sets** → rejected
  when the overlap materializes.

### 6.3 Import visibility

- **Importing a non-public type is rejected** at resolve time —
  `findExportedType` refuses to hand out a private type. Error
  message contains `non-public`.
- **Importing a name that does not exist in the source file** is
  rejected.
- **Aliased imports (`Foo as B`)** resolve at use sites to the target
  type — `Byte.value` works after `import { u8 as Byte }`.
- **Shorthand import brings every `public` defined type into scope**,
  skipping non-public ones.

---

## 7. Resolver-phase validations

Source: `tests/test_resolver.nim`.

### 7.1 Name resolution

- **Unknown type references** in argument types, function signatures,
  or bodies are rejected with the offending name in the error and
  "does not exist in the scope".
- **Variable not in scope** — a body-level identifier that isn't a
  parameter or a prior `let`-bound variable is rejected with
  "not present in scope".
- **Function-call on non-existent function** — `Module.no_such_fn(...)`
  is rejected with the function name in the error.
- **Wrong arity call** — `Module.fn(a, b)` when `fn` takes one arg is
  rejected with `arity` in the error.

### 7.2 Initializer field mapping (struct + union)

Domain rule: a struct or union initializer's kwargs must map one-to-
one onto the target's fields — no extras, no missing, no duplicates.
The resolver enforces the count-equality half; the parser AST layer
enforces the duplicate half.

Struct:
- **Exact count.** `Struct { a: 1, b: 2 }` against a two-field struct
  resolves.
- **Extra fields rejected.** `Struct { a: 1, b: 2, c: 3 }` against a
  two-field struct is rejected. Error contains "expects".
- **Missing fields rejected.** `Struct { a: 1 }` against a two-field
  struct is rejected.
- **Fully empty initializer rejected.** `Struct {}` against a struct
  with ≥ 1 field is rejected by the same count check (0 != N).
  `newStructDef` guarantees structs always have ≥ 1 field, so the
  edge case of a "zero-field struct" is structurally impossible.
- **Wrong field name rejected.** Right count but wrong kwarg name —
  `Error { wrong_name: u32 0, message: String "x" }` — falls through
  the count check and fails at `structBlock.findFieldId`.
- **Duplicate kwarg names rejected** at parse time by
  `newKeywordArgumentList`.

Union:
- **Exact count.** `Union.Variant { field: value }` against a
  variant with the same field count resolves.
- **Extra fields rejected.**
- **Missing fields rejected** (when the variant has ≥ 1 field).
- **Zero-field variant accepts empty initializer.** `Union.Empty {}`
  against a variant declared with no fields resolves — the count
  check trivially matches 0 to 0. This is why the shared
  `KeywordArgumentList` allows empty lists (§ 3.7).
- **Non-existent variant rejected.** `Union.NoSuchVariant { … }`
  fails at `union.findVariant` after the union has resolved cleanly.
- **Wrong field name in variant rejected.** Right count but wrong
  kwarg name (`Union.Ok { wrong: v }`) fails at
  `variant.findFieldId`.
- **Duplicate kwarg names rejected** at parse time.

### 7.3 Argument-type impl-list arity

- **Literal-backed type given type parameters** — `u8[K]` when `u8` is
  a literal-only module is rejected with "does not require impl
  types".
- **Explicit-header mismatch** — a module declaring `struct(K, V):`
  invoked as `Array[u8]` (too few impls) is rejected with "expects 2
  impls".
- **Union arg type with too few impls** — same rule for union types
  with declared or inferred generics.

### 7.4 Struct header (`struct(...)`) rules

- **All named generics must be unique** — `struct(K, K):` is rejected
  with "duplicate generic encountered". Fires at struct-header parse
  time via `validateRequiresNameConflict` inside `newStructDefHeader`.
- **Header generics and field generics compose** — a struct's generic
  parameter set is the union of its explicit `struct(A):` header slots
  and every generic collected from its field types, recursing into
  nested argtypes (a field typed `Box[K]` contributes `K`). Header
  slots come first; the rest follow in first-seen order across the
  fields (see also §8.3a on how the analyzer handles their kwarg
  values). Use of such structs is constrained separately by the
  impl-arity check (§7.3) when a generic parameter is exposed at a
  return position.

Unions have no equivalent explicit-header form. A union's generic
parameters are always inferred from its variant field types (see §7.7
for the ordering rule). This asymmetry is intentional: the phantom-type
use case that motivates explicit `struct(A):` is only meaningful on
structs.

### 7.5 Generic-signature bounds

Inside a `generic Foo:` block, an argument-type root may only resolve
to:

- The current generic itself (self-reference like `Foo` in one of its
  own signatures).
- A module (imported or locally-defined).

**Another generic referenced inside a generic block is rejected** —
"generic X can not be used inside generic Y".

### 7.6 Concrete impl-satisfies-generic check

- **A concrete impl passed for a required generic must implement every
  funcDef the generic mandates.** Missing a required method is
  rejected with "does not implement function X to support Y" (test
  `test_analyzer.nim` under "generic constraint satisfaction" —
  landed in the resolver via `checkImplSatisfiesGeneric`).
- **Each concrete impl is checked independently** — a two-generic
  `struct(K, V):` header validates both slots.

### 7.7 Union param-list ordering

- **Union's param list = position-ordered distinct generics across
  all variants in declaration order.** Repeated generic names keep
  their first-seen position; new names take the next slot. Verified
  by `union with the same generic across variants resolves` and
  `union dedups shared generic and orders by first occurrence`.

### 7.8 Error message formatting

Every resolver error message must include:

- **The offending file path** (verified by "error message includes
  the file path").
- **`line:column`** location (verified by scanning for `digit:digit`
  in the error output).

---

## 8. Analyzer-phase validations

Source: `tests/test_analyzer.nim`.

### 8.1 Constraint-satisfaction (post-resolution use sites)

- **A concrete impl missing a required funcDef** is caught at use time
  with "does not implement" + function name + generic name.
- **Two concrete impls (two generic slots) both must satisfy their
  respective generic** — one failure kills the analysis.

### 8.2 Literal-typing

For every numeric literal that flows into a typed position, the
analyzer checks the value fits the target type:

- **8-bit unsigned integer** (`u8`) — range check.
- **16-bit unsigned integer** (`u16`) — range check.
- **32-bit unsigned integer** (`u32`) — range check.
- **64-bit unsigned integer** (`u64`) — range check.
- **8/16/32/64-bit signed integers** (`i8` – `i64`) — same treatment.
- **32-bit float** (`f32`) — overflow rejected; exactly-representable
  values accepted; values that lose precision on narrowing accepted
  with a stderr warning ("cannot be exactly represented").
- **64-bit float** (`f64`) — overflow rejected; power-of-two fractions
  and integer-valued literals with exponent accepted exactly;
  decimals that would round into the mantissa accepted with a warning.
- **Special IEEE-754 values** (`nan`, `inf`, `+inf`, `-inf`) — accepted
  unconditionally for both `f32` and `f64`. The analyzer's fit-check
  and exact-representability warning short-circuit for these forms
  (`validateFloat` in `src/parser/literals.nim`). Numeric literals that
  overflow to infinity or produce NaN via computation are still
  rejected as out-of-range — the special-value short-circuit only
  fires when the source literal was written as the special-value
  token, not as a numeric expression that computes to one. `nan`
  cannot be sign-prefixed (`+nan` / `-nan` are rejected at parse
  time); `inf` accepts optional `+` / `-` sign.

### 8.3 Non-numeric literals

- **String literal** vs numeric target — rejected.
- **Float literal** vs integer target — rejected.
- **Integer literal** vs string target — rejected.
- **Integer literal** vs float target — rejected with "expected float
  ... but found integer".

### 8.3a Bare-literal contextual defaulting

Bare literals in expression position (`x = 10`, `f(1)`, `Struct { field:
"data" }`) don't carry a source-level type prefix. The analyzer picks
one by threading an `expected: Option[AnalyzedArgumentType]` into
`analyzeExpression`; the `rekLiteral` arm dispatches through
`analyzeBareLiteral`:

- `expected = some(concrete module w/ literal data def)` → **adopt** the
  concrete type (concrete adapt). `u8.add(10, 20)` picks up `u8` for
  each bare literal; `Struct { field: 10 }` where `field: u32` picks up
  `u32`.
- `expected = some(generic)` → **default** to `i32` / `f32` / `String`.
  The binding contributes to the generic-impl map at the call site,
  letting the caller substitute the concrete instantiation downstream.
- `expected = none` → **default** to `i32` / `f32` / `String`. This is
  the bare-assignment case (`x = 10`) and the bare-statement case (a
  bare literal as the last expression of a function body — though
  in practice a valid return path will have some prior constraint).

Fit-checking against the chosen module's literal spec happens next
(§8.2 / §8.3 rules apply). A bare literal targeted at a struct or
union module is rejected — the user wrote a literal where an
initializer was expected.

Concrete-position wiring:

- **Function-call args** — per candidate (overloads): each candidate's
  declared arg types are the `expected` for the corresponding call
  arg. First match wins; ambiguity fires the existing multi-match
  error.
- **Struct kwargs** — the field's declared type is `expected`. A
  struct's outer generic parameters are **not** inferred from bare-
  literal kwarg values on the bare init path: the `GenericImplMap`
  returned by the field-vs-value check is currently discarded (see
  the `discard ?` and TODO in `analyzeBareLiteral`,
  `src/analyzer/index.nim`). The kwarg-
  level generic-default still fires — `Holder { value: 42 }` where
  `value: Any` picks up i32 for the kwarg — but the struct's result
  type stays impl-less. Union kwargs (below) accumulate; struct
  kwargs don't.
- **Union kwargs** — the field's declared type, first concretized
  through the current `GenericImplMap`, is `expected`. Free-generic
  fields on the bare path fall through to the default rule and
  contribute to the impl map. `i32!.Ok { value: 42 }` with `value:
  Any` produces `Status[i32, Error]` — i32 is picked as the value
  default AND bound as the impl (the error slot is `Error`, from the
  `!` sugar's default).
- **Getter-assignment RHS** — the getter's field type is `expected`, and
  the analyzer additionally requires the RHS type to equal the field type
  (a `Statement` whose kind is getter; `analyzeStatement` in
  `analyzer/main.nim`).

Defaults are looked up in the file scope. Every `.asl` file gets `@std`
auto-injection that brings `i32` / `f32` / `String` into scope; a bare
literal in a file that skipped that injection surfaces a clear error
naming the missing default type.

**Coverage**: 12 tests in `test_analyzer.nim` under
`analyzer — bare literal defaulting` — three defaulting cases
(int/float/string in bare assignment), one concrete-adopt regression
guard for function args, three concrete-adopt sites (struct kwarg,
union kwarg, getter-assignment RHS), two generic-default sites (struct kwarg
with generic field, union kwarg with generic field), and three
error branches (fit-check range overflow, default type not in scope,
bare literal where a struct is expected).

### 8.4 Case-pattern variant reference

- **A case pattern that names a variant not defined on the union
  subject is rejected.** `analyzeUnionCasePattern` calls
  `union.findVariant(patternName)`; a missing variant surfaces as
  an analyzer error with the variant name in the message.

### 8.5 Error propagation

- **Resolver errors propagate through `analyze*`.** A `NoSuchType`
  from name resolution surfaces at the analyzer boundary with the
  name preserved.
- **Every analyzer error carries the file path and `line:column`**
  location.

### 8.6 Successful analysis (positive path)

The suite also documents what MUST analyze cleanly — these implicitly
constrain future refactors:

- Module with only a self-referential generic.
- File with multiple modules.
- Union module with a method returning a variant.
- Multi-file program with an importer + importee both analyzing.
- Extern functions inside `.aslr` files.
- Public function calling an imported module method.

### 8.7 `try` operator

`try f(...)` is a `FunctionCall` variant (§ grammar `fckTry`); the analyzer
types it as the callee's unwrapped `Ok` value and checks the propagated
`Err` is well-typed. Source: `tests/test_analyzer.nim` under "analyzer —
`try` operator".

- **The callee must return a `Status`.** `try` on a call whose return type
  is a non-`Status` module (e.g. `u32`) is rejected ("requires a call that
  returns a Status"); likewise a call whose concretized return is a bare
  generic.
- **The enclosing function must return a `Status`.** A `try` inside a
  function returning a non-`Status` type (e.g. `i32`) is rejected ("can
  only appear in a function returning a Status").
- **Error slots must match.** The callee's `Error` type must equal the
  enclosing function's `Error` type; a mismatch (e.g. `try` a `u32!MyError`
  inside a `u32!` function) is rejected ("error-type mismatch").
- **On success the expression types as the value slot.** `x = try f()`
  where `f(): u32!` binds `x: u32` (not `u32!`), so downstream use sees the
  unwrapped value.

---

## 9. CLI validations

Source: `tests/test_cli.nim`.

### 9.1 `--vendor=<name>:<path>` flag

- **Value must contain a `:` separator.** Missing `:` rejected with
  the `<name>:<path>` form in the error.
- **Vendor name must be empty-check** — `--vendor=:/x.aslr` rejected
  with "empty vendor name".
- **Vendor path must be non-empty** — `--vendor=std:` rejected with
  "empty path".
- **Vendor name must be a valid ASL identifier.** Same rules as the
  parser's identifier grammar:
  - Starting with a digit is rejected ("valid ASL identifier").
  - Containing a hyphen is rejected.
- **Vendor name must be unique** — two `--vendor=std:a.aslr
  --vendor=std:b.aslr` rejected with both paths in the error and
  "specified more than once".
- **Vendor paths are resolved to absolute paths.** Relative paths
  supplied on the CLI become absolute in `VendorRoots`.

### 9.2 Default vendor

- **`std` is implicitly registered** if the user doesn't provide it.
  Default value: `examples/base.aslr` resolved absolutely. Test:
  "no --vendor flag → default `std` is registered".

---

## Cross-reference

- **Domain-model source of truth:** `grammar.md`.
- **Pipeline overview + phase descriptions:** `overview.md`.
- **Open TODOs and known bugs:** `overview.md` §"What's Next".
- **Test entry point:** `tests/all.nim`.

Every rule above has at least one corresponding test. When a
validation is added, extended, or relaxed, this document should be
updated in the same commit as the test.
