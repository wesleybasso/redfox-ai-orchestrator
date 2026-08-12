<!-- ai-trio:start -->
## Especialista / Trio / Quinteto de IA

Quando o usuario pedir "use o especialista" ou "roteie a tarefa", execute `/especialista <tarefa>`.
Quando pedir "use a pesquisa" ou "pesquise na web", execute `/pesquisa <pergunta>`.
Quando pedir "use o conselho" ou "as ias decidam entre si", execute `/conselho <tarefa>`.
Quando pedir "use o trio", execute `/trio <tarefa>`.
Quando pedir "use o quinteto", execute `/quinteto <tarefa>`.

- Especialista (roteador, padrao): um classificador barato escolhe UM dominio e chama so o modelo mais forte (arch->Claude, impl->Codex, algo->Qwen, math->DeepSeek, research->Gemini).
- Pesquisa: o host busca fontes na web (Tavily), um modelo redige citando [n] e outro verifica cada citacao; apresente so o que ficou SUSTENTADO.
- Conselho: os modelos votam em quem deve liderar, a lider executa e as demais revisam.
- Trio (painel): Claude + Codex + Gemini.
- Quinteto (painel): Claude + Codex + Gemini + Qwen + DeepSeek via Pi/OpenRouter.
- Todos usam MCO em modo `read_only`; o painel apresenta primeiro uma sintese unica.
- Toda chamada carrega persona e regras anti-alucinacao (nao inventar, admitir incerteza, citar arquivo, separar fato de suposicao).
- Para implementacoes, os modelos externos fornecem plano e revisao; somente o host atual altera arquivos e executa testes.
<!-- ai-trio:end -->
