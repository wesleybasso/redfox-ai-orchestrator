#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
runtime="${TMPDIR:-/tmp}/redfox-pwsh-7.6.3"
if [[ ! -x "$runtime/pwsh" ]]; then
  mkdir -p "$runtime"
  curl -fsSL https://github.com/PowerShell/PowerShell/releases/download/v7.6.3/powershell-7.6.3-linux-x64.tar.gz | tar -xz -C "$runtime"
  chmod +x "$runtime/pwsh"
fi
PATH="$runtime:$PATH" bash "$ROOT/tests/linux-pwsh.Tests.sh"
