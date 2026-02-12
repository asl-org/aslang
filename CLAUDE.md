# CLAUDE.md - ASLang Compiler Project Guide

## Project Overview

ASLang (A Software Language) is a compiler for a new programming language designed for zero-maintenance systems. It targets readability, security, performance, and software architecture by turning common architectural patterns into single-line declarations instead of boilerplate code.

- **Compiler language:** Nim (2.2.0)
- **Source files:** `.asl`
- **Target:** C code, then compiled to native executables via GCC
- **Runtime:** Custom C runtime library (`runtime.c` / `runtime.h`)
- **Codebase:** ~7,600 lines of Nim across 74 source files

## Build and Test

```bash
# Build the compiler
nimble build

# Build for release
nimble build -d:release

# Run all tests (preferred method - builds and runs all examples)
bash test.sh

# Manual test (pick any file from examples/)
./aslang examples/docs/struct.asl -o:sample && ./sample
# Exit code should always be 0
```

### Test Categories

- **Documentation examples** (`examples/docs/`): `struct.asl`, `union.asl`, `generic_struct.asl`, `generic_union.asl`
- **Project Euler solutions** (`examples/project-euler/`): `problem001.asl` through `problem010.asl`

## Compilation Pipeline

```
Source (.asl) -> Tokenizer -> Parser -> Resolver -> Analyzer -> Codegen -> C Code -> GCC -> Binary
```

The pipeline is implemented as a clean chain in `src/compiler.nim`:

```nim
let tokens = ? tokenize(filename, content)
let file = ? parse(filename, tokens)
let resolved_file = ? resolve(file)
let analyzed_file = ? analyze(resolved_file)
let code = ? analyzed_file.c()
```

### 1. Tokenizer (`src/codegen/analyzer/resolver/parser/tokenizer.nim` + `tokenizer/`)
- Reads raw source files and converts text into tokens
- Token types: operators, brackets, literals (string, digits, alphabets), whitespace, comments
- Tracks source location (filename, line, column, index) for error reporting
- Key function: `tokenize(filename, content) -> Result[seq[Token], string]`

### 2. Parser (`src/codegen/analyzer/resolver/parser.nim` + `parser/`)
- Consumes tokens and produces unresolved AST
- Top-level type: `File` containing modules and file-level functions
- Modules contain generics, data (struct or union), and functions
- `parser.nim` acts as an import/export hub following Nim convention
- Key function: `parse(path, tokens) -> Result[File, string]`

### 3. Resolver (`src/codegen/analyzer/resolver.nim` + `resolver/`)
- Assigns types to identifiers (variables, modules)
- Produces `Resolved*` versions of AST nodes
- Tracks module dependencies and detects circular dependencies
- Performs topological sort of modules for resolution order
- Validates numeric literal ranges for target types
- Key function: `resolve(file) -> Result[ResolvedFile, string]`

### 4. Analyzer (`src/codegen/analyzer.nim` + `analyzer/`)
- Performs semantic analysis and validation
- Validates that types follow defined constraints
- Produces `Analyzed*` versions of AST nodes
- Performs monomorphization (instantiates generic types with concrete types)
- Key function: `analyze(resolved_file) -> Result[AnalyzedFile, string]`

### 5. Codegen (`src/codegen.nim` + `codegen/`)
- Generates C code from analyzed AST
- Each codegen file mirrors an analyzer type (e.g., `codegen/function.nim` generates C for `AnalyzedFunction`)
- Key function: `c(analyzed_file) -> Result[string, string]`
- Generated C code is compiled with `gcc -O3 runtime.c <output>.c -o <binary>`

## Project Structure

```
src/
  aslang.nim                    # CLI entry point (arg parsing, invokes compile)
  compiler.nim                  # Compilation orchestration (tokenize -> parse -> resolve -> analyze -> codegen -> gcc)
  codegen.nim                   # Import/export hub for codegen layer (imports analyzer + codegen/file)
  codegen/
    # Codegen layer (C code generation from Analyzed* types)
    arg.nim                     # AnalyzedArgument -> C
    arg_def.nim                 # AnalyzedArgumentDefinition -> C (byte_size, c)
    expression.nim              # AnalyzedStatement -> C
    file.nim                    # AnalyzedFile -> C (top-level file generation)
    file_def.nim                # AnalyzedFileDefinition -> C (headers, struct defs)
    fncall.nim                  # AnalyzedFunctionCall -> C
    func_def.nim                # AnalyzedFunctionDefinition -> C (c_name, h)
    function.nim                # AnalyzedUserFunction -> C
    generic.nim                 # AnalyzedGeneric -> C
    initializer.nim             # AnalyzedInitializer -> C
    literal.nim                 # AnalyzedLiteral -> C
    module.nim                  # AnalyzedModule -> C
    module_def.nim              # AnalyzedModuleDefinition -> C (headers, data defs)
    module_ref.nim              # AnalyzedModuleRef -> C (byte_size, c)
    struct.nim                  # AnalyzedStruct/Union -> C (h, c)
    struct_get.nim              # AnalyzedStructGet -> C
    struct_init.nim             # AnalyzedStructInit -> C
    struct_ref.nim              # AnalyzedDataRef -> C

    # Analyzer layer (Analyzed* types, semantic analysis)
    analyzer.nim                # Import/export hub for analyzer layer
    analyzer/
      module_ref.nim            # AnalyzedModuleRef, AnalyzedImpl (generic instantiation)
      arg_def.nim               # AnalyzedArgumentDefinition
      arg.nim                   # Argument analysis
      struct.nim                # AnalyzedStruct, AnalyzedUnionBranch, AnalyzedUnion, AnalyzedData
      struct_ref.nim            # AnalyzedStructRef, AnalyzedUnionRef, AnalyzedDataRef
      struct_init.nim           # AnalyzedStructInit
      struct_get.nim            # AnalyzedStructGet (field access)
      struct_pattern.nim        # AnalyzedStructPattern
      case_pattern.nim          # AnalyzedCasePattern
      literal.nim               # Literal analysis
      initializer.nim           # AnalyzedInitializer
      func_ref.nim              # AnalyzedFunctionRef
      func_def.nim              # AnalyzedFunctionDefinition
      fncall.nim                # AnalyzedFunctionCall
      function.nim              # AnalyzedUserFunction, AnalyzedFunction
      expression.nim            # AnalyzedExpression, AnalyzedStatement, AnalyzedMatch, AnalyzedCase, AnalyzedElse
      generic.nim               # Generic analysis
      module.nim                # AnalyzedModule
      module_def.nim            # AnalyzedModuleDefinition
      file_def.nim              # AnalyzedFileDefinition, FunctionScope
      file.nim                  # AnalyzedFile (top-level analysis)

      # Resolver layer (Resolved* types, type assignment)
      resolver.nim              # Type resolution entry point + cycle detection + literal validation
      resolver/
        module_ref.nim          # ResolvedModuleRef
        defs.nim                # ResolvedArgumentDefinition, ResolvedFunctionDefinition, ResolvedStruct, ResolvedUnionBranch, ResolvedUnion, ResolvedData
        fncall.nim              # ResolvedFunctionRef, ResolvedFunctionCall, ResolvedStructGet, ResolvedVariable
        initializer.nim         # ResolvedLiteralInit, ResolvedStructRef, ResolvedStructInit, ResolvedInitializer
        expression.nim          # ResolvedExpression, ResolvedStatement, ResolvedCase, ResolvedElse, ResolvedMatch, ResolvedUserFunction, ResolvedExternFunction, ResolvedFunction
        module.nim              # ResolvedGeneric, ResolvedModule
        file.nim                # ResolvedFile

        # Parser layer (unresolved AST)
        parser.nim              # Parser hub + native module initialization + parse()
        parser/
          tokenizer.nim         # Tokenizer hub
          tokenizer/
            location.nim        # Source position tracking (Location, Cursor)
            cursor.nim          # Character cursor
            token.nim           # Token type (kind, value, location)
            spec.nim            # Token specifications (matchers)
            constants.nim       # Operator/special character definitions
            error.nim           # Tokenizer errors
          core.nim              # Parser infrastructure (Parser type, indent/space handling, combinators)
          repo.nim              # Repo[T] - flexible indexed lookups with duplicate detection
          identifier.nim        # Identifier type and parsing
          module_ref.nim        # ModuleRef (recursive, supports generics like Array[Item])
          literal.nim           # Literal types (IntegerLiteral, FloatLiteral, StringLiteral)
          defs.nim              # StructDefinition, ArgumentDefinition, FunctionDefinition
          struct.nim            # Struct, UnionBranch, Union, Data
          arg.nim               # Argument, FunctionRef, FunctionCall
          initializer.nim       # LiteralInit, StructRef, StructInit, Initializer, StructGet
          pattern.nim           # MatchDefinition, StructPattern, CasePattern, CaseDefinition
          expression.nim        # Expression, Statement, Case, Else, Match (mutually recursive)
          generic.nim           # Generic type (default or constrained with function defs)
          function.nim          # UserFunction, ExternFunction, Function
          module.nim            # Module (generics, data, functions)
          file.nim              # File (top-level container)

examples/
  docs/                         # Language feature examples (4 files)
    struct.asl                  # Struct definitions and usage
    union.asl                   # Discriminated unions
    generic_struct.asl          # Generic struct instantiation
    generic_union.asl           # Generic union patterns
  project-euler/                # Project Euler solutions (10 files)
    problem001.asl - problem010.asl

runtime.c                       # C runtime library implementation
runtime.h                       # C runtime type definitions
test.sh                         # Test runner script
aslang.nimble                   # Nim package manifest
```

### Import Hierarchies

#### Parser Layer Import Order

```
parser.nim (hub - imports and re-exports all submodules)
  ├── parser/tokenizer       # No dependencies
  ├── parser/core            # No dependencies
  ├── parser/repo            # No dependencies
  ├── parser/identifier      # Depends on core
  ├── parser/module_ref      # Depends on identifier, core
  ├── parser/defs            # Depends on identifier, module_ref, core
  ├── parser/literal         # Depends on identifier, core
  ├── parser/struct          # Depends on defs, identifier, module_ref, core
  ├── parser/arg             # Depends on identifier, module_ref, literal, core
  ├── parser/initializer     # Depends on identifier, module_ref, literal, arg, core
  ├── parser/pattern         # Depends on identifier, literal, core
  ├── parser/expression      # Depends on identifier, arg, initializer, pattern, core
  ├── parser/generic         # Depends on identifier, module_ref, defs, core
  ├── parser/function        # Depends on identifier, module_ref, defs, expression, core
  ├── parser/module          # Depends on identifier, module_ref, defs, struct, generic, function, core
  └── parser/file            # Depends on module, function, core
```

#### Resolver Layer Import Chain

Each file imports `parser` (the hub) to get all parser types:

```
resolver.nim (entry point - cycle detection, literal validation, topological sort)
  ├── resolver/module_ref    # ResolvedModuleRef
  ├── resolver/defs          # ResolvedArgumentDefinition, ResolvedFunctionDefinition, ResolvedStruct, ResolvedData
  ├── resolver/fncall        # ResolvedFunctionRef, ResolvedFunctionCall, ResolvedStructGet, ResolvedVariable
  ├── resolver/initializer   # ResolvedLiteralInit, ResolvedStructRef, ResolvedStructInit, ResolvedInitializer
  ├── resolver/expression    # ResolvedExpression, ResolvedStatement, ResolvedUserFunction, ResolvedFunction
  ├── resolver/module        # ResolvedGeneric, ResolvedModule
  └── resolver/file          # ResolvedFile
```

#### Analyzer Layer Import Chain

```
analyzer.nim (hub - imports resolver and all analyzer modules, exports both)
  analyzer/file.nim          # AnalyzedFile (imports all other analyzer modules)
  analyzer/function.nim      # AnalyzedUserFunction, AnalyzedFunction
  analyzer/expression.nim    # AnalyzedExpression, AnalyzedStatement, AnalyzedMatch, etc.
  analyzer/module.nim        # AnalyzedModule
  analyzer/module_def.nim    # AnalyzedModuleDefinition
  analyzer/file_def.nim      # AnalyzedFileDefinition, FunctionScope
  analyzer/func_def.nim      # AnalyzedFunctionDefinition
  analyzer/module_ref.nim    # AnalyzedModuleRef, AnalyzedImpl
  analyzer/arg_def.nim       # AnalyzedArgumentDefinition
  ... (remaining analyzer files)
```

#### Codegen Layer Import Chain

```
codegen.nim (hub - imports analyzer hub + codegen/file, exports both)
  codegen/file.nim           # AnalyzedFile -> C (imports all other codegen modules)
  codegen/function.nim       # AnalyzedFunction -> C
  codegen/expression.nim     # AnalyzedStatement -> C
  codegen/module.nim         # AnalyzedModule -> C
  codegen/module_def.nim     # AnalyzedModuleDefinition -> C
  codegen/file_def.nim       # AnalyzedFileDefinition -> C
  ... (remaining codegen files mirror analyzer types)
```

## ASLang Language Syntax

### Entry Point

Every program must define a `start` function with signature `fn start(U8 seed): U8`:

```asl
fn start(U8 seed): U8
  U8 0
```

### Modules

```asl
module ModuleName:
  # Can contain: struct/union, generics, extern functions, user functions
```

### Structs

```asl
module User:
  struct:
    U64 id
    U64 age

  fn print(User user): U64
    user_id = user.id
    System.print(user_id)
```

### Unions (Discriminated)

```asl
module Status:
  generic Value
  union:
    Ok:
      Value value
    Err:
      Error error
```

### Functions

```asl
fn function_name(ArgType arg1, ArgType arg2): ReturnType
  result1 = some_expression
  result2 = another_expression
  result2  # implicit return (last expression)
```

### Function Calls

```asl
result = ModuleName.function_name(arg1, arg2)
field_value = instance.field_name
```

### Literals

```asl
integer = S64 42
unsigned = U8 0
float_val = F64 3.14
text = String "hello"
```

### Struct Initialization

```asl
user = User { id: id_val, age: age_val }
ok_status = Status[U64].Ok { value: 0 }
```

### Pattern Matching

```asl
match variable:
  case Ok { value: temp }:
    # use temp
    result_expr
  case Err { error: e }:
    # use e
    result_expr
  else:
    fallback_expr
```

### Extern Functions (C FFI)

```asl
module S64:
  extern S64_add_S64:
    fn add(S64 a, S64 b): S64
```

### Generics

```asl
module Array:
  generic Item
  struct:
    U64 size
  extern Array_init:
    fn init(U64 size): Array[Item]
```

### Built-in Modules

| Module | Description |
|--------|-------------|
| `S8`, `S16`, `S32`, `S64` | Signed integers |
| `U8`, `U16`, `U32`, `U64` | Unsigned integers |
| `F32`, `F64` | Floating point |
| `String` | String type |
| `Pointer` | Raw pointer |
| `Error` | Error struct with code and message |
| `Status[T]` | Generic union: Ok(value) or Err(error) |
| `Array[T]` | Generic array with init, get, set |
| `System` | allocate, free, box, print functions |

## Coding Conventions

### File Organization
- Max 250 lines per file for readability
- Chain imports/exports - each module imports and re-exports its dependency
- Functions close to their struct definitions
- **Hub pattern**: `<name>.nim` acts as import/export hub for `<name>/` directory
- **Mutually recursive types**: Must be defined together in a single `type` block (e.g., Expression, Statement, Case, Else, Match)

### Naming Conventions
- `underscore_case` for all identifiers (never camelCase)
- Constructors: `new_<struct>`
- Properties: named after the field (e.g., `location`, `name`, `kind`)
- Extractors: named like properties with `*` export marker (`extern*`, `user*`)
- Helpers: action-based names (`find_module`, `find_generic`)

### Struct Definition Pattern

For every struct type, follow this order:

```nim
# 1. Kind enum (if variant type)
type StructKind* = enum
  SK_VARIANT_A, SK_VARIANT_B

# 2. Type definition
type Struct* = ref object of RootObj
  field: SomeType
  case kind: StructKind
  of SK_VARIANT_A: field_a: TypeA
  of SK_VARIANT_B: field_b: TypeB

# 3. Constructors - new_<struct>
proc new_struct*(field_a: TypeA): Struct =
  Struct(kind: SK_VARIANT_A, field_a: field_a)

# 4. Properties - only accept struct, return value
proc location*(struct: Struct): Location = struct.location

# 5. Extractors - return Result for variant-specific access
proc variant_a*(struct: Struct): Result[TypeA, string] =
  case struct.kind:
  of SK_VARIANT_A: ok(struct.field_a)
  of SK_VARIANT_B: err(fmt"{struct.location} expected variant A")

# 6. Helper functions
proc find_field*(struct: Struct, name: Identifier): Result[Field, string] =
  # lookup logic
```

### Visibility Rules
- Export (`*`) only procs that are used by other modules
- Constructors used only within the same file should be private
- `kind*` accessor procs on variant types MUST stay public if the type's discriminator is accessed from other modules (Nim requirement)
- Codegen `c()` / `h()` helper procs that are only called within the same file should be private

### Control Flow
- Always use `case` statements for checking `.kind` - never `if x.kind == ...`
- Exhaustive case handling - handle all variants explicitly

```nim
# GOOD
case module.kind:
of MK_CASE_ONLY: # handle
of MK_COMPLETE: # handle

# BAD
if module.kind == MK_CASE_ONLY:
  # ...
```

### Error Handling
- Use `Result[T, string]` for operations that can fail
- Error messages include location: `err(fmt"{location} message")`
- Use `?` operator to propagate errors

```nim
proc do_something(x: X): Result[Y, string] =
  let value = ? x.get_value()  # propagates error if failed
  ok(value.transform())
```

### Import/Export Pattern
- Chain exports to minimize import statements at call sites
- Place exports immediately after imports

```nim
import resolver/parser
export parser

import resolved_ref
export resolved_ref
```

### Dependency Management
- Minimize inter-module dependencies
- Export only what is needed (use `*` marker)
- Handle cyclic type dependencies by grouping in single `type` block
- **Mutually recursive types**: Define all types together in one `type` block, use forward declarations for procs

```nim
# Forward declarations for mutually recursive procs
proc location*(match: Match): Location
proc match_spec*(parser: Parser, indent: int): Result[Match, string]

# Mutually recursive types - all defined together
type
  Expression* = ref object of RootObj
    case kind: ExpressionKind
    of EK_MATCH: match: Match
    # ... other variants

  Statement* = ref object of RootObj
    expression: Expression

  Match* = ref object of RootObj
    case_blocks: seq[Case]
```

## Key Types

### Parser Layer (Unresolved AST)

| Type | Description |
|------|-------------|
| `File` | Top-level container for all modules and file-level functions |
| `Module` | Module with generics, data (struct/union), and functions |
| `Generic` | Generic type parameter (default or constrained with function defs) |
| `Data` | Module data: none, literal, struct, or union |
| `Struct` | Data structure with named fields |
| `UnionBranch` | Union variant with name and fields |
| `Union` | Discriminated union with branches |
| `Function` | Variant of `UserFunction` or `ExternFunction` |
| `UserFunction` | User-defined function with steps (statements) |
| `ExternFunction` | External C function binding |
| `Repo[T]` | Flexible indexed lookup collection with duplicate detection |

### Resolver Layer (Resolved AST)

| Type | Description |
|------|-------------|
| `ResolvedFile` | Top-level resolved container with start function |
| `ResolvedModule` | Resolved module with generics, data, and functions |
| `ResolvedGeneric` | Generic type parameter with resolved function definition repo |
| `ResolvedModuleRef` | Reference to a module with resolved children |
| `ResolvedFunctionDefinition` | Function signature with resolved args and return |
| `ResolvedArgumentDefinition` | Function argument with resolved type |
| `ResolvedStruct` | Struct with resolved fields (default or named) |
| `ResolvedData` | Module data: none, literal, struct, or union |
| `ResolvedExpression` | Expression variant (match, fncall, init, struct_get, variable) |
| `ResolvedStatement` | Assignment statement with resolved expression |
| `ResolvedFunction` | Variant of `ResolvedUserFunction` or `ResolvedExternFunction` |
| `ResolvedMatch` | Pattern matching expression |
| `ResolvedFunctionCall` | Function call with resolved arguments |
| `ResolvedInitializer` | Literal or struct initialization |

### Analyzer Layer (Analyzed AST)

| Type | Description |
|------|-------------|
| `AnalyzedFile` | Top-level analyzed file |
| `AnalyzedModule` | Analyzed module with definition and functions |
| `AnalyzedModuleDefinition` | Module definition with data and function defs |
| `AnalyzedFileDefinition` | File definition with FunctionScope support |
| `AnalyzedModuleRef` | Variant: AMRK_GENERIC (generic ref) or AMRK_MODULE (concrete module with impls) |
| `AnalyzedImpl` | Generic implementation binding (module_ref + constraint function defs) |
| `AnalyzedFunctionDefinition` | Concrete function signature |
| `AnalyzedArgumentDefinition` | Parameter with analyzed module ref |
| `AnalyzedFunction` | Variant of user or extern function |
| `AnalyzedExpression` | Expression variant (match, fncall, init, struct_get, variable) |
| `AnalyzedStatement` | Statement with analyzed expression |
| `AnalyzedMatch` | Pattern matching with case/else blocks |
| `AnalyzedStruct` | Struct with analyzed field types |
| `AnalyzedFunctionCall` | Function call with analyzed arguments |
| `AnalyzedInitializer` | Analyzed literal or struct initialization |
| `AnalyzedStructGet` | Analyzed field access |
| `AnalyzedCasePattern` | Pattern in a case block (literal or struct) |
| `FunctionScope` | Variable scope tracking during analysis |

## Common Patterns

### Repo Pattern

`Repo[T]` provides flexible indexed lookups with multiple composite indexes, duplicate detection, and name/hash-based access. Used for functions, generics, fields, and module lookups at both parser and resolver layers.

### Error Message Helpers

```nim
proc err_no_default_struct(location: Location, module_name: string): string =
  fmt"{location} module `{module_name}` does not have a default struct"
```

### Monomorphization

Generic modules are instantiated per concrete type usage. The analyzer collects all implementations (`AnalyzedImpl`) from usage sites, then the codegen generates separate C code for each concrete instantiation.

## Refactoring Guidelines

1. Max 60 lines per change - Keep changes small and verifiable
2. Always run `bash test.sh` after each change
3. Fix linter errors immediately - Do not proceed with broken code
4. One function at a time - When unifying types, migrate incrementally
5. Preserve argument order - Match order of variable existence in scope
6. Use chain exports - Import and re-export dependencies to minimize import statements
7. Keep files under 250 lines - Split large files following the `<name>.nim` + `<name>/` pattern
8. **Parser breakdown pattern**: When breaking down parser files:
   - Extract related types into focused modules
   - Keep mutually recursive types together
   - Order imports by dependency (no dependencies first, then dependent modules)
   - Update hub file to import and export all submodules

## Runtime Library

The C runtime (`runtime.c` / `runtime.h`) provides:

- **Type mappings**: `S8`->`int8_t`, `U64`->`uint64_t`, `String`->`char*`, `Pointer`->`void*`, etc.
- **Memory**: `System_allocate`, `System_free`, `System_box_*`
- **I/O**: `System_print_*` for all primitive types
- **Arithmetic**: `add`, `subtract`, `multiply`, `quotient`, `remainder` for numeric types
- **Comparison**: `compare` returning S8 (-1, 0, 1)
- **Bitwise**: `lshift`, `rshift`, `and`, `or`, `not`
- **Type conversion**: `from` functions (e.g., `S64_from_U8`)
- **Memory access**: `byte_size`, `read`, `write` for all types
- **String**: `String_get` returning `Status[U8]`
- **Array**: `Array_init`, `Array_set`, `Array_get` with Status-based error handling
