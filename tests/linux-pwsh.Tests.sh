#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
command -v pwsh >/dev/null 2>&1 || { echo 'pwsh e obrigatorio para este teste.' >&2; exit 1; }

pwsh -NoProfile -File "$ROOT/redfox-local/tests/RedFox.Local.Tests.ps1"
pwsh -NoProfile -File "$ROOT/redfox-local/tests/RedFox.Setup.Tests.ps1"
pwsh -NoProfile -File "$ROOT/redfox-local/tests/RedFox.Console.Tests.ps1"
pwsh -NoProfile -File "$ROOT/redfox-local/tests/RedFox.Command.Tests.ps1"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
home="$tmp/home"
mkdir -p "$home"

mkdir -p "$tmp/bin"
cat > "$tmp/bin/mco" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == 'doctor' ]]; then
  printf '%s\n' '{"providers":{"codex":{"detected":true,"auth_ok":true,"ready":true,"reason":"ok","risk":{"level":"read_only"}}}}'
  exit 0
fi
echo '{"status":"dry_run"}'
EOF
chmod +x "$tmp/bin/mco"
PATH="$tmp/bin:$PATH" pwsh -NoProfile -File "$ROOT/redfox-local/tests/RedFox.Service.Integration.Tests.ps1"

pwsh -NoProfile -File "$ROOT/packages/ai-trio/install.ps1" -UserHome "$home" -SkipDependencyCheck
HOME="$home" bash "$ROOT/install-skill.sh" --source-root "$ROOT" --home "$home"

output="$(HOME="$home" bash "$home/.codex/skills/redfox/scripts/invoke-redfox.sh" \
  --task 'Corrija um erro simples' --repo "$ROOT" --mode auto --dry-run --json)"
for expected in redfox especialista read_only; do
  grep -Fq "$expected" <<<"$output" || { echo "Invocacao Linux sem: $expected" >&2; exit 1; }
done

package_root="$tmp/packages"
pwsh -NoProfile -File "$ROOT/redfox-local/Build-RedFox-Editions.ps1" -OutputRoot "$package_root" >/dev/null
for script in \
  "$package_root/RedFox-Somente-Skill/INSTALAR-SOMENTE-SKILL.sh" \
  "$package_root/RedFox-Programa-Completo/INSTALAR-REDFOX.sh" \
  "$package_root/RedFox-Programa-Completo/redfox-local/install-linux.sh"; do
  [[ -f "$script" ]] || { echo "Pacote Linux incompleto: $script" >&2; exit 1; }
  bash -n "$script"
done

mock_bin="$tmp/full-install-bin"
full_home="$tmp/full-home"
mkdir -p "$mock_bin" "$full_home"
ln -s "$(command -v pwsh)" "$mock_bin/pwsh"
for command_name in mco claude codex gemini; do
  cat > "$mock_bin/$command_name" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  chmod +x "$mock_bin/$command_name"
done
cat > "$mock_bin/node" <<'EOF'
#!/usr/bin/env bash
echo v24.19.0
EOF
cat > "$mock_bin/npm" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
cat > "$mock_bin/ollama" <<'EOF'
#!/usr/bin/env bash
[[ "${1:-}" == pull || "${1:-}" == list || "${1:-}" == serve ]]
EOF
cat > "$mock_bin/curl" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
cat > "$mock_bin/systemctl" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
find "$mock_bin" -maxdepth 1 -type f -exec chmod +x {} +

env -u XDG_DATA_HOME -u XDG_CONFIG_HOME \
  HOME="$full_home" PATH="$mock_bin:/usr/bin:/bin" bash "$ROOT/install-linux.sh" \
  --source-root "$ROOT" --home "$full_home" --skip-configuration >/dev/null
for installed in \
  "$full_home/.local/share/redfox/RedFox.Service.ps1" \
  "$full_home/.local/share/redfox/service.token" \
  "$full_home/.config/systemd/user/redfox.service" \
  "$full_home/.codex/skills/redfox/SKILL.md" \
  "$full_home/.codex/skills/using-ai-trio/SKILL.md"; do
  [[ -f "$installed" ]] || { echo "Instalacao Linux completa ausente: $installed" >&2; exit 1; }
done
grep -Fq 'EnvironmentFile=' "$full_home/.config/systemd/user/redfox.service" || { echo 'Servico Linux nao carrega credenciais.' >&2; exit 1; }

echo 'PASS: PowerShell e skill RedFox funcionam no Linux.'
