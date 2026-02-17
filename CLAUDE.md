# CLAUDE.md - ASLang Compiler Project Guide

## Project Overview

ASLang (A Software Language) is a compiler for a new programming language designed for zero-maintenance systems. It targets readability, security, performance, and software architecture by turning common architectural patterns into single-line declarations instead of boilerplate code.

- **Compiler language:** Nim (2.2.0)
- **Source files:** `.asl`
- **Target:** C code, then compiled to native executables via GCC
- **Runtime:** Custom C runtime library (`runtime.c` / `runtime.h`)
- **Codebase:** ~9,100 lines of Nim across 90 source files

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

- **Documentation examples** (`examples/docs/`): `struct.asl`, `union.asl`, `generic_struct.asl`, `generic_union.asl`, `nested_expr.asl`, `reassignment.asl`
- **Project Euler solutions** (`examples/project-euler/`): `problem001.asl` through `problem010.asl`

### Memory Sanitization

```bash
# Run AddressSanitizer + leak detection on all examples
bash sanitize.sh
# macOS: uses `leaks --atExit` for leak detection
# Linux: uses LeakSanitizer via ASAN_OPTIONS=detect_leaks=1
```

## Compilation Pipeline

```
Source (.asl) → Tokenizer → Parser → Expander → Resolver → Analyzer → Lowering → Optimizer → Emitter → C Code → GCC → Binary
```

The pipeline is implemented as a clean chain in `src/compiler.nim`:

```nim
let tokens = ? tokenize(filename, content)
let file = ? parse(filename, tokens)
let expanded = ? expand(file)
let resolved_file = ? resolve(expanded)
let analyzed_file = ? analyze(resolved_file)
let program = ? generate(analyzed_file)
let optimized = optimize(program)
let code = emit(optimized)
```

### 1. Tokenizer (`src/frontend/tokenizer.nim` + `tokenizer/`)
- Reads raw source files and converts text into tokens
- Token types: operators, brackets, literals (string, digits, alphabets), whitespace, comments
- Tracks source location (filename, line, column, index) for error reporting
- Key function: `tokenize(filename, content) -> Result[seq[Token], string]`

### 2. Parser (`src/frontend/parser.nim` + `parser/`)
- Consumes tokens and produces unresolved AST
- Top-level type: `File` containing modules and file-level functions
- Modules contain generics, data (struct or union), and functions
- `parser.nim` acts as an import/export hub following Nim convention
- Key function: `parse(path, tokens) -> Result[File, string]`

### 3. Expander (`src/frontend/expander.nim` + `expander/`)
- Desugaring pass between parser and resolver
- Expands struct/union shorthand into canonical form
- Generates implicit functions (e.g., `byte_size`, `read`, `write` for structs)
- Key function: `expand(file) -> Result[File, string]`

### 4. Resolver (`src/middle/resolver.nim` + `resolver/`)
- Assigns types to identifiers (variables, modules)
- Produces `Resolved*` versions of AST nodes
- Tracks module dependencies and detects circular dependencies
- Performs topological sort of modules for resolution order
- Validates numeric literal ranges for target types
- Key function: `resolve(file) -> Result[ResolvedFile, string]`

### 5. Analyzer (`src/middle/analyzer.nim` + `analyzer/`)
- Performs semantic analysis and validation
- Validates that types follow defined constraints
- Produces `Analyzed*` versions of AST nodes
- Performs monomorphization (instantiates generic types with concrete types)
- Computes `FunctionMetadata` for user functions (via `func_metadata.nim`) and data functions (via `data_metadata.nim`)
- Key function: `analyze(resolved_file) -> Result[AnalyzedFile, string]`

### 6. Lowering (`src/backend/lowering.nim` + `lowering/`)
- Converts Analyzed* types to C IR nodes (`CProgram`)
- Assembles complete C programs with includes, typedefs, forward declarations, and definitions
- Adds runtime function metadata (from `runtime_metadata.nim`) to the C IR program
- Key function: `generate(analyzed_file) -> Result[CProgram, string]`

### 7. Optimizer (`src/backend/optimizer.nim` → `lifetime.nim` → `lifetime/`)
- Scope-based lifetime analysis on C IR
- Injects `free()` calls for heap-allocated values at scope exit
- **Two-pass architecture:**
  - Pass 1: Infers function metadata from C IR call sites (fills gaps from analyzer metadata)
  - Pass 2: Walks C IR statements, tracks allocations per scope, generates frees
- **Status match lifetime handling:** OWNED Status matches get per-branch freeing (Ok branches: extractions + shell freed; else branches: inner-free + shell freed if status doesn't escape)
- **TCO-aware free placement:** Detects tail-call patterns and inserts frees before the tail call to preserve GCC/Clang tail-call optimization
- **Reassignment tracking:** Frees old value before variable reassignment of allocated variables
- Key function: `optimize(program) -> CProgram`

### 8. Emitter (`src/backend/emitter.nim`)
- Serializes C IR to C source strings
- Recursive `emit` procs for each C IR type (CType, CExpr, CStmt, CDecl, CProgram)
- Key function: `emit(program) -> string`

## Project Structure

```
src/
  aslang.nim                    # CLI entry point (arg parsing, invokes compile)
  compiler.nim                  # Compilation orchestration (tokenize → parse → expand → resolve → analyze → generate → optimize → emit → gcc)
  metadata.nim                  # Shared metadata types: FunctionMetadata, AllocKind
  temp_counter.nim              # Temporary variable counter for codegen

  # --- Frontend: Source → AST ---
  frontend/
    tokenizer.nim               # Tokenizer hub + tokenize()
    tokenizer/
      location.nim              # Source position tracking (Location, Cursor)
      cursor.nim                # Character cursor
      token.nim                 # Token type (kind, value, location)
      spec.nim                  # Token specifications (matchers)
      constants.nim             # Operator/special character definitions
      error.nim                 # Tokenizer errors
    parser.nim                  # Parser hub + parse()
    parser/
      core.nim                  # Parser infrastructure (Parser type, indent/space handling, combinators)
      repo.nim                  # Repo[T] - flexible indexed lookups with duplicate detection
      identifier.nim            # Identifier type and parsing
      module_ref.nim            # ModuleRef (recursive, supports generics like Array[Item])
      literal.nim               # Literal types (IntegerLiteral, FloatLiteral, StringLiteral)
      defs.nim                  # StructDefinition, ArgumentDefinition, FunctionDefinition
      struct.nim                # Struct, UnionBranch, Union, Data
      struct_ref.nim            # StructRef parsing
      arg.nim                   # Argument, FunctionCall
      function_ref.nim          # FunctionRef parsing
      initializer.nim           # LiteralInit, StructRef, StructInit, Initializer, StructGet
      pattern.nim               # MatchDefinition, StructPattern, CasePattern, CaseDefinition
      expression.nim            # Expression, Statement, Case, Else, Match (mutually recursive)
      generic.nim               # Generic type (default or constrained with function defs)
      function.nim              # UserFunction, ExternFunction, Function
      module.nim                # Module (generics, data, functions)
      file.nim                  # File (top-level container)
    expander.nim                # Expander hub + expand()
    expander/
      expand_file.nim           # File-level expansion
      expand_expression.nim     # Expression expansion
      expand_struct.nim         # Struct expansion (implicit function generation)
      expand_union.nim          # Union expansion (implicit function generation)

  # --- Middle: Semantic Analysis ---
  middle/
    resolver.nim                # Resolver hub + resolve() + cycle detection + literal validation
    resolver/
      module_ref.nim            # ResolvedModuleRef
      defs.nim                  # ResolvedArgumentDefinition, ResolvedFunctionDefinition, ResolvedStruct, ResolvedData
      fncall.nim                # ResolvedFunctionRef, ResolvedFunctionCall, ResolvedStructGet, ResolvedVariable
      initializer.nim           # ResolvedLiteralInit, ResolvedStructRef, ResolvedStructInit, ResolvedInitializer
      expression.nim            # ResolvedExpression, ResolvedStatement, ResolvedUserFunction, ResolvedFunction
      module.nim                # ResolvedGeneric, ResolvedModule
      file.nim                  # ResolvedFile
    analyzer.nim                # Analyzer hub (imports and re-exports all analyzer modules)
    analyzer/
      module_ref.nim            # AnalyzedModuleRef, AnalyzedImpl (generic instantiation)
      arg_def.nim               # AnalyzedArgumentDefinition
      arg.nim                   # Argument analysis
      struct.nim                # AnalyzedStruct, AnalyzedUnionBranch, AnalyzedUnion, AnalyzedData
      struct_ref.nim            # AnalyzedStructRef, AnalyzedUnionRef, AnalyzedDataRef
      struct_init.nim           # AnalyzedStructInit
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
      data_metadata.nim         # compute_data_metadata: struct/union function metadata (byte_size, read, write, init, get, set)
      func_metadata.nim         # compute_user_metadata: user function metadata with match walking + allocated_vars tracking

  # --- Backend: C IR + Code Generation ---
  backend/
    ir/
      types.nim                 # CType, CExpr, CStmt, CDecl, CProgram (C intermediate representation)
      constructors.nim          # Pure constructors: c_void, c_named, c_call, c_if, c_program, etc.
    lowering.nim                # Lowering hub + generate()
    lowering/
      lower_file.nim            # Top-level CProgram assembly + runtime metadata merging
      lower_file_def.nim        # File-level typedefs/decls/defs
      lower_module.nim          # Generic dispatch switch generation
      lower_module_def.nim      # Module typedefs/decls/defs
      lower_function.nim        # User function → C IR
      lower_expression.nim      # Expression/statement/match/case → C IR
      lower_fncall.nim          # Function call → C IR (boxing, impl_id dispatch)
      lower_initializer.nim     # Struct/literal initialization → C IR
      lower_struct.nim          # Struct/union/data → C IR (get/set/init/byte_size/read/write)
      lower_func_def.nim        # Function name/declaration generation
      lower_generic.nim         # Generic forward declarations
      lower_module_ref.nim      # Module ref → CType/byte_size
      lower_arg_def.nim         # Argument definition → C parameter
      lower_arg.nim             # Argument → C expression
      lower_struct_ref.nim      # Data ref name generation
      lower_literal.nim         # Literal typedef/init generation
    optimizer.nim               # Optimizer hub
    lifetime.nim                # Lifetime hub
    lifetime/
      analysis.nim              # Tree traversal: optimize_stmts, optimize_if, TCO detection, Status match handling
      scope.nim                 # Scope-based tracking: allocations, consumed, reassignments, free generation
      runtime_metadata.nim      # Static FunctionMetadata for runtime C functions (System_*, Array_*, String_*, etc.)
    emitter.nim                 # Recursive C IR → string serializers (emit procs)

examples/
  docs/                         # Language feature examples (6 files)
    struct.asl                  # Struct definitions and usage
    union.asl                   # Discriminated unions
    generic_struct.asl          # Generic struct instantiation
    generic_union.asl           # Generic union patterns
    nested_expr.asl             # Nested expressions
    reassignment.asl            # Variable reassignment
  project-euler/                # Project Euler solutions (10 files)
    problem001.asl - problem010.asl

runtime.c                       # C runtime library implementation
runtime.h                       # C runtime type definitions
test.sh                         # Test runner script
sanitize.sh                     # Memory sanitization validation (ASan + leak detection)
aslang.nimble                   # Nim package manifest
```

### Import Hierarchies

#### Frontend Layer

```
frontend/tokenizer.nim (hub)
  ├── tokenizer/location        # Source position tracking
  ├── tokenizer/cursor          # Character cursor
  ├── tokenizer/token           # Token type
  ├── tokenizer/spec            # Token matchers
  ├── tokenizer/constants       # Operators/special chars
  └── tokenizer/error           # Tokenizer errors

frontend/parser.nim (hub - imports tokenizer + all parser submodules)
  ├── parser/core               # Parser infrastructure
  ├── parser/repo               # Indexed lookups
  ├── parser/identifier         # Depends on core
  ├── parser/module_ref         # Depends on identifier, core
  ├── parser/defs               # Depends on identifier, module_ref, core
  ├── parser/literal            # Depends on identifier, core
  ├── parser/struct             # Depends on defs, identifier, module_ref, core
  ├── parser/struct_ref         # Depends on identifier, module_ref, core
  ├── parser/arg                # Depends on identifier, module_ref, literal, core
  ├── parser/function_ref       # Depends on identifier, module_ref, core
  ├── parser/initializer        # Depends on identifier, module_ref, literal, arg, core
  ├── parser/pattern            # Depends on identifier, literal, core
  ├── parser/expression         # Depends on identifier, arg, initializer, pattern, core
  ├── parser/generic            # Depends on identifier, module_ref, defs, core
  ├── parser/function           # Depends on identifier, module_ref, defs, expression, core
  ├── parser/module             # Depends on identifier, module_ref, defs, struct, generic, function, core
  └── parser/file               # Depends on module, function, core

frontend/expander.nim (hub)
  └── expander/expand_file      # Imports expand_expression, expand_struct, expand_union
```

#### Middle Layer

```
middle/resolver.nim (hub - imports frontend/parser, all resolver submodules)
  ├── resolver/module_ref       # ResolvedModuleRef
  ├── resolver/defs             # ResolvedArgumentDefinition, ResolvedFunctionDefinition, ResolvedStruct, ResolvedData
  ├── resolver/fncall           # ResolvedFunctionRef, ResolvedFunctionCall, ResolvedStructGet, ResolvedVariable
  ├── resolver/initializer      # ResolvedLiteralInit, ResolvedStructRef, ResolvedStructInit, ResolvedInitializer
  ├── resolver/expression       # ResolvedExpression, ResolvedStatement, ResolvedUserFunction, ResolvedFunction
  ├── resolver/module           # ResolvedGeneric, ResolvedModule
  └── resolver/file             # ResolvedFile

middle/analyzer.nim (hub - imports resolver, all analyzer submodules)
  ├── analyzer/module_ref       # AnalyzedModuleRef, AnalyzedImpl
  ├── analyzer/arg_def          # AnalyzedArgumentDefinition
  ├── analyzer/func_def         # AnalyzedFunctionDefinition
  ├── analyzer/expression       # AnalyzedExpression, AnalyzedStatement, AnalyzedMatch
  ├── analyzer/function         # AnalyzedUserFunction, AnalyzedFunction (calls compute_user_metadata)
  ├── analyzer/module           # AnalyzedModule
  ├── analyzer/module_def       # AnalyzedModuleDefinition
  ├── analyzer/file_def         # AnalyzedFileDefinition, FunctionScope
  ├── analyzer/file             # AnalyzedFile
  ├── analyzer/data_metadata    # compute_data_metadata (struct/union function metadata)
  ├── analyzer/func_metadata    # compute_user_metadata (user function metadata with match walking)
  └── ... (remaining analyzer files)
```

#### Backend Layer

```
backend/lowering.nim (hub)
  └── lowering/lower_file.nim   # Entry point: generate() → Result[CProgram, string]
      → lower_file_def          # File typedefs/decls/defs
      → lower_module            # Generic dispatch generation
        → lower_module_def      # Module typedefs/decls/defs
      → lower_function          # User function generation
        → lower_expression      # Expression/statement/match generation
          → lower_fncall        # Function call generation
          → lower_initializer   # Initialization generation
      → lower_struct            # Struct/union C code generation
      → lower_func_def          # Function name/declaration
      → lower_generic           # Generic forward declarations
      → lower_module_ref        # Type/byte_size from module ref
      → lower_arg_def, lower_arg  # Argument generation
      → lower_struct_ref        # Data ref naming
      → lower_literal           # Literal type/init

backend/optimizer.nim → lifetime.nim → lifetime/analysis.nim
  └── lifetime/scope.nim        # Scope construction + free generation
  └── lifetime/runtime_metadata.nim  # Static metadata for runtime functions

backend/emitter.nim             # CProgram → string (recursive emit procs)

backend/ir/types.nim            # C IR type definitions
backend/ir/constructors.nim     # C IR constructors
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
| `AnalyzedFunctionDefinition` | Concrete function signature with metadata |
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

### Shared Metadata Types (`src/metadata.nim`)

| Type | Description |
|------|-------------|
| `AllocKind` | `AK_PLAIN` (heap alloc), `AK_STATUS_OWNED` (Status with owned inner pointer), `AK_STATUS_BORROWED` (Status with borrowed inner pointer) |
| `FunctionMetadata` | Analysis flags: `allocates`, `mutates_args`, `reads_only`, `returns_allocated`, `alloc_kind`, `consumes_args`, `is_union_extraction` |

### C IR Layer (Intermediate Representation)

| Type | Description |
|------|-------------|
| `CType` | C type: void, named, pointer, const_pointer |
| `CExpr` | C expression: literal, ident, call, binary, cast |
| `CStmt` | C statement: decl, assign, return, expr, if, switch, block, comment, raw |
| `CDecl` | C declaration: typedef, func_decl, func_def, extern, include |
| `CProgram` | Complete C program: includes, typedefs, forward_decls, definitions, main, metadata |

## Optimizer Details

The optimizer (`src/backend/lifetime/`) performs scope-based lifetime analysis on the C IR to inject memory management.

### Scope Analysis (`scope.nim`)
- Tracks: `allocations` (variables that own heap memory), `consumed` (variables whose ownership transferred), `alloc_kinds` (AllocKind per variable), `reassign_frees` (frees before variable reassignment)
- Allocation detection: `_init` calls, `System_box_*`, `System_allocate`, and calls to functions with `returns_allocated` metadata
- Consumption detection: variables used as function call arguments (to consuming functions), direct aliasing (`y = x`), and variables inside if/switch/block bodies
- OWNED Status match variables are marked consumed at parent scope (freed per-branch by `optimize_if`)

### Status Match Lifetime (`analysis.nim`)
- Detects `if(status->id == TAG)` patterns as Status match arms
- Ok branches: extractions (via `_get_value` calls) + status shell tracked as `extra_allocs`
- Else branches: if status doesn't escape (not returned/aliased), injects `free(inner_pointer)` + `free(shell)`
- Alias-aware escape detection: checks both direct exit and aliased exit patterns

### TCO-Aware Free Placement (`analysis.nim`)
- `find_tail_call_idx`: detects when the scope's exit variable is produced by a function call (tail-call candidate)
- Frees are inserted BEFORE the tail call declaration, enabling GCC/Clang to apply tail-call optimization
- Critical for deeply recursive functions (e.g., `mark_non_prime` in problem003 with ~387K recursions)
- Uses standard `free()` (not `System_free`) so GCC recognizes known semantics and can reorder

### Metadata Flow
1. **Analyzer level** (`func_metadata.nim`): `compute_user_metadata` walks analyzed AST, tracking `allocated_vars` set to detect functions that return allocated values through match branches
2. **Lowering level** (`lower_file.nim`): Merges analyzer metadata with runtime metadata from `runtime_metadata.nim`
3. **Optimizer level** (`analysis.nim`): `collect_metadata` infers remaining gaps from C IR call sites

### Known Limitation: Analyzer Metadata Gap
The analyzer doesn't have access to runtime function metadata (e.g., `Array_get.returns_allocated = true` from `runtime_metadata.nim`). This means user functions that call extern allocators through match patterns may not get correct `returns_allocated` at the analyzer level. The optimizer's `collect_metadata` partially compensates at the C IR level, but only for functions not already in the metadata table.

## Common Patterns

### Repo Pattern

`Repo[T]` provides flexible indexed lookups with multiple composite indexes, duplicate detection, and name/hash-based access. Used for functions, generics, fields, and module lookups at both parser and resolver layers.

### Error Message Helpers

```nim
proc err_no_default_struct(location: Location, module_name: string): string =
  fmt"{location} module `{module_name}` does not have a default struct"
```

### Monomorphization

Generic modules are instantiated per concrete type usage. The analyzer collects all implementations (`AnalyzedImpl`) from usage sites, then the lowering generates separate C code for each concrete instantiation.

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

- **Type mappings**: `S8`->`int8_t`, `U64`->`uint64_t`, `String`->`char*`, `Pointer`->`uintptr_t`, etc.
- **Memory**: `System_allocate`, `System_free`, `System_box_*`
- **I/O**: `System_print_*` for all primitive types
- **Arithmetic**: `add`, `subtract`, `multiply`, `quotient`, `remainder` for numeric types
- **Comparison**: `compare` returning S8 (-1, 0, 1)
- **Bitwise**: `lshift`, `rshift`, `and`, `or`, `not`
- **Type conversion**: `from` functions (e.g., `S64_from_U8`)
- **Memory access**: `byte_size`, `read`, `write` for all types
- **String**: `String_get` returning `Status[U8]`
- **Array**: `Array_init`, `Array_set`, `Array_get` with Status-based error handling

Note: `Pointer` in generated C is `typedef uintptr_t Pointer` (unsigned long), NOT `void*`. The optimizer casts to `(void*)` when calling standard `free()`.

## Architectural Recommendations

If reimplementing from scratch, these are the major changes guided by four fundamental principles.

### Principle 1: Pure Functions

**Current violations:**
- `FunctionScope.set()` mutates the table in-place AND returns self — callers can't tell if they hold a shared or independent reference
- `generic_impls` merge pattern creates a new Table on every call via mutable accumulation

**Recommendations:**
- Make `FunctionScope` immutable — `with()` returns a new scope instead of mutating in-place
- Return values from tree traversals instead of accumulating via `var` parameters
- Use `concat` / `fold` instead of `var seq + .add()` where the output shape is simple

### Principle 2: Side Effects on the Outermost Layer

**Current state:** compiler.nim already isolates I/O (file read/write, gcc exec) from the pure pipeline (tokenize → parse → expand → resolve → analyze → generate → optimize → emit). Strong foundation.

**Recommendation:** Push the last side effect (`exec_cmd` for gcc) out of compiler.nim into aslang.nim. Return a `CompilationResult` (c_code, output_file, command) from the pure pipeline — aslang.nim handles file writes and process execution. This makes the entire compiler testable without filesystem or process side effects.

### Principle 3: Making Invalid States Unreachable

**Current weaknesses:**
1. Variant accessors use runtime `do_assert` — calling `.match()` on an `EK_VARIABLE` crashes at runtime, not compile time
2. Direct object construction bypasses constructors — `Expression(kind: EK_MATCH, variable: id)` compiles
3. Error types degrade at layer boundaries — `parse()` converts `Result[T, Error]` to `Result[T, string]`, losing structured info

**Recommendations:**
- Use typed errors at every boundary — `TokenError`, `ParseError`, `ResolveError` instead of degrading to `string`
- Introduce a `visit` proc pattern that forces exhaustive handling instead of `do_assert` accessor pattern

### Principle 4: Spatial and Temporal Locality

**Current violations:**
1. Understanding "modules" requires reading `parser/module.nim`, `resolver/module.nim`, `analyzer/module.nim`, and `lowering/lower_module.nim` — 4 files across 3 directories
2. `analyzer.nim` hub imports and re-exports 22+ modules — no visible structure

**Recommendations:**
- Organize by domain concept instead of compiler phase: `src/module/` contains `types.nim`, `parse.nim`, `resolve.nim`, `analyze.nim`, `lower.nim`
- Replace `Repo[T]` (125-line generic B-tree index) with simple `validate_unique` + `seq[T]` with `filter_it` — collections never exceed 20 items
