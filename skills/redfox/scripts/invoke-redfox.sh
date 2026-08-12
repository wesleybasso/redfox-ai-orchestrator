#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
task=''
repo="$PWD"
target_paths='.'
mode='auto'
dry_run=0
json=0

while (($#)); do
  case "$1" in
    --task|-t) task="$2"; shift 2 ;;
    --repo) repo="$2"; shift 2 ;;
    --target-paths) target_paths="$2"; shift 2 ;;
    --mode) mode="$2"; shift 2 ;;
    --dry-run) dry_run=1; shift ;;
    --json) json=1; shift ;;
    *) echo "Opcao desconhecida: $1" >&2; exit 2 ;;
  esac
done

[[ -n "$task" ]] || { echo 'Use --task para informar a missao.' >&2; exit 2; }
command -v pwsh >/dev/null 2>&1 || { echo 'PowerShell 7 (pwsh) e necessario para executar a RedFox.' >&2; exit 1; }

args=(-NoProfile -File "$script_dir/invoke-redfox.ps1" -Task "$task" -Repo "$repo" -TargetPaths "$target_paths" -Mode "$mode")
((dry_run)) && args+=(-DryRun)
((json)) && args+=(-Json)
exec pwsh "${args[@]}"
