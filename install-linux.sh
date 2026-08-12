#!/usr/bin/env bash
set -euo pipefail

repo="wesleybasso/redfox-ai-orchestrator"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd || pwd)"
source_root="$script_dir"
temporary_root=""

for ((i=1; i<=$#; i++)); do
  if [[ "${!i}" == "--source-root" ]]; then
    next=$((i + 1))
    source_root="${!next}"
  fi
done

cleanup() {
  if [[ -n "$temporary_root" && -d "$temporary_root" ]]; then
    rm -rf -- "$temporary_root"
  fi
}
trap cleanup EXIT

if [[ ! -f "$source_root/redfox-local/install-linux.sh" ]]; then
  command -v curl >/dev/null 2>&1 || { echo 'curl e obrigatorio para baixar a RedFox.' >&2; exit 1; }
  command -v tar >/dev/null 2>&1 || { echo 'tar e obrigatorio para baixar a RedFox.' >&2; exit 1; }
  temporary_root="$(mktemp -d)"
  echo 'Baixando a RedFox do GitHub...'
  curl -fsSL "https://github.com/$repo/archive/refs/heads/main.tar.gz" | tar -xz -C "$temporary_root"
  source_root="$(find "$temporary_root" -mindepth 1 -maxdepth 1 -type d | head -n 1)"
fi

bash "$source_root/redfox-local/install-linux.sh" "$@" --source-root "$source_root"
