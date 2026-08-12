# AI Trio / Quinteto — pacote para Windows

> ⚠️ **ANTES DE INSTALAR, LEIA:** [`LEIA-PRIMEIRO-INSTALACAO.md`](LEIA-PRIMEIRO-INSTALACAO.md)
> Este pacote **não funciona sozinho**: cada IA precisa estar **instalada como CLI** e
> **autenticada** antes. O **Gemini** exige uma API key do Google AI Studio; o **quinteto**
> (Qwen + DeepSeek) exige **uma única** API key do OpenRouter. Sem esses passos prévios,
> a instalação não terá efeito. O guia passo a passo "antiburrice" explica tudo em ordem.

Orquestre agentes de IA de código a partir de uma única sessão usando o MCO em modo
`read_only` e receba uma síntese unificada.

Há quatro modos:

- **especialista (roteador — padrão):** um classificador barato (Gemini) lê a tarefa,
  escolhe **um** domínio e chama **só** o modelo mais forte naquilo. Barato e rápido.
- **pesquisa (web citada):** o script busca na web (API Tavily), injeta as **fontes reais**
  nos modelos; um modelo redige com citações `[n]` e **outro verifica** cada citação contra
  as fontes. Supera ferramentas de um modelo só. Exige `TAVILY_API_KEY`.
- **conselho:** os próprios modelos **votam** em quem deve liderar, a líder eleita
  **executa** e as demais **revisam**. O script decide se precisa de 2ª rodada (consenso).
- **trio / quinteto (painel — avançado):** roda vários modelos em paralelo e sintetiza
  uma resposta única. Para decisões difíceis que valem o custo extra.
  - **trio**: Claude + Codex + Gemini
  - **quinteto**: trio + Qwen3 Coder + DeepSeek via Pi/OpenRouter

Mapa domínio → especialista do roteador: `arch`→Claude, `impl`→Codex, `algo`→Qwen,
`math`→DeepSeek, `research`→Gemini.

**Política anti-alucinação (todos os modos):** toda chamada leva uma **persona** e
**regras anti-alucinação** — o modelo se baseia só no contexto, não inventa arquivos/APIs/
números, admite "não sei" quando incerto, separa fato de suposição, cita o caminho do arquivo
e não fabrica citações/links/saídas de terminal.

O pacote instala integrações para Codex, Claude Code e Gemini CLI sem substituir
silenciosamente configurações existentes.

## Compatibilidade testada

Este release é destinado a **Windows 10/11 x64**. As versões verificadas estão em
[`versions.lock.json`](versions.lock.json): PowerShell 7.6.4, Node.js 24.19.0, MCO 0.11.0,
Gemini CLI 0.55.1, Qwen Code 0.21.6 e Pi 0.84.0.

O instalador exige PowerShell 7 ou superior. Outras versões podem funcionar, mas não fazem
parte deste teste de distribuição.

## Pré-requisitos

Instale Node.js e, em um PowerShell 7, execute os pacotes necessários. As versões abaixo são
as versões testadas, não aliases móveis como `latest`.

```powershell
npm install --global @tt-a1i/mco@0.11.0
npm install --global @anthropic-ai/claude-code@2.1.185
npm install --global @openai/codex@0.147.0
npm install --global @google/gemini-cli@0.55.1
```

Para habilitar também o quinteto:

```powershell
npm install --global @qwen-code/qwen-code@0.21.6
npm install --global --ignore-scripts @earendil-works/pi-coding-agent@0.84.0
```

Autentique Claude Code, Codex e Gemini CLI pelos fluxos oficiais de cada ferramenta. O
quinteto também requer uma `OPENROUTER_API_KEY` compartilhada por Qwen e DeepSeek. O modo
**pesquisa** requer uma chave de busca web: `TAVILY_API_KEY` (https://app.tavily.com) **ou**
`BRAVE_API_KEY` (https://brave.com/search/api). Basta uma das duas; ambas têm faixa grátis.

## Instalação segura

Abra o PowerShell 7 na raiz desta pasta e valide primeiro:

```powershell
pwsh -NoProfile -File ./install.ps1 -WhatIf
```

Instale em todos os hosts:

```powershell
pwsh -NoProfile -File ./install.ps1
```

Ou selecione apenas alguns hosts:

```powershell
pwsh -NoProfile -File ./install.ps1 -Hosts Codex,Claude
pwsh -NoProfile -File ./install.ps1 -Hosts Gemini
```

O instalador:

- cria cada diretório de destino explicitamente;
- instala a skill dentro de `using-ai-trio`, nunca diretamente na raiz de `skills`;
- preserva arquivos diferentes em backups `*.ai-trio-backup-*` antes de atualizá-los;
- mescla somente o bloco delimitado `ai-trio` no `~/.gemini/GEMINI.md`;
- não lê, copia nem imprime valores de credenciais;
- pode ser executado novamente sem duplicar conteúdo.

Após a instalação, abra uma nova sessão do Codex, Claude Code ou Gemini CLI.

## Configuração do quinteto

Execute o configurador correspondente ao host já instalado. Exemplo para Codex:

```powershell
pwsh -NoProfile -File "$env:USERPROFILE/.codex/skills/using-ai-trio/scripts/configure-openrouter.ps1"
```

Exemplo para Gemini:

```powershell
pwsh -NoProfile -File "$env:USERPROFILE/.gemini/trio-scripts/configure-openrouter.ps1"
```

O script solicita a chave sem exibi-la, persiste `OPENROUTER_API_KEY` no ambiente do usuário
e configura o Qwen para `qwen/qwen3-coder-next` via OpenRouter. Nunca cole a chave no chat.

## Uso

### Modo especialista (roteador — padrão)

Em Codex ou Claude Code:

```text
use o especialista para otimizar este algoritmo
```

No Gemini CLI:

```text
/especialista otimize este algoritmo O(n^2)
```

Chamando o script diretamente:

```powershell
# automático (o classificador escolhe o domínio):
pwsh -File "$env:USERPROFILE/.codex/skills/using-ai-trio/scripts/invoke-router.ps1" -Task "corrija este bug"
# forçar o domínio (pula o classificador):
pwsh -File "$env:USERPROFILE/.codex/skills/using-ai-trio/scripts/invoke-router.ps1" -Task "..." -Domain math
# só mostrar a decisão de roteamento:
pwsh -File "$env:USERPROFILE/.codex/skills/using-ai-trio/scripts/invoke-router.ps1" -Task "..." -Explain
```

O roteador faz **duas** chamadas quando o domínio é `auto` (uma para classificar, uma para
o especialista). Use `-Domain <nome>` para pular o classificador. Os domínios `algo` e `math`
exigem a chave do OpenRouter.

### Modo pesquisa (web citada e verificada — supera a Perplexity)

Configure a chave de busca uma vez (pede Tavily e Brave; informe pelo menos uma):

```powershell
pwsh -File "$env:USERPROFILE/.codex/skills/using-ai-trio/scripts/configure-search.ps1"
# só uma delas:
pwsh -File "$env:USERPROFILE/.codex/skills/using-ai-trio/scripts/configure-search.ps1" -Provider tavily
pwsh -File "$env:USERPROFILE/.codex/skills/using-ai-trio/scripts/configure-search.ps1" -Provider brave
```

Backends: **Tavily** (https://app.tavily.com) e **Brave** (https://brave.com/search/api).
O modo pesquisa usa a chave disponível (Tavily tem prioridade); force com `-SearchProvider brave`.

Em Codex ou Claude Code:

```text
use a pesquisa para descobrir a versão LTS atual do Node.js
```

No Gemini CLI:

```text
/pesquisa qual a versão LTS atual do Node.js
```

Chamando o script diretamente:

```powershell
pwsh -File "$env:USERPROFILE/.codex/skills/using-ai-trio/scripts/invoke-research.ps1" -Query "sua pergunta"
# escolher quem redige e quem verifica (devem ser diferentes):
pwsh -File "$env:USERPROFILE/.codex/skills/using-ai-trio/scripts/invoke-research.ps1" -Query "..." -Writer claude -Verifier codex
# forçar o backend de busca (tavily|brave):
pwsh -File "$env:USERPROFILE/.codex/skills/using-ai-trio/scripts/invoke-research.ps1" -Query "..." -SearchProvider brave
```

Fluxo: busca web (Tavily) → um modelo redige citando `[n]` só a partir das fontes → outro modelo
marca cada afirmação como SUSTENTADO / NÃO-SUSTENTADO / SEM-FONTE e reporta a CONFIABILIDADE.

> ℹ️ Os CLIs **não** têm web funcional via MCO aqui (o Claude responde `SEM_WEB`, o Gemini expira).
> Por isso é o **host que busca** as fontes e as injeta no contexto — os modelos não precisam de web ao vivo.

### Modo conselho (as IAs decidem entre si)

Em Codex ou Claude Code:

```text
use o conselho para revisar esta arquitetura
```

No Gemini CLI:

```text
/conselho revise esta arquitetura
```

Chamando o script diretamente:

```powershell
# eleicao (trio vota) + execucao + revisao:
pwsh -File "$env:USERPROFILE/.codex/skills/using-ai-trio/scripts/invoke-council.ps1" -Task "..."
# incluir Qwen e DeepSeek entre os eleitores:
pwsh -File "$env:USERPROFILE/.codex/skills/using-ai-trio/scripts/invoke-council.ps1" -Task "..." -Electors claude,codex,gemini,qwen,pi
# só ver quem foi eleito:
pwsh -File "$env:USERPROFILE/.codex/skills/using-ai-trio/scripts/invoke-council.ps1" -Task "..." -ElectOnly
```

Os modelos votam em quem deve liderar; o script faz uma 2ª rodada se não houver consenso
(`-MaxRounds`, padrão 2). É o modo **mais caro** (uma chamada por eleitor por rodada, mais
execução e revisão) — use `-Electors` para controlar o custo. Eleger `qwen`/`pi` exige a chave
do OpenRouter.

### Modo painel (trio / quinteto — avançado)

Em Codex ou Claude Code:

```text
use o trio para revisar esta arquitetura e me entregue uma conclusão única
use o quinteto para comparar estas abordagens
```

No Gemini CLI:

```text
/trio revise esta arquitetura
/quinteto compare estas abordagens
```

Comandos customizados do Gemini que executam shell podem solicitar confirmação antes da
execução. Isso é uma proteção normal do Gemini CLI.

## Segurança de escrita

Revisões, pesquisas, diagnósticos e planos ficam em `read_only`. Para implementação, os
modelos externos fornecem o plano e a revisão; somente o host atual altera arquivos e executa
os testes. Escrita paralela exige solicitação explícita e caminhos sem sobreposição.

## Verificação do pacote

O teste usa perfis temporários e não altera o perfil real:

```powershell
pwsh -NoProfile -File ./tests/Test-Package.ps1
```

Ele cobre instalação limpa, reinstalação idempotente, preservação de `GEMINI.md`, `-WhatIf`,
sintaxe PowerShell, consistência das cópias, ausência de artefatos e busca básica por segredos.

Para validar o MCO sem chamar modelos:

```powershell
pwsh -NoProfile -File ./codex/using-ai-trio/scripts/invoke-trio.ps1 `
  -Task "Teste seguro de instalação" -Team trio -DryRun -Json

pwsh -NoProfile -File ./codex/using-ai-trio/scripts/invoke-trio.ps1 `
  -Task "Teste seguro de instalação" -Team quintet -DryRun -Json
```

## Estrutura

```text
ai-trio-skills/
├─ install.ps1
├─ versions.lock.json
├─ README.md
├─ tests/Test-Package.ps1
├─ claude-code/using-ai-trio/   (scripts: invoke-router, invoke-research, invoke-council, invoke-trio, configure-openrouter, configure-search)
├─ codex/using-ai-trio/         (scripts: idem)
└─ gemini/
   ├─ commands/especialista.toml, pesquisa.toml, conselho.toml, trio.toml, quinteto.toml
   ├─ trio-scripts/             (invoke-router, invoke-research, invoke-council, invoke-trio, configure-openrouter, configure-search)
   └─ GEMINI.fragment.md
```
