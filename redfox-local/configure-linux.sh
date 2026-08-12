#!/usr/bin/env bash
set -euo pipefail

config_home="${XDG_CONFIG_HOME:-$HOME/.config}/redfox"
env_file="$config_home/env"
mkdir -p "$config_home"
touch "$env_file"
chmod 600 "$env_file"

ask() {
  local prompt="$1" answer
  read -r -p "$prompt (s/n) " answer
  [[ "$answer" =~ ^([sS]|[sS][iI][mM])$ ]]
}

set_secret() {
  local name="$1" value
  read -r -s -p "Cole a $name (ficara invisivel): " value
  echo
  [[ -n "$value" ]] || return 0
  grep -v "^${name}=" "$env_file" > "$env_file.tmp" || true
  printf '%s=%s\n' "$name" "$value" >> "$env_file.tmp"
  mv "$env_file.tmp" "$env_file"
  chmod 600 "$env_file"
  export "$name=$value"
  unset value
}

echo 'REDFOX - CONFIGURACAO GUIADA PARA LINUX'
if command -v claude >/dev/null 2>&1 && ask 'Configurar login do Claude agora?'; then claude || echo 'Login do Claude nao concluido; tente novamente depois.'; fi
if command -v codex >/dev/null 2>&1 && ask 'Configurar login do Codex agora?'; then codex login || echo 'Login do Codex nao concluido; tente novamente depois.'; fi
if ask 'Configurar chave do Gemini agora?'; then set_secret GEMINI_API_KEY; fi
if command -v copilot >/dev/null 2>&1 && ask 'Configurar o GitHub Copilot CLI agora?'; then copilot login || echo 'Login do Copilot nao concluido; tente novamente depois.'; fi

if command -v mco >/dev/null 2>&1; then
  echo 'Diagnostico final:'
  mco doctor --json || true
fi
if command -v systemctl >/dev/null 2>&1 && systemctl --user is-enabled redfox.service >/dev/null 2>&1; then
  systemctl --user restart redfox.service || true
fi
echo "Credenciais por variavel foram protegidas em $env_file"
