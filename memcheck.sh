#!/bin/bash

# ------------------------------------------------------------------------------
# 🧠 Memory Leak Detection Script: memcheck.sh
#
# This script provides a cross-platform way to automatically detect memory leaks,
# use-after-free errors, and buffer overflows using Valgrind or AddressSanitizer.
#
# 🔧 FEATURES:
# - Compiles a given .c file with debug info
# - Detects and uses Valgrind if available (with auto-install on Linux)
# - Falls back to AddressSanitizer (ASan) if Valgrind is missing or unsupported
# - Cleans up build artifacts ONLY if no memory issues are found
# - Auto-cleans leftovers from previous runs if fixed
#
# ------------------------------------------------------------------------------
#
# 🚀 USAGE:
#   ./memcheck.sh [--keep] <path/to/file.c>
#
# ------------------------------------------------------------------------------
#
# ⚙️ COMMAND-LINE FLAGS:
#
#   <path>      Required. Path to the C source file.
#   --keep      Optional. Prevents automatic cleanup, even when no errors are found.
#
# ------------------------------------------------------------------------------
#
# 🧼 CLEANUP BEHAVIOR:
#
#   ✅ No memory issues:      Artifacts are cleaned up (unless --keep is used)
#   ❌ Memory issues found:   Artifacts are preserved for debugging
#   🧹 Re-run after fix:      Leftover files from last failed run are auto-cleaned
#
# ------------------------------------------------------------------------------
#
# 📦 OUTPUT STRUCTURE:
#
#   memcheck_temp_<name>.out     # Compiled binary
#   memcheck_temp_<name>.out.dSYM/  # macOS debug symbols
#   logs/valgrind.log            # Valgrind memory check log
#   logs/asan_output.log         # ASan output log
#
# ------------------------------------------------------------------------------
#
# 📋 EXAMPLES:
#
#   ./memcheck.sh generated.c
#   ./memcheck.sh --keep generated.c
#
# ------------------------------------------------------------------------------

set -e

SRC="$1"
KEEP_MODE=0
CLEAN_FLAG=".cleanup.flag"
BIN=""
LOG_DIR="logs"
LOG="$LOG_DIR/valgrind.log"
ASAN_LOG="$LOG_DIR/asan_output.log"
ERRORS_FOUND=0

# ---------- Option Handling ----------
if [[ "$SRC" == "--keep" ]]; then
  KEEP_MODE=1
  SRC="$2"
elif [[ "$2" == "--keep" ]]; then
  KEEP_MODE=1
fi

# ---------- Helpers ----------

print_usage() {
  echo "Usage: $0 [--keep] <path/to/source.c>"
  exit 1
}

error_exit() {
  echo "❌ Error: $1"
  exit 1
}

check_command() {
  if ! command -v "$1" &>/dev/null; then
    error_exit "'$1' is required but not installed"
  fi
}

get_os_type() {
  case "$OSTYPE" in
    linux*) echo "linux" ;;
    darwin*) echo "macos" ;;
    *) echo "unsupported" ;;
  esac
}

is_valgrind_supported_on_mac() {
  if [[ "$(get_os_type)" == "macos" ]]; then
    local OS_VER MAJOR MINOR
    OS_VER=$(sw_vers -productVersion)
    MAJOR=$(echo "$OS_VER" | cut -d. -f1)
    MINOR=$(echo "$OS_VER" | cut -d. -f2)
    if (( MAJOR == 10 && MINOR <= 14 )); then
      return 0
    fi
  fi
  return 1
}

cleanup() {
  if [[ "$KEEP_MODE" -eq 1 ]]; then
    echo "🧩 --keep flag set, skipping cleanup."
    return
  fi

  if [[ "$ERRORS_FOUND" -eq 0 ]]; then
    echo "🧹 No memory issues detected. Cleaning up..."

    [[ -f "$BIN" ]] && echo "  🔸 Removing binary: $BIN" && rm -f "$BIN"
    [[ -d "$BIN.dSYM" ]] && echo "  🔸 Removing debug symbols: $BIN.dSYM" && rm -rf "$BIN.dSYM"
    [[ -f "$LOG" ]] && echo "  🔸 Removing Valgrind log: $LOG" && rm -f "$LOG"
    [[ -f "$ASAN_LOG" ]] && echo "  🔸 Removing ASan log: $ASAN_LOG" && rm -f "$ASAN_LOG"
    [[ -f "$CLEAN_FLAG" ]] && rm -f "$CLEAN_FLAG"
  else
    echo "⚠️ Memory issues detected. Preserving build artifacts for debugging."
    touch "$CLEAN_FLAG"
  fi
}

# ---------- Main Logic ----------

trap cleanup EXIT

[[ -z "$SRC" ]] && print_usage
[[ ! -f "$SRC" ]] && error_exit "File '$SRC' not found"

mkdir -p "$LOG_DIR"

# Clean leftover files from last failed run
if [[ -f "$CLEAN_FLAG" && "$KEEP_MODE" -eq 0 ]]; then
  echo "🧼 Cleaning up leftovers from previous run..."
  cleanup
fi

OS=$(get_os_type)
[[ "$OS" == "unsupported" ]] && error_exit "Unsupported OS: $OSTYPE"

BASENAME=$(basename "$SRC" .c)
BIN="memcheck_temp_$BASENAME.out"

echo "🛠️ Compiling '$SRC'..."

if [[ "$OS" == "linux" ]]; then
  if ! command -v gcc &>/dev/null; then
    echo "⚠️ 'gcc' not found, trying 'clang'..."
    check_command clang
    clang -g "$SRC" -o "$BIN"
  else
    gcc -g "$SRC" -o "$BIN"
  fi
elif [[ "$OS" == "macos" ]]; then
  check_command clang
  clang -g "$SRC" -o "$BIN"
else
  error_exit "Unsupported OS type."
fi

try_valgrind() {
  echo "🚀 Running Valgrind..."
  if ! command -v valgrind &>/dev/null; then
    echo "⚠️ Valgrind not found."
    return 1
  fi

  if ! valgrind \
    --leak-check=full \
    --show-leak-kinds=all \
    --track-origins=yes \
    --verbose \
    --log-file="$LOG" \
    "./$BIN"; then
    ERRORS_FOUND=1
    return 2
  fi

  echo
  echo "✅ Valgrind Leak Summary:"
  grep -E "definitely lost|indirectly lost|possibly lost|still reachable" "$LOG" | tee /dev/stderr | grep -q '[1-9][0-9]* bytes' && ERRORS_FOUND=1
  echo "📄 Full log written to: $LOG"
  return 0
}

run_asan() {
  echo "🧪 Running AddressSanitizer (ASan)..."
  check_command clang
  clang -fsanitize=address -g "$SRC" -o "$BIN"

  echo
  OS_TYPE="$(get_os_type)"
  if [[ "$OS_TYPE" == "linux" ]]; then
    ASAN_OPTIONS=detect_leaks=1 ./"$BIN" 2>&1 | tee "$ASAN_LOG" | grep -q "leaked in" && ERRORS_FOUND=1
  elif [[ "$OS_TYPE" == "macos" ]]; then
    echo "⚠️ LeakSanitizer is not supported on macOS. Only use-after-free and buffer errors will be reported."
    ./"$BIN" 2>&1 | tee "$ASAN_LOG" | grep -E "AddressSanitizer:|runtime error:" && ERRORS_FOUND=1
  else
    echo "❌ Unsupported OS: $OS_TYPE"
    exit 1
  fi
}

install_valgrind_linux() {
  echo "🔧 Installing Valgrind..."
  if command -v apt &>/dev/null; then
    sudo apt update && sudo apt install -y valgrind
  elif command -v dnf &>/dev/null; then
    sudo dnf install -y valgrind
  elif command -v pacman &>/dev/null; then
    sudo pacman -Sy --noconfirm valgrind
  else
    echo "⚠️ Unsupported package manager. Cannot auto-install Valgrind."
    return 1
  fi
}

# ---------- Run Tools ----------

if [[ "$OS" == "linux" ]]; then
  try_valgrind || {
    echo "⚠️ Valgrind failed or not found. Trying to install..."
    install_valgrind_linux && try_valgrind || run_asan
  }
elif [[ "$OS" == "macos" ]]; then
  if is_valgrind_supported_on_mac; then
    try_valgrind || run_asan
  else
    echo "⚠️ macOS version does not support Valgrind reliably. Using ASan."
    run_asan
  fi
fi
