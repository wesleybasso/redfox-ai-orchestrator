#!/usr/bin/env bash
set -euo pipefail

[[ "$(uname -s)" == "Linux" ]] || { echo 'Este instalador e exclusivo para Linux.' >&2; exit 1; }

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source_root="$(cd "$script_dir/.." && pwd)"
user_home="${HOME:?HOME nao definido}"
model="gemma3:1b"
dry_run=0
skip_configuration=0

while (($#)); do
  case "$1" in
    --source-root) source_root="$(cd "$2" && pwd)"; shift 2 ;;
    --home) user_home="$2"; shift 2 ;;
    --model) model="$2"; shift 2 ;;
    --dry-run) dry_run=1; shift ;;
    --skip-configuration) skip_configuration=1; shift ;;
    *) echo "Opcao desconhecida: $1" >&2; exit 2 ;;
  esac
done

data_home="${XDG_DATA_HOME:-$user_home/.local/share}"
config_home="${XDG_CONFIG_HOME:-$user_home/.config}"
runtime_root="$data_home/redfox-runtime"
install_dir="$data_home/redfox"
unit_dir="$config_home/systemd/user"
unit_path="$unit_dir/redfox.service"
trio_dir="$source_root/packages/ai-trio"

if ((dry_run)); then
  cat <<EOF
RedFox linux - plano de instalacao
modelo: $model
runtime: $runtime_root
servico: $install_dir
systemd: $unit_path
trio: $trio_dir
etapas: powershell node npm ollama mco claude codex gemini skill service
EOF
  exit 0
fi

for command_name in curl tar; do
  command -v "$command_name" >/dev/null 2>&1 || { echo "Dependencia ausente: $command_name" >&2; exit 1; }
done
[[ -f "$trio_dir/install.ps1" ]] || { echo "Pacote do trio ausente: $trio_dir" >&2; exit 1; }

mkdir -p "$runtime_root" "$install_dir" "$user_home/.local/bin"

arch="$(uname -m)"
case "$arch" in
  x86_64|amd64) node_arch='x64'; pwsh_arch='x64' ;;
  aarch64|arm64) node_arch='arm64'; pwsh_arch='arm64' ;;
  *) echo "Arquitetura Linux ainda nao suportada: $arch" >&2; exit 1 ;;
esac

pwsh_bin="$(command -v pwsh || true)"
if [[ -z "$pwsh_bin" ]]; then
  pwsh_version='7.6.3'
  pwsh_dir="$runtime_root/powershell-$pwsh_version"
  if [[ ! -x "$pwsh_dir/pwsh" ]]; then
    mkdir -p "$pwsh_dir"
    echo "Instalando PowerShell $pwsh_version no perfil do usuario..."
    curl -fsSL "https://github.com/PowerShell/PowerShell/releases/download/v${pwsh_version}/powershell-${pwsh_version}-linux-${pwsh_arch}.tar.gz" | tar -xz -C "$pwsh_dir"
    chmod +x "$pwsh_dir/pwsh"
  fi
  pwsh_bin="$pwsh_dir/pwsh"
  ln -sfn "$pwsh_bin" "$user_home/.local/bin/pwsh"
fi

node_bin="$(command -v node || true)"
node_ok=0
if [[ -n "$node_bin" ]]; then
  node_major="$(node --version | sed -E 's/^v([0-9]+).*/\1/')"
  ((node_major >= 20)) && node_ok=1
fi
if ((node_ok == 0)); then
  node_version='24.19.0'
  node_dir="$runtime_root/node-v${node_version}-linux-${node_arch}"
  if [[ ! -x "$node_dir/bin/node" ]]; then
    echo "Instalando Node.js $node_version no perfil do usuario..."
    curl -fsSL "https://nodejs.org/dist/v${node_version}/node-v${node_version}-linux-${node_arch}.tar.gz" | tar -xz -C "$runtime_root"
  fi
  export PATH="$node_dir/bin:$PATH"
fi

npm_prefix="$runtime_root/npm"
mkdir -p "$npm_prefix"
export PATH="$user_home/.local/bin:$npm_prefix/bin:$PATH"
service_path="$user_home/.local/bin:$npm_prefix/bin:$(dirname "$(command -v node)"):/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

install_npm_cli() {
  local command_name="$1" package="$2"
  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "Instalando $command_name..."
    npm install --global --prefix "$npm_prefix" "$package"
  fi
}

install_npm_cli mco '@tt-a1i/mco@0.11.0'
install_npm_cli claude '@anthropic-ai/claude-code@2.1.185'
install_npm_cli codex '@openai/codex@0.147.0'
install_npm_cli gemini '@google/gemini-cli@0.55.1'

if ! command -v ollama >/dev/null 2>&1; then
  echo 'Instalando Ollama pelo instalador oficial...'
  curl -fsSL https://ollama.com/install.sh | sh
fi

if ! curl -fsS http://127.0.0.1:11434/api/tags >/dev/null 2>&1; then
  if command -v systemctl >/dev/null 2>&1; then sudo systemctl start ollama 2>/dev/null || true; fi
  if ! curl -fsS http://127.0.0.1:11434/api/tags >/dev/null 2>&1; then
    nohup ollama serve >"$install_dir/ollama.log" 2>&1 &
  fi
  for _ in {1..30}; do curl -fsS http://127.0.0.1:11434/api/tags >/dev/null 2>&1 && break; sleep 1; done
fi
ollama pull "$model"

"$pwsh_bin" -NoProfile -File "$trio_dir/install.ps1"
bash "$source_root/install-skill.sh" --source-root "$source_root" --home "$user_home"

for file in RedFox.Core.psm1 RedFox.Setup.psm1 RedFox.Service.ps1 RedFox.Client.ps1 Configure-RedFox.ps1; do
  cp "$source_root/redfox-local/$file" "$install_dir/$file"
done
if [[ ! -f "$install_dir/service.token" ]]; then
  umask 077
  od -An -N32 -tx1 /dev/urandom | tr -d ' \n' > "$install_dir/service.token"
fi
printf '{"brain":"ollama","model":"%s","ollama_uri":"http://127.0.0.1:11434"}\n' "$model" > "$install_dir/config.json"

mkdir -p "$unit_dir"
cat > "$unit_path" <<EOF
[Unit]
Description=RedFox AI Orchestrator
After=network-online.target

[Service]
Type=simple
ExecStart="$pwsh_bin" -NoProfile -File "$install_dir/RedFox.Service.ps1" -DataDirectory "$install_dir"
Restart=on-failure
RestartSec=3
Environment="PATH=$service_path"
EnvironmentFile=-$config_home/redfox/env

[Install]
WantedBy=default.target
EOF

if command -v systemctl >/dev/null 2>&1 && systemctl --user show-environment >/dev/null 2>&1; then
  systemctl --user daemon-reload
  systemctl --user enable --now redfox.service
else
  echo 'systemd de usuario indisponivel; iniciando a RedFox nesta sessao.'
  if ! curl -fsS http://127.0.0.1:4777/health >/dev/null 2>&1; then
    nohup "$pwsh_bin" -NoProfile -File "$install_dir/RedFox.Service.ps1" -DataDirectory "$install_dir" >"$install_dir/startup.log" 2>&1 &
  fi
fi

if ((skip_configuration == 0)); then
  bash "$source_root/redfox-local/configure-linux.sh"
fi

echo
echo 'RedFox instalada no Linux.'
echo 'Abra um novo terminal e diga: RedFox, quais IAs voce encontrou?'
