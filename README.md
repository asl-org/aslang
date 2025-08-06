# ASLang

**A Software Language** — a modern, minimal, and expressive programming language designed for learning, experimenting, and building.
This repository contains the official compiler for ASLang, named **`asl`**.

---

## 💡 About the Language

ASLang (short for *A Software Language*, pronounced _“a slang”_) is a small, statically typed language with a focus on clarity and simplicity. It's ideal for:

- Writing interpretable or compiled code with minimal syntax
- Exploring compiler design principles
- Creating DSLs or educational tools

The language is still under active development and is **not stable** yet — feedback and contributions are welcome!

---

## 🛠️ About the Compiler: `asl`

The `asl` compiler is written in [Nim](https://nim-lang.org/) and follows a traditional 4-phase compilation pipeline:

### 🔧 Compilation Phases

1. **Tokenization**
   Lexical analysis that converts source code into tokens.

2. **Parsing**
   Builds an abstract syntax tree (AST) from tokens using ASLang grammar.

3. **Resolution**
   Builds an type resolved abstract syntax tree (AST) from raw AST.

4. **Code Generation**
   Translates the Resolved AST into target code (planned: Nim or C backend, possibly WASM in the future).

---

## 📦 Installation & Build

### ✅ Prerequisites

- `git`
- `curl`

```bash
# Clone
git clone https://github.com/yourname/aslang.git
cd aslang

# Bootstrap
chmod +x bootstrap.sh
./bootstrap.sh

# Memory leak detection, see script content for usage instructions.
chmod +x memcheck.sh
./memcheck.sh

# Run tests
chmod +x test.sh
./test.sh

# Compile
asl -o=example example.asl
```
