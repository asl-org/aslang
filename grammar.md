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
- Role-typed identifiers (`VarName`, `ModuleName`, `GenericName`,
  `FunctionName`, `TypeName`, `Variant`, `Field`, `Binding`,
  `Property`, `Source`, `LiteralRef`, `ImportedType`) are distinct
  types wrapping `Identifier`. Structurally they're all identifiers;
  the type system prevents mixing them so passing a `ModuleName`
  where a `VarName` is expected is a compile error, not a bug.

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

StructDef: Requires? ArgumentDef+
Requires: GenericName+
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

Expression: Initializer | FunctionCall | Getter | Variable | MatchExpression

Initializer: LiteralInitializer | StructInitializer | UnionInitializer
LiteralInitializer: LiteralRef Literal
LiteralRef: ModuleName
ModuleName: Identifier
Literal: IntegerLiteral | FloatLiteral | StringLiteral

StructInitializer: ArgumentType KeywordArgument+
UnionInitializer: ArgumentType Variant KeywordArgument*
Variant: Identifier
KeywordArgument: VarName Expression

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

ArgumentType: ModuleArgumentType | GenericArgumentType
# Resolver-level split. The parser's flatter form is just
# `Identifier ArgumentType*`; the resolver disambiguates by looking
# up the head identifier in scope.

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
  no types is meaningless), `StructDef: Requires? ArgumentDef+` (a
  struct with zero fields is invalid), `VariantDef: Variant
  ArgumentDef*` (empty variants are structurally legal — surface
  syntax is a separate question), `UnionInitializer: … KeywordArgument*`
  (matches the empty-variant cardinality).

- **Role-typed identifiers make misuse a compile error.** Passing a
  `ModuleName` where a `VarName` is expected — a class of "I copied
  the wrong string" bug — becomes a type mismatch instead of a
  runtime-lookup miss three passes later.

- **Discard (`_ = expr`) is a regular `Assignment` with `VarName = "_"`.**
  `_` is a valid `Identifier`. No dedicated `Discard` statement
  variant until we see a downstream branch that specifically needs
  the distinction.

## Relationship to the layer types

Each pipeline phase's type module (`src/parser/*`, `src/resolver/*`,
`src/analyzer/*`) is expected to trace back to this grammar. Renames
land here first; then the code catches up. When a type appears in two
layers (e.g. `Struct` at parser level, `ResolvedStruct` at resolver
level), both are recognizable projections of the same grammar rule —
the resolver layer just carries additional fields (indices, resolved
references) added via accessor delegation from the parser back-ref.

Ongoing refactor tasks that reshape the code toward this grammar are
tracked in `tasks.md` under "DDD refactor: align every layer with the
locked domain grammar."
