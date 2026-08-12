# 🚦 LEIA PRIMEIRO — Guia de instalação passo a passo (antiburrice)

> **ATENÇÃO — NÃO PULE ESTA PÁGINA.**
> Este pacote **NÃO instala nem loga as IAs para você**. Ele só conecta IAs que
> **já estejam instaladas como CLI** e **já estejam autenticadas** no seu computador.
>
> Se você rodar o `install.ps1` sem antes fazer o que está abaixo, **NÃO VAI FUNCIONAR**.
> Faça primeiro a lista de "coisas que você precisa conseguir" (Passo 0), depois siga na ordem.

---

## ✅ Passo 0 — O que você precisa ANTES de instalar (junte tudo primeiro)

Antes de qualquer coisa, você precisa de **contas/chaves**. Separe tudo isto antes de começar:

| Para usar... | Você precisa de... | Onde conseguir | É pago? |
|---|---|---|---|
| **Claude Code** | Uma conta Anthropic (login) | https://claude.ai | Plano/uso pago |
| **Codex** | Uma conta OpenAI/ChatGPT (login) | https://chatgpt.com | Plano/uso pago |
| **Gemini** | Uma **API key** do Google | https://aistudio.google.com/apikey | Tem faixa grátis |
| **Qwen + DeepSeek** (só no *quinteto*) | **UMA** API key do **OpenRouter** | https://openrouter.ai/keys | Pago por uso (créditos) |
| **Pesquisa web** (modo `/pesquisa`) | Uma API key do **Tavily** OU do **Brave** | https://app.tavily.com · https://brave.com/search/api | Ambas têm faixa grátis |

> 💡 **Importante (leia com calma):** o *quinteto* usa **Qwen** e **DeepSeek**, mas neste
> pacote **os dois passam pelo mesmo lugar: o OpenRouter**. Ou seja, você **NÃO** precisa de
> uma chave da Alibaba pro Qwen e outra da DeepSeek. **É UMA CHAVE SÓ (a do OpenRouter)** e ela
> cobre os dois. Não se confunda.

- **Trio** = Claude + Codex + Gemini → precisa dos 3 primeiros da tabela.
- **Quinteto** = Trio + Qwen + DeepSeek → precisa também da chave do OpenRouter (a última linha).

Se você só quer o **trio**, pode ignorar a linha do OpenRouter.

---

## ✅ Passo 1 — Instale as bases (Node.js e PowerShell 7)

Sem estes dois, nada roda.

1. **Node.js** (versão LTS): https://nodejs.org → baixe o instalador **LTS** e clique "Next" até o fim.
2. **PowerShell 7**: https://aka.ms/powershell → baixe e instale.
   - Depois, **sempre abra o "PowerShell 7"** (ícone preto), **não** o "Windows PowerShell" azul antigo.

**Como saber se deu certo?** Abra o PowerShell 7 e digite:

```powershell
node --version
$PSVersionTable.PSVersion
```

Se aparecerem números de versão (ex.: `v24.x` e `7.x`), está ok. Se der erro "não reconhecido",
reinicie o computador e tente de novo.

---

## ✅ Passo 2 — Instale os CLIs das IAs (copie e cole)

Abra o **PowerShell 7** e cole os comandos abaixo. **Cada IA é um programa separado.**

### 2.1 — Obrigatório para o TRIO (Claude + Codex + Gemini)

```powershell
npm install --global @tt-a1i/mco@0.11.0
npm install --global @anthropic-ai/claude-code@2.1.185
npm install --global @openai/codex@0.147.0
npm install --global @google/gemini-cli@0.55.1
```

### 2.2 — Só se você quiser também o QUINTETO (adiciona Qwen + DeepSeek)

```powershell
npm install --global @qwen-code/qwen-code@0.21.6
npm install --global --ignore-scripts @earendil-works/pi-coding-agent@0.84.0
```

> ℹ️ O `mco` é o "maestro" que faz as IAs conversarem. O `pi` é o programa que roda o DeepSeek.
> Não precisa entender os detalhes — só instalar.

---

## ✅ Passo 3 — Faça LOGIN / coloque as CHAVES (a parte que a maioria esquece)

**Instalar não basta. Cada IA precisa ser autenticada UMA vez.** Faça na ordem:

### 3.1 — Claude Code (login por conta)
```powershell
claude
```
Abra, siga o login no navegador (conta Anthropic) e depois pode fechar.

### 3.2 — Codex (login por conta)
```powershell
codex
```
Faça o login com sua conta OpenAI/ChatGPT quando ele pedir.

### 3.3 — Gemini (precisa da API KEY do Google)
1. Vá em https://aistudio.google.com/apikey e clique em **"Create API key"**. Copie a chave.
2. No PowerShell 7, cole isto **trocando `SUA_CHAVE_AQUI`** pela chave copiada:

```powershell
[Environment]::SetEnvironmentVariable('GEMINI_API_KEY', 'SUA_CHAVE_AQUI', 'User')
```

> 🔒 **Nunca cole sua chave em chat/IA.** Só neste comando, no seu próprio PowerShell.

### 3.4 — Qwen + DeepSeek (só no quinteto — UMA chave do OpenRouter)
1. Vá em https://openrouter.ai/keys, crie a conta, **adicione créditos** (é pago por uso) e clique
   em **"Create Key"**. Copie a chave.
2. **Não** cole a chave num comando à mão aqui — o pacote tem um script seguro que faz isso pra você,
   sem mostrar a chave na tela. Você vai rodá-lo no **Passo 5**.

---

## ✅ Passo 4 — Instale a integração do pacote (o `install.ps1`)

Agora sim. Abra o PowerShell 7 **dentro desta pasta** (`ai-trio-skills`) e primeiro **teste sem alterar nada**:

```powershell
pwsh -NoProfile -File ./install.ps1 -WhatIf
```

Se não deu erro grave, instale de verdade:

```powershell
pwsh -NoProfile -File ./install.ps1
```

> Isso conecta o trio/quinteto ao **Claude Code, Codex e Gemini** de uma vez.
> Depois, **feche e abra de novo** a sessão da IA que for usar.

---

## ✅ Passo 5 — (Só quinteto) Configure a chave do OpenRouter com segurança

Rode **UM** destes, conforme a IA que você usa como base. Ele pede a chave **sem exibir** e a guarda:

```powershell
# Se você usa Codex:
pwsh -NoProfile -File "$env:USERPROFILE/.codex/skills/using-ai-trio/scripts/configure-openrouter.ps1"

# Se você usa Gemini:
pwsh -NoProfile -File "$env:USERPROFILE/.gemini/trio-scripts/configure-openrouter.ps1"

# Se você usa Claude Code:
pwsh -NoProfile -File "$env:USERPROFILE/.claude/skills/using-ai-trio/scripts/configure-openrouter.ps1"
```

Cole a chave do OpenRouter quando pedir (a tela vai ficar "em branco" enquanto você digita — **isso é normal**, é proteção). Depois **abra uma nova sessão**.

---

## ✅ Passo 6 — Teste se funcionou

**Teste seguro (não gasta crédito, não chama as IAs de verdade):**

```powershell
pwsh -NoProfile -File "$env:USERPROFILE/.codex/skills/using-ai-trio/scripts/invoke-trio.ps1" -Task "teste" -Team trio -DryRun -Json
```

Se rodar sem erro, está pronto. Para usar de verdade:

**Modo especialista (recomendado no dia a dia — usa 1 modelo, o certo pra tarefa):**
- No **Codex** ou **Claude Code**:
  > `use o especialista para otimizar este algoritmo`
- No **Gemini CLI**:
  > `/especialista otimize este algoritmo`

**Modo pesquisa (web com fontes citadas e verificadas — melhor que a Perplexity):**
- Configure a chave de busca uma vez (pede Tavily e Brave — informe pelo menos uma):
  > `pwsh -File "$env:USERPROFILE/.codex/skills/using-ai-trio/scripts/configure-search.ps1"`
- No **Codex** ou **Claude Code**:
  > `use a pesquisa para descobrir a versão LTS atual do Node.js`
- No **Gemini CLI**:
  > `/pesquisa qual a versão LTS atual do Node.js`

**Modo conselho (as próprias IAs decidem quem é a melhor):**
- No **Codex** ou **Claude Code**:
  > `use o conselho para revisar esta arquitetura`
- No **Gemini CLI**:
  > `/conselho revise esta arquitetura`

**Modo painel (avançado — vários modelos + síntese, para decisões difíceis):**
- No **Codex** ou **Claude Code**:
  > `use o trio para revisar esta arquitetura e me dê uma conclusão única`
  > `use o quinteto para comparar estas abordagens`
- No **Gemini CLI**:
  > `/trio revise esta arquitetura`
  > `/quinteto compare estas abordagens`

> 💡 O **especialista** é o mais barato e rápido (chama só o modelo forte no assunto). O
> **conselho** faz as IAs votarem em quem lidera (mais caro). Use o **painel** quando quiser
> vários modelos opinando de uma vez.
>
> 🛡️ **Todos os modos** já usam **persona + regras anti-alucinação** em cada chamada: as IAs
> são orientadas a não inventar, admitir "não sei" quando incertas e citar o arquivo ao falar
> do código.

---

## ❓ Deu errado? (problemas comuns)

| Sintoma | Causa provável | Solução |
|---|---|---|
| `mco nao encontrado` | Faltou o Passo 2 | Rode o `npm install` do `@tt-a1i/mco` |
| `Qwen e DeepSeek sem credencial` | Faltou o Passo 5 | Rode o `configure-openrouter.ps1` |
| Gemini não responde | Faltou a `GEMINI_API_KEY` | Refaça o Passo 3.3 |
| `pwsh nao reconhecido` | Está no PowerShell antigo | Abra o **PowerShell 7** (ícone preto) |
| Nada muda depois de configurar | Sessão antiga aberta | **Feche e abra** a IA de novo |

> ✋ **Resumo do que trava a maioria:** as pessoas instalam os CLIs mas **esquecem de logar/colocar
> as chaves** (Passo 3 e Passo 5). Sem isso, o pacote não tem como funcionar.
