#!/usr/bin/env bash
set -euo pipefail

script_source="${BASH_SOURCE[0]:-$0}"
script_dir="$(cd "$(dirname "$script_source")" 2>/dev/null && pwd || pwd)"
source_root="$script_dir"
user_home="${HOME:?HOME nao definido}"
dry_run=0
temporary_root=''

while (($#)); do
  case "$1" in
    --source-root) source_root="$2"; shift 2 ;;
    --home) user_home="$2"; shift 2 ;;
    --dry-run) dry_run=1; shift ;;
    *) echo "Opcao desconhecida: $1" >&2; exit 2 ;;
  esac
done

cleanup() {
  if [[ -n "$temporary_root" && -d "$temporary_root" ]]; then
    rm -rf -- "$temporary_root"
  fi
}
trap cleanup EXIT

if [[ ! -f "$source_root/skills/redfox/SKILL.md" ]]; then
  command -v curl >/dev/null 2>&1 || { echo 'curl e obrigatorio para baixar a skill.' >&2; exit 1; }
  command -v tar >/dev/null 2>&1 || { echo 'tar e obrigatorio para baixar a skill.' >&2; exit 1; }
  temporary_root="$(mktemp -d)"
  archive_url="${REDFOX_ARCHIVE_URL:-https://github.com/wesleybasso/redfox-ai-orchestrator/archive/refs/heads/main.tar.gz}"
  echo 'Baixando a skill RedFox do GitHub...'
  curl -fsSL "$archive_url" | tar -xz -C "$temporary_root"
  source_root="$(find "$temporary_root" -mindepth 1 -maxdepth 1 -type d | head -n 1)"
fi

source_dir="$source_root/skills/redfox"
[[ -f "$source_dir/SKILL.md" ]] || { echo "Skill RedFox ausente: $source_dir" >&2; exit 1; }
timestamp="$(date +%Y%m%d-%H%M%S)"

for target in \
  "$user_home/.agents/skills/redfox" \
  "$user_home/.codex/skills/redfox" \
  "$user_home/.claude/skills/redfox"; do
  if ((dry_run)); then
    echo "[dry-run] instalar skill em $target"
    continue
  fi
  mkdir -p "$(dirname "$target")"
  if [[ -e "$target" ]]; then
    cp -a "$target" "$target.backup-$timestamp"
    rm -rf -- "$target"
  fi
  cp -a "$source_dir" "$target"
  echo "Skill instalada: $target"
done

echo 'Abra uma nova conversa e escreva: RedFox, qual e a missao?'
