# AGENT.md - ASLang Compiler Project Guide

## Project Overview

ASLang is a programming language compiler written in Nim. It compiles `.asl` source files to C code, which is then compiled to native executables.

## Build and Test

```bash
# Build the compiler
nimble build

# Run tests (preferred method)
bash test.sh

# Manual test (pick any file from examples/)
./aslang examples/<filename>.asl -o:sample && ./sample
# Exit code should always be 0
```

## Compilation Pipeline

```
Source (.asl) -> Tokenizer -> Parser -> Deps Analyzer -> Resolver -> Codegen -> C Code
```

### 1. Tokenizer (`src/resolver/deps_analyzer/parser/tokenizer.nim`)
- Reads raw source files
- Converts text into tokens (identifiers, keywords, literals, operators)
- Makes it easier to work with raw text

### 2. Parser (`src/resolver/deps_analyzer/parser.nim` + `parser/` submodules)
- Consumes tokens
- Produces larger AST blocks: `Module`, `Generic`, `Struct`, `Function`
- `File` is the top-level block containing all modules
- **Structure**: `parser.nim` acts as an import/export hub following Nim convention
- **Submodules**: Broken down into focused modules (see Project Structure below)

### 3. Deps Analyzer (`src/resolver/deps_analyzer.nim`)
- Assigns types to identifiers (variables, modules)
- Produces `Typed*` versions of AST nodes (e.g., `TypedModuleRef`, `TypedFunction`)
- Tracks module dependencies via `module_deps` functions

### 4. Resolver (`src/resolver.nim`)
- Performs semantic resolution
- Validates that types follow defined constraints
- Produces `Resolved*` versions of AST nodes

### 5. Codegen (`src/codegen.nim`)
- Takes resolved AST
- Performs monomorphization (instantiates generic types with concrete types)
- Generates pure C code

## Project Structure

```
src/
  aslang.nim                 # Entry point
  compiler.nim               # File I/O utilities, compilation orchestration
  resolver.nim               # Resolution phase (Resolved* types)
  resolver/
    deps_analyzer.nim        # Type assignment entry point + assign_type logic
    deps_analyzer/
      parser.nim             # Parser import/export hub + native module initialization
      parser/
        # Core parsing infrastructure
        tokenizer.nim        # Lexical analysis (Token, Location)
        core.nim             # Parser type, token specs, space/indent handling

        # Basic AST nodes
        identifier.nim       # Identifier type and parsing
        module_ref.nim       # ModuleRef type (recursive, supports generics)
        literal.nim          # Literal types (Integer, Float, String)

        # Definitions
        defs.nim             # ArgumentDefinition, FunctionDefinition, StructDefinition
        struct.nim           # Struct type with fields

        # Expressions and calls
        arg.nim              # Argument, FunctionRef, FunctionCall
        initializer.nim      # LiteralInit, StructRef, StructInit, Initializer, StructGet

        # Pattern matching
        pattern.nim          # MatchDefinition, StructPattern, CasePattern, CaseDefinition

        # Complex expressions (mutually recursive - must stay together)
        expression.nim       # Expression, Statement, Case, Else, Match

        # Functions and generics
        function.nim         # UserFunction, ExternFunction, Function (unified)
        generic.nim          # Generic type with constraints

        # Modules and files
        module.nim           # UserModuleDefinition, UserModule, NativeModule, Module, ModulePayload
        file.nim             # File type (top-level container)

      # Typed AST types (import hierarchy: file -> module -> expr -> call/init/defs/ref)
      typed_file.nim         # TypedFile - top-level typed container
      typed_module.nim       # TypedGeneric, TypedUserModule, TypedNativeModule, TypedModule
      typed_expr.nim         # TypedExpression, TypedStatement, TypedCase, TypedElse, TypedMatch, TypedFunction
      typed_call.nim         # TypedFunctionRef, TypedFunctionCall, TypedStructGet, TypedVariable
      typed_init.nim         # TypedLiteralInit, TypedStructRef, TypedStructInit, TypedInitializer
      typed_defs.nim         # TypedArgumentDefinition, TypedFunctionDefinition, TypedStruct
      typed_ref.nim          # TypedModuleRef

examples/                    # Test files (.asl)
  generic_struct.asl
  generic_union.asl
  struct.asl
  union.asl
  project-euler/             # Project Euler solutions for testing
```

### Import Hierarchies

#### Parser Layer Import Order

The parser submodules follow a dependency-ordered import pattern:

```
parser.nim (hub)
  ├── parser/tokenizer       # No dependencies
  ├── parser/core            # No dependencies
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

**Note**: `parser.nim` acts as an import/export hub. It imports all submodules and re-exports them, following the Nim convention where `<name>.nim` serves as the public interface for a `<name>/` directory.

#### Typed AST Import Hierarchy

The typed AST files follow a chain import pattern where each file imports and re-exports its dependencies:

```
deps_analyzer.nim
  └── typed_file.nim         # TypedFile
        └── typed_module.nim # TypedGeneric, TypedUserModule, TypedNativeModule, TypedModule
              └── typed_expr.nim  # TypedExpression, TypedStatement, TypedFunction, etc.
                    ├── typed_call.nim  # TypedFunctionRef, TypedFunctionCall, etc.
                    ├── typed_init.nim  # TypedLiteralInit, TypedStructInit, etc.
                    ├── typed_defs.nim  # TypedArgumentDefinition, TypedFunctionDefinition, TypedStruct
                    └── typed_ref.nim   # TypedModuleRef
```

This allows a single `import deps_analyzer/typed_file; export typed_file` to access all typed AST types.

## Coding Conventions

### File Organization
- Max 250 lines per file for readability
- Chain imports/exports - each module imports and re-exports its dependency
- Functions close to their struct definitions
- **Parser pattern**: `<name>.nim` acts as import/export hub for `<name>/` directory
- **Mutually recursive types**: Must be defined together in a single `type` block (e.g., Expression, Statement, Case, Else, Match)

### Naming Conventions
- `underscore_case` for all identifiers (never camelCase)
- Constructors: `new_<struct>`
- Properties: named after the field (e.g., `location`, `name`, `kind`)
- Extractors: named like properties with `*` export marker (`native*`, `user*`, `payload*`)
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

proc new_struct*(field_b: TypeB): Struct =
  Struct(kind: SK_VARIANT_B, field_b: field_b)

# 4. Properties - only accept struct, return value
proc location*(struct: Struct): Location = struct.location
proc kind*(struct: Struct): StructKind = struct.kind
proc field*(struct: Struct): SomeType = struct.field

# 5. Extractors - return Result for variant-specific access
proc variant_a*(struct: Struct): Result[TypeA, string] =
  case struct.kind:
  of SK_VARIANT_A: ok(struct.field_a)
  of SK_VARIANT_B: err(fmt"{struct.location} expected variant A")

# 6. Helper functions
proc find_field*(struct: Struct, name: Identifier): Result[Field, string] =
  # lookup logic
```

### Control Flow
- Always use `case` statements for checking `.kind` - never `if x.kind == ...`
- Exhaustive case handling - handle all variants explicitly

```nim
# GOOD
case module.kind:
of MK_NATIVE: # handle native
of MK_USER: # handle user

# BAD
if module.kind == MK_NATIVE:
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
import deps_analyzer/parser
export parser

import typed_ref
export typed_ref
```

### Dependency Management
- Minimize inter-module dependencies
- Export only what is needed (use `*` marker)
- Handle cyclic type dependencies by grouping in single `type` block
- **Mutually recursive types**: Define all types together in one `type` block, use forward declarations for procs

```nim
# Forward declarations for mutually recursive procs
proc location*(match: Match): Location
proc asl*(match: Match, indent: string): seq[string]
proc match_spec*(parser: Parser, indent: int): Result[Match, string]

# Mutually recursive types - all defined together
type
  Expression* = ref object of RootObj
    case kind: ExpressionKind
    of EK_MATCH: match: Match
    # ... other variants

  Statement* = ref object of RootObj
    expression: Expression
    # ...

  Match* = ref object of RootObj
    case_blocks: seq[Case]
    # ...

  Case* = ref object of RootObj
    statements: seq[Statement]
    # ...

  Else* = ref object of RootObj
    statements: seq[Statement]
    # ...
```

### Parser Module Structure

The parser follows the Nim convention where `parser.nim` serves as an import/export hub:

- **`parser.nim`**:
  - Imports and exports all submodules
  - Contains native module initialization (`native_modules()`, `new_native_error_module()`, etc.)
  - Contains main `parse()` function
  - Currently ~285 lines (down from ~793)

- **Submodules** (`parser/` directory):
  - Each focused on a specific aspect of parsing
  - All under 250 lines
  - Organized by dependency order
  - Export their types and parsing functions

## Key Types

### Parser Layer (Untyped AST)

| Type | Description |
|------|-------------|
| `File` | Top-level container for all modules |
| `Module` | Variant of `UserModule` or `NativeModule` |
| `ModulePayload` | Unified view of module data (generics, structs, functions) |
| `UserModule` | User-defined module with generics, structs, functions |
| `NativeModule` | Built-in module (U8, U16, S32, etc.) with extern functions |
| `Generic` | Generic type parameter |
| `Struct` | Data structure with fields |
| `Function` | Variant of `UserFunction` or `ExternFunction` |
| `UserFunction` | User-defined function |
| `ExternFunction` | External C function binding |

### Deps Analyzer Layer (Typed AST)

| Type | File | Description |
|------|------|-------------|
| `TypedModuleRef` | typed_ref.nim | Reference to a module with resolved children |
| `TypedArgumentDefinition` | typed_defs.nim | Function argument with type |
| `TypedFunctionDefinition` | typed_defs.nim | Function signature with typed args and return |
| `TypedStruct` | typed_defs.nim | Struct with typed fields |
| `TypedLiteralInit` | typed_init.nim | Literal initialization (integers, floats, strings) |
| `TypedStructRef` | typed_init.nim | Reference to a struct type |
| `TypedStructInit` | typed_init.nim | Struct instantiation with arguments |
| `TypedInitializer` | typed_init.nim | Variant of literal or struct initialization |
| `TypedFunctionRef` | typed_call.nim | Reference to a function |
| `TypedFunctionCall` | typed_call.nim | Function call with arguments |
| `TypedStructGet` | typed_call.nim | Field access on a struct |
| `TypedVariable` | typed_call.nim | Variable reference |
| `TypedExpression` | typed_expr.nim | Expression variant (match, fncall, init, etc.) |
| `TypedStatement` | typed_expr.nim | Assignment statement |
| `TypedCase` | typed_expr.nim | Case block in pattern matching |
| `TypedElse` | typed_expr.nim | Else block in pattern matching |
| `TypedMatch` | typed_expr.nim | Pattern matching expression |
| `TypedFunction` | typed_expr.nim | Function with typed definition and statements |
| `TypedGeneric` | typed_module.nim | Generic type parameter with function definitions |
| `TypedUserModule` | typed_module.nim | Typed user-defined module |
| `TypedNativeModule` | typed_module.nim | Typed native module with extern functions |
| `TypedNativeFunction` | typed_module.nim | Native function with extern binding |
| `TypedModule` | typed_module.nim | Unified variant of `TypedUserModule` or `TypedNativeModule` |
| `TypedFile` | typed_file.nim | Top-level container for all typed modules and functions |

### Resolver Layer (Resolved AST)

| Type | Description |
|------|-------------|
| `ResolvedDef` | Fully resolved type definition |
| `ResolvedImpl` | Generic implementation with concrete type |
| `ResolvedStruct` | Struct with resolved field types |
| `ResolvedFunction` | Function with resolved types |

## Common Patterns

### Creating Accessors for Variant Types

```nim
# For a Module variant type with MK_NATIVE and MK_USER kinds:

# Property accessor (always works)
proc kind*(module: Module): ModuleKind = module.kind

# Extractor (returns Result, may fail)
proc native*(module: Module): Result[NativeModule, string] =
  case module.kind:
  of MK_NATIVE: ok(module.native_module)
  of MK_USER: err(fmt"{module.location} expected native module")

proc user*(module: Module): Result[UserModule, string] =
  case module.kind:
  of MK_USER: ok(module.user_module)
  of MK_NATIVE: err(fmt"{module.location} expected user module")
```

### Accumulating Module Dependencies

```nim
# Helper for collecting deps from sequences
proc accumulate_module_deps[T](items: seq[T]): HashSet[UserModule] =
  var module_set: HashSet[UserModule]
  for item in items:
    module_set.incl(item.module_deps)
  module_set

# Usage
proc module_deps(function: TypedFunction): HashSet[UserModule] =
  var module_set = function.def.module_deps
  module_set.incl(accumulate_module_deps(function.steps))
  module_set
```

### Error Message Helpers

```nim
# Extract common error messages into helpers
proc err_no_default_struct(location: Location, module_name: string): string =
  fmt"{location} module `{module_name}` does not have a default struct"

# Usage
return err(err_no_default_struct(location, module.name.asl))
```

## Module Unification Pattern

The codebase uses a pattern where variant types (`UserModule`/`NativeModule`) are unified under a common type (`Module`) with accessors:

```nim
# Parser layer: Module wraps UserModule and NativeModule
type Module* = ref object of RootObj
  case kind: ModuleKind
  of MK_USER: user_module: UserModule
  of MK_NATIVE: native_module: NativeModule

# ModulePayload provides a unified view of common data
proc payload*(module: Module): ModulePayload =
  case module.kind:
  of MK_USER: new_module_payload(module.user_module)
  of MK_NATIVE: new_module_payload(module.native_module)

# Typed layer: TypedModule wraps TypedUserModule and TypedNativeModule
type TypedModule* = ref object of RootObj
  case kind: TypedModuleKind
  of TMK_USER: user: TypedUserModule
  of TMK_NATIVE: native: TypedNativeModule
```

### Avoiding Thin Wrappers

When functions need to work with both `UserModule` and `NativeModule`, use `parser.Module` instead of creating thin wrappers:

```nim
# GOOD: Single function accepting unified type
proc assign_type(file: File, module: parser.Module, ref: ModuleRef): Result[...] =
  # implementation uses module.payload for common access

# BAD: Thin wrappers that just delegate
proc assign_type(file: File, module: UserModule, ref: ModuleRef): Result[...] =
  assign_type(file, parser.new_module(module), ref)  # Don't do this

proc assign_type(file: File, module: NativeModule, ref: ModuleRef): Result[...] =
  assign_type(file, parser.new_module(module), ref)  # Don't do this
```

Only use specific types (`UserModule`, `NativeModule`) when creating typed results that require the specific type:

```nim
# These need specific types because they create TypedUserModule/TypedNativeModule
proc assign_type(file: File, module: UserModule, id: uint64): Result[TypedUserModule, string]
proc assign_type(file: File, module: NativeModule, id: uint64): Result[TypedNativeModule, string]
```

## Refactoring Guidelines

1. Max 60 lines per change - Keep changes small and verifiable
2. Always run `bash test.sh` after each change
3. Fix linter errors immediately - Do not proceed with broken code
4. One function at a time - When unifying types, migrate incrementally
5. Preserve argument order - Match order of variable existence in scope
6. Prefer `parser.Module` over `UserModule`/`NativeModule` for internal functions
7. Use chain exports - Import and re-export dependencies to minimize import statements
8. Keep files under 250 lines - Split large files following the `<name>.nim` + `<name>/` pattern
9. **Parser breakdown pattern**: When breaking down parser files:
   - Extract related types into focused modules (e.g., `parser/literal.nim` for all literal types)
   - Keep mutually recursive types together (e.g., Expression, Statement, Case, Else, Match)
   - Order imports by dependency (no dependencies first, then dependent modules)
   - Update `parser.nim` to import and export all submodules
   - Keep initialization code (like `native_modules()`) in `parser.nim` if it's specific to the parser