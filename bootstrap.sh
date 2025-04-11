#!/usr/bin/env bash
set -euo pipefail

echo "📦 Bootstrapping Nim environment..."

# --- Detect OS + CPU info ---
OS="$(uname -s)"
ARCH="$(uname -m)"

echo "🔍 Detected platform: $OS ($ARCH)"

# --- Ensure choosenim is installed ---
if ! command -v choosenim &> /dev/null; then
  echo "🚀 Installing choosenim..."
  curl https://nim-lang.org/choosenim/init.sh -sSf | sh -s -- -y
else
  echo "✅ choosenim already installed"
fi

# --- Ensure PATH is updated ---
export PATH="$HOME/.nimble/bin:$PATH"

# --- Install specific Nim version ---
echo "🔧 Installing Nim 2.2.0..."
choosenim 2.2.0

# --- Verify installation ---
echo "🧪 Nim version:"
nim -v

# --- Install project dependencies ---
echo "📦 Installing nimble packages..."
nimble install -y

# --- Build the compiler ---
echo "🔨 Building..."
nimble build

echo "✅ Done!"
