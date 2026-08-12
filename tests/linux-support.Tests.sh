#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

require_file() {
  [[ -f "$ROOT/$1" ]] || { echo "RED: arquivo Linux ausente: $1" >&2; exit 1; }
}

for file in \
  install-linux.sh \
  install-skill.sh \
  redfox-local/install-linux.sh \
  redfox-local/configure-linux.sh \
  skills/redfox/scripts/invoke-redfox.sh; do
  require_file "$file"
  bash -n "$ROOT/$file"
done

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

HOME="$tmp/home" bash "$ROOT/install-skill.sh" --source-root "$ROOT" --home "$tmp/home"
for target in \
  "$tmp/home/.agents/skills/redfox/SKILL.md" \
  "$tmp/home/.codex/skills/redfox/scripts/invoke-redfox.sh" \
  "$tmp/home/.claude/skills/redfox/scripts/invoke-redfox.ps1"; do
  [[ -f "$target" ]] || { echo "Skill Linux incompleta: $target" >&2; exit 1; }
done

tar -czf "$tmp/redfox-source.tar.gz" --exclude='.git' --exclude='.test-output-final-*' -C "$(dirname "$ROOT")" "$(basename "$ROOT")"
remote_home="$tmp/remote-home"
HOME="$remote_home" REDFOX_ARCHIVE_URL="file://$tmp/redfox-source.tar.gz" \
  bash -c 'cd /tmp && bash -s -- --home "$HOME"' < "$ROOT/install-skill.sh"
[[ -f "$remote_home/.codex/skills/redfox/SKILL.md" ]] || { echo 'Instalacao remota da skill falhou.' >&2; exit 1; }

dry_run="$(HOME="$tmp/home" bash "$ROOT/install-linux.sh" --source-root "$ROOT" --home "$tmp/home" --dry-run --skip-configuration)"
for expected in \
  'linux' \
  'gemma3:1b' \
  '.local/share/redfox' \
  '.config/systemd/user/redfox.service' \
  'packages/ai-trio'; do
  grep -Fq "$expected" <<<"$dry_run" || { echo "Plano Linux sem: $expected" >&2; exit 1; }
done
[[ ! -e "$tmp/home/.local/share/redfox" ]] || { echo 'Dry-run alterou o perfil.' >&2; exit 1; }

skill_text="$(cat "$ROOT/skills/redfox/SKILL.md")"
grep -Fq 'invoke-redfox.sh' <<<"$skill_text" || { echo 'Skill nao ensina invocacao Linux.' >&2; exit 1; }
grep -Fq '~/.local/share/redfox' <<<"$skill_text" || { echo 'Skill nao documenta dados Linux.' >&2; exit 1; }

readme="$(cat "$ROOT/README.md")"
grep -Fq 'Linux' <<<"$readme" || { echo 'README nao anuncia Linux.' >&2; exit 1; }
grep -Fq 'install-linux.sh' <<<"$readme" || { echo 'README nao ensina instalar no Linux.' >&2; exit 1; }
grep -Fq 'install-skill.sh' <<<"$readme" || { echo 'README nao ensina instalar somente a skill no Linux.' >&2; exit 1; }

echo 'PASS: distribuicao Linux RedFox validada.'
