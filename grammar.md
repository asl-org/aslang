# ASL Compiler — Domain Grammar

## Purpose

Source-of-truth vocabulary for the compiler's domain model. Every layer
— parser AST, resolver types, analyzer types — derives from this
grammar. When a domain concept is renamed, added, or restructured, it
lands here *first*; then the code catches up.

This is not a full BNF for the surface language (there's no lexical
detail — whitespace, comments, keyword table, exact tokenization) and
it's not the syntax the user writes; it's the shape of the *values* the
compiler passes around after parsing and resolution. Some rules
deliberately describe the resolved shape rather than the parsed one
(see `ArgumentType` below) — where that's the case, a comment on the
rule says so.

## Reading conventions

- `A: B | C | D` — `A` is a tagged union of variants `B`, `C`, `D`.
- `A: B C` — `A` is a record with fields typed `B`, then `C`
  (positional in this grammar; the type-level definition names them).
- `B+` — one or more `B`, in order.
- `B*` — zero or more `B`, in order.
- `B?` — an optional `B`.
- `# comment` — design-intent note attached to the rule above it.
- Role names (`VarName`, `ModuleName`, `GenericName`, `FunctionName`,
  `TypeName`, `Variant`, `Field`, `Binding`, `Property`, `Source`,
  `LiteralRef`, `ImportedType`) are *documentation labels* — they
  identify the role each `Identifier` plays at that position in the
  grammar. They are NOT distinct types in the code; every one of
  them is just an `Identifier` at runtime. Their purpose here is
  readability of the grammar and reviewer intent (a rule that reads
  `ModuleName` at position N is clearer than one that reads
  `Identifier` twelve times).

## Grammar

```
App: File+

File: Import* Type+

Import: ImportShortHand | ImportExplicit

ImportShortHand: ImportedPath
ImportExplicit: ImportedType+ ImportedPath

ImportedType: Identifier

ImportedPath: ImportedVendorPath | ImportedRelativePath
ImportedVendorPath: VendorName Path
ImportedRelativePath: Path
Path: RawString
VendorName: RawString

Type: Module | Generic

Module: Public? ModuleName (DataModule | FunctionalModule)
DataModule: Data Function*
FunctionalModule: Function+

Data: LiteralDef | StructDef | UnionDef
LiteralDef: StringLiteral
# LiteralDef's StringLiteral names a C type; assume it is typedef'd
# to one of u8 / i8 / f32 / string in the host runtime.

StructDef: StructHeaderGenerics? ArgumentDef+
StructHeaderGenerics: GenericName+
# Surface syntax: `struct(A, B, C):` — a parenthesised comma-separated
# identifier list on the `struct` keyword itself. Absent when the
# header is a plain `struct:`; in that case any generic parameters are
# inferred from the fields.
GenericName: Identifier

UnionDef: VariantDef+
VariantDef: Variant ArgumentDef*
# `ArgumentDef*` — empty variants are structurally legal; whether
# the parser exposes surface syntax for them is a separate question
# (see the "empty variants" task in tasks.md).

Function: ExternFunction | UserFunction
ExternFunction: Public? ExternDecorator FunctionDef
ExternDecorator: StringLiteral
UserFunction: Public? FunctionDef Statement+

Generic: Public? GenericName FunctionDef+
Public: "public"
# `Public` is a presence marker. `Public?` means "the `public`
# keyword may or may not precede this declaration." Every function
# def inside a `Generic` is implicitly public — generics are
# interface types, so their signatures are always callable across
# module boundaries.

FunctionDef: FunctionName ArgumentDef* ReturnType
ReturnType: ArgumentType
FunctionName: Identifier

# ==== Body-level cluster — heaviest cyclic relation of objects. ====

Statement: Assignment | Setter | Expression
Assignment: VarName Expression
VarName: Identifier

Expression: Initializer | FunctionCall | Getter | Variable | MatchExpression | Literal
# A bare `Literal` in expression position is syntactic sugar for a
# `LiteralInitializer` with a default type prefix — `i32` for integer
# literals, `f32` for float, `String` for string. The expansion happens
# at the analyzer layer via contextual defaulting: bare literals in
# concrete-typed positions (function args with concrete arg type, kwarg
# fields with concrete field type, setter RHS) adopt the position's
# declared type; bare literals in generic-typed or unconstrained
# positions (`x = 10`) take the default. See §8.3a of validations.md.

Initializer: LiteralInitializer | StructInitializer | UnionInitializer
LiteralInitializer: LiteralRef Literal
LiteralRef: ModuleName
ModuleName: Identifier
Literal: IntegerLiteral | FloatLiteral | StringLiteral
# FloatLiteral additionally accepts C-style special IEEE-754 values:
# `nan`, `inf`, `+inf`, `-inf`. `nan` cannot be sign-prefixed. Any
# float type (`f32`, `f64`) accepts these unconditionally; the
# analyzer's fit-check / exact-representability warning is skipped
# for the special forms. Numeric literals that overflow to infinity
# or NaN are still rejected as out-of-range.

StructInitializer: ArgumentType KeywordArgument+
UnionInitializer: ArgumentType Variant KeywordArgument*
Variant: Identifier
KeywordArgument: VarName Expression?
# If `Expression` is absent, the value is synthesized as a bare
# Variable of the same name — `Struct { x }` is equivalent to
# `Struct { x: x }`. Mirrors the `KeywordArgumentPattern: Field
# Binding?` sugar on the case-pattern side.

FunctionCall: FunctionRef Expression*
Getter: Source Property
Setter: Getter Expression
Source: Identifier
Property: Identifier

Variable: Identifier

MatchExpression: Expression Case+
Case: CaseDef Statement+
CaseDef: UnionPattern | LiteralPattern | VariablePattern
VariablePattern: Identifier

# ==== Type-shape and reference cluster. ====

ArgumentType: (ModuleArgumentType | GenericArgumentType) '!'?
# Resolver-level split. The parser's flatter form is just
# `Identifier ArgumentType*`; the resolver disambiguates by looking
# up the head identifier in scope.
#
# Trailing `!` is sugar for wrapping in `Status[...]`. Binds tight
# to the type it immediately follows:
#   T!            -> Status[T]
#   Array[u32]!   -> Status[Array[u32]]
#   Array[u32!]   -> Array[Status[u32]]
#   Status[u32]!  -> Status[Status[u32]]     (syntactically legal)
# The sugar collapses at parse time; downstream (resolver, analyzer)
# sees a plain `Status[...]` ArgumentType, no distinct AST variant.

ModuleArgumentType: ModuleName ArgumentType*
GenericArgumentType: GenericName

FunctionRef: TypeName FunctionName
# All calls today are of the form `Receiver.name(args)`. Future
# method-like calls (`x.method(args)` where `x` is a variable)
# will lower to this same shape: the analyzer infers `x`'s
# ArgumentType, extracts its TypeName, and produces a
# `FunctionRef(TypeName, FunctionName)` — so no new variant is
# needed at the domain level.

TypeName: ModuleName | GenericName

UnionPattern: Variant KeywordArgumentPatternList?
LiteralPattern: Literal
ArgumentDef: ArgumentType VarName

KeywordArgumentPatternList: KeywordArgumentPattern+
KeywordArgumentPattern: Field Binding?
# If `Binding` is absent, the binding takes the field's name —
# `case Ok { value }` is equivalent to `case Ok { value: value }`.
Field: Identifier
Binding: Identifier

Identifier: [_a-zA-Z][_a-zA-Z0-9]*
# `_` is a valid `Identifier`. Keyword exclusion (rejecting
# `module` / `func` / `import` etc. as Identifiers) is a
# parser-level concern, not encoded in this regex.
```

## Design decisions worth preserving

Notes that surfaced while iterating this grammar — kept here so future
contributors can find the *why* alongside the *what*.

- **Modules without a data block are namespaces, not values.** A
  function-only module (like `System`) can be called
  (`System.println(...)`) but cannot appear as an argument or
  return type — the resolver rejects it at argument-type resolution
  ("is not a data module"). An earlier design had `System` as a
  struct threaded through `start(sys: System)`; that was ditched —
  runtime capabilities are reached through the namespace, not
  passed as a value.

- **Only structs support the explicit `struct(...)` generic header.**
  The escape hatch exists for runtime containers like `Array` and
  `Map`: they store pointers to their element data, which is not
  representable in the language, so their type parameters cannot be
  inferred from fields and must be declared as phantom params.
  Consequences: a struct with an explicit header rejects generic
  fields and rejects bare (impl-less) refs ("expects N impls"),
  while inferred-generic structs and generic unions accept bare
  refs (leave-as-is inference fills the positions). Unions never
  take a header — their params are always inferred from variant
  fields.

- **Decorators are not first-class in the domain today.** `@extern` is
  handled inline on `ExternFunction`. If a second decorator (e.g.
  `@deprecated`) is added, look at the resolution/analysis pattern
  and generalize; until then the domain stays lean.

- **`Public` distributes across `Module`, `Function`, `Generic`.** It
  could be hoisted to a single wrapper (`Type: Public? …`,
  `Function: Public? …`), but the distributed form keeps each type
  self-contained and reads more naturally at each declaration site.
  Every function def inside a `Generic` is implicitly public (see
  the `Generic` rule's comment).

- **Function visibility is decided by the definition context, not
  the call syntax.** Every type reference resolves inside a
  `TypeContext` (the enclosing module or generic block); a
  non-public function is visible only when that context IS the
  defining module (`FunctionAccess`: `faAll` vs `faPublic`). The
  rule is enforced at both checkpoints that look functions up: call
  sites (`resolveFunctionCall`) and generic-constraint satisfaction
  (`satisfies` at resolve time, `checkImplSatisfies` at def time) —
  so a private function can neither be called from another module
  nor make its module satisfy a constraint written elsewhere.

- **`ArgumentType` splits at the resolver level, not the parser
  level.** From the parse text alone, `Foo` could be a module or a
  generic — the resolver disambiguates by looking up `Foo` in scope.
  The parser's `ArgumentType` is a flatter `Identifier ArgumentType*`
  that the resolver converts into one of the two tagged variants.

- **`FunctionRef` is always `TypeName FunctionName`.** No local-call
  variant (bare `foo(args)`) — every call today is a method call
  with an explicit receiver. Future method-like calls where the
  receiver is a variable name will lower to this same shape after
  the analyzer infers the variable's type.

- **Cardinality (`+` vs `*`) is deliberate everywhere.** `App: File+`
  (there's always an entry file), `File: Import* Type+` (a file with
  no types is meaningless), `StructDef: StructHeaderGenerics? ArgumentDef+`
  (a struct with zero fields is invalid), `VariantDef: Variant
  ArgumentDef*` (empty variants are structurally legal — surface
  syntax is a separate question), `UnionInitializer: … KeywordArgument*`
  (matches the empty-variant cardinality).

- **Structs must have fields; union variants don't have to.** The
  `+` on `StructDef.ArgumentDef+` vs the `*` on `VariantDef.ArgumentDef*`
  is a language-level design decision, not accidental. A struct with
  zero fields is meaningless data — there's nothing there. A union
  variant with zero fields is a legitimate signal: the variant tag
  itself is the information. E.g. `Event.Timeout` conveys "a timeout
  happened" without needing to carry any payload. Downstream syntax
  work on empty-variant instantiation and pattern matching must
  respect this asymmetry: `Timeout {}` (empty braces on a struct-like
  syntax) is not an obligation, and `S {}` for a struct S is not a
  language goal.

- **Role names are documentation, not distinct types.** The grammar
  labels each identifier position by its role (`VarName`,
  `ModuleName`, `GenericName`, etc.) so the shape is readable, but
  in the code every one of these is just an `Identifier`. Distinct
  newtypes were considered and dropped: the borrow-op boilerplate
  outweighed the compile-error protection for what turns out to be
  a small class of realistic mistakes.

- **Discard (`_ = expr`) is a regular `Assignment` with `VarName = "_"`.**
  `_` is a valid `Identifier`. No dedicated `Discard` statement
  variant until we see a downstream branch that specifically needs
  the distinction.

## Relationship to the layer types

Each pipeline phase's type module (`src/analyzer/resolver/parser/*`,
`src/analyzer/resolver/*`, `src/analyzer/*`) is expected to trace
back to this grammar. Renames
land here first; then the code catches up. When a type appears in two
layers (e.g. `Struct` at parser level, `ResolvedStruct` at resolver
level), both are recognizable projections of the same grammar rule —
the resolver layer just carries additional fields (indices, resolved
references) added via accessor delegation from the parser back-ref.

Ongoing refactor tasks that reshape the code toward this grammar are
tracked in `tasks.md` under "DDD refactor: align every layer with the
locked domain grammar."
