# RedFox AI Orchestrator 🦊

Uma mini IA local que encontra e coordena as IAs instaladas no Windows. A RedFox usa o
Ollama como cérebro local, organiza Claude Code, Codex, Gemini e outros agentes compatíveis,
controla as rodadas e entrega uma resposta única.

Você escolhe entre duas edições:

| Edição | Para quem é | O que instala |
| --- | --- | --- |
| **Somente Skill** | Já possui o Trio/MCO configurado | Apenas o comando e a personalidade RedFox |
| **Programa Completo** | Quer começar do zero | Ollama, modelo local, MCO, CLIs, Trio, skill e serviço RedFox |

> As assinaturas e chaves de Claude, Codex, Gemini e outros provedores não estão incluídas.
> O Ollama e o modelo local são gratuitos. Cada usuário autentica suas próprias contas.

## Instalação completa — PowerShell

Abra o PowerShell e execute:

```powershell
irm https://raw.githubusercontent.com/wesleybasso/redfox-ai-orchestrator/main/install.ps1 | iex
```

O instalador usa `winget` para preparar as dependências ausentes e não grava chaves no
repositório. No final, ele abre a configuração guiada das contas.

## Instalação completa — CMD

Abra o **Prompt de Comando (CMD)** e execute:

```cmd
curl.exe -fsSL https://raw.githubusercontent.com/wesleybasso/redfox-ai-orchestrator/main/install.cmd -o "%TEMP%\install-redfox.cmd" && call "%TEMP%\install-redfox.cmd"
```

Também é possível abrir a página de **Releases**, baixar o ZIP, extrair e dar dois cliques em
`install.cmd`.

## Instalar somente a Skill

Com o instalador de skills:

```powershell
npx skills add wesleybasso/redfox-ai-orchestrator --skill redfox -g -y
```

Ou com PowerShell, instalando para os caminhos compartilhados de Codex e Claude:

```powershell
irm https://raw.githubusercontent.com/wesleybasso/redfox-ai-orchestrator/main/install-skill.ps1 | iex
```

A edição somente-skill pressupõe que `using-ai-trio` e MCO já estejam instalados. Ela não
instala Ollama nem as CLIs.

## Como usar

Depois da instalação, abra uma nova sessão do Codex ou Claude e fale naturalmente:

```text
RedFox, revise a arquitetura deste projeto.
RedFox, use o conselho para comparar estas duas soluções.
RedFox, quais IAs você encontrou neste computador?
```

A RedFox escolhe entre especialista, pesquisa, conselho, trio ou quinteto. Trabalhos externos
começam em modo somente leitura; o agente atual aplica e testa alterações no projeto.

## O que entra no conselho

- Claude Code
- OpenAI Codex CLI
- Gemini CLI
- GitHub Copilot CLI e outros agentes reconhecidos pelo MCO
- Qwen e DeepSeek quando configurados por um provedor compatível

Agentes instalados mas sem autenticação são mostrados como indisponíveis e não são chamados.

## Testes

Os testes não precisam gastar tokens:

```powershell
pwsh -NoProfile -File ./tests/public-release.Tests.ps1
pwsh -NoProfile -File ./redfox-local/tests/RedFox.Local.Tests.ps1
pwsh -NoProfile -File ./redfox-local/tests/RedFox.Setup.Tests.ps1
pwsh -NoProfile -File ./packages/ai-trio/tests/Test-Package.ps1
```

## ☕ Pague um café

Se a RedFox ajudou no seu trabalho, você pode [pagar um café pelo PayPal](https://www.paypal.me/wesleybasso)
ou visitar o [Linktree do Wesley Basso](https://linktr.ee/wesleybasso). Valeu! 😄

## Licença

[MIT](LICENSE) — Wesley Basso.
