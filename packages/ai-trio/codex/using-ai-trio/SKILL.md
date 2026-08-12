---
name: using-ai-trio
description: Use when the user says "use o especialista", "use a pesquisa", "pesquise na web", "use o conselho", "use o trio", "use o quinteto", "chame os agentes", asks to route a task to the best model, asks for cited web research, asks the models to decide among themselves who is best, or asks for Claude, Codex, Gemini, Qwen or DeepSeek — as a single routed specialist, a cited web-research pass, a self-electing council, or a multi-model panel with one unified answer.
compatibility: Requires MCO and authenticated provider CLIs; the quintet also requires Qwen Code, Pi, and one OPENROUTER_API_KEY shared by Qwen and DeepSeek.
---

# Using AI Trio

## Overview

Invoke multi-model teams headlessly through MCO so the user stays in the current Codex or Claude session and never needs to open the other applications.

## Four modes

- **especialista (router, default)** — a cheap classifier (Gemini) reads the task, picks ONE domain, and calls only the strongest specialist for it, in `read_only`. Cheapest and fastest. Prefer this for everyday tasks.
- **pesquisa (web research)** — the host searches the web (Tavily or Brave API), injects the real sources into the models; one model writes a cited answer and ANOTHER model verifies every citation against the sources. Beats single-model tools by cross-checking citations. Requires `TAVILY_API_KEY` or `BRAVE_API_KEY`.
- **conselho (council)** — the models themselves vote on who should lead, the elected leader executes, and the others review. The script decides whether a second voting round is needed (consensus-based). Use when you want the models to choose the best fit with their own reasoning.
- **trio / quinteto (panel, advanced)** — runs several models in parallel and synthesizes one answer. Reserve for hard/ambiguous design and review decisions where multiple perspectives justify the extra cost.

Note: provider CLIs do NOT have working web access through MCO here (Claude returns SEM_WEB; Gemini times out). The `pesquisa` mode works around this by having the host fetch sources and pass them in-context, so the models never need live web.

### Anti-hallucination policy (all modes)

Every model call carries a **persona** and mandatory **anti-hallucination guardrails**: ground answers only in the provided repo/context; never invent files, functions, APIs, versions or numbers; say "não sei"/"não consta" when unsure; separate FACT from ASSUMPTION; cite the file path when claiming something about code; never fabricate citations, links or terminal output; prefer admitting uncertainty over confident error.

Domain → specialist map used by the router:

- `arch` → Claude (architecture, requirements, risks, security)
- `impl` → Codex (implementation, debugging, tests, refactor)
- `algo` → Qwen3 Coder via OpenRouter (algorithms, data structures, alternatives)
- `math` → DeepSeek via Pi/OpenRouter (math, complexity, deep reasoning)
- `research` → Gemini (research, docs, wide context, comparison)

Router command:

```powershell
& "<skill-dir>\scripts\invoke-router.ps1" -Task "<complete task>" -Repo "<repository>"
# force the domain instead of auto-classifying:
& "<skill-dir>\scripts\invoke-router.ps1" -Task "..." -Domain math
# only show the routing decision:
& "<skill-dir>\scripts\invoke-router.ps1" -Task "..." -Explain
```

The router makes two model calls when `-Domain auto` (one to classify, one specialist). Use `-Domain <name>` to skip the classifier. `algo` and `math` require the OpenRouter key.

Council command:

```powershell
& "<skill-dir>\scripts\invoke-council.ps1" -Task "<complete task>" -Repo "<repository>"
# choose who votes (default: claude,codex,gemini):
& "<skill-dir>\scripts\invoke-council.ps1" -Task "..." -Electors claude,codex,gemini,qwen,pi
# only show the election result:
& "<skill-dir>\scripts\invoke-council.ps1" -Task "..." -ElectOnly
# skip the review phase:
& "<skill-dir>\scripts\invoke-council.ps1" -Task "..." -SkipReview
```

The council runs one model call per elector per voting round (up to `-MaxRounds`, default 2), plus one execution and one review call. It is the most expensive mode; scope `-Electors` to control cost. Electing `qwen`/`pi` requires the OpenRouter key.

Research command:

```powershell
& "<skill-dir>\scripts\invoke-research.ps1" -Query "<question>"
# pick writer/verifier models (must differ):
& "<skill-dir>\scripts\invoke-research.ps1" -Query "..." -Writer claude -Verifier codex -MaxResults 5
```

The research flow is: web search → writer drafts a `[n]`-cited answer from the sources only → verifier marks each claim SUSTENTADO / NAO-SUSTENTADO / SEM-FONTE and reports CONFIABILIDADE. Run `scripts/configure-search.ps1` once to store a search key: `TAVILY_API_KEY` (https://app.tavily.com) or `BRAVE_API_KEY` (https://brave.com/search/api) — either works, Tavily takes priority, force with `-SearchProvider brave`. The host must present the final answer with unsupported claims removed.

## Runtime dependency

This skill requires the `mco` executable and authenticated provider CLIs. It does not require another Agent Skill.

Before dispatch, confirm the requested team in natural language, use explicit providers, keep reviews in `read_only`, and preserve each successful answer when another provider fails or times out. Use `mco --version`, `mco doctor --json`, and `-DryRun -Json` when validating a new installation.

## Panel workflow (trio / quinteto — advanced)

1. Resolve the explicit shortcut without a blocking reconfirmation:
   - **trio** = Claude + Codex + Gemini.
   - **quinteto** = Claude + Codex + Gemini + Qwen + DeepSeek.
2. Resolve the repository from the current working directory unless the user names another path.
3. Run `scripts/invoke-trio.ps1` relative to this skill directory, passing the complete task, repository, and `-Team trio|quintet`.
4. Return the unified synthesis first, then provider status, reported token usage, and artifact location.

The helper assigns stable perspectives:

- Claude: architecture, requirements, risks, security, and final synthesis.
- Codex: implementation, debugging, tests, performance, and maintainability.
- Gemini: research, documentation, long context, alternatives, and usability.
- Qwen3 Coder Next via OpenRouter: code reasoning, algorithmic alternatives, and independent review.
- DeepSeek V4 Flash via Pi/OpenRouter: deep reasoning, mathematics, and token efficiency.

## Changes to files

When the user requests review, comparison, research, planning, or diagnosis, keep the trio in `read_only`.

When the user requests implementation or a fix:

1. Ask the trio for an implementation plan and review in `read_only`.
2. Let only the currently open host agent implement the synthesized plan.
3. Run relevant tests and report deviations from the plan.

This gives the benefit of three perspectives without parallel writers racing on the same files. Use parallel writing only when the user explicitly requests it and file ownership is partitioned into non-overlapping paths.

## Command

```powershell
& "<skill-dir>\scripts\invoke-trio.ps1" -Task "<complete task>" -Repo "<repository>" -Team quintet
```

Add `-DryRun -Json` only when previewing the resolved policy without invoking models. Do not use unrestricted or approval-bypass modes unless the user explicitly requests them.

For one-time quintet setup, run `scripts/configure-openrouter.ps1`. It prompts securely, stores `OPENROUTER_API_KEY` in the Windows user environment, and configures Qwen Code to use `qwen/qwen3-coder-next` at `https://openrouter.ai/api/v1`. Never ask the user to paste a key into chat.

## Failures

If the task is partial, preserve successful answers and identify the failed or timed-out provider. Verify credentials by presence only and never expose key values: `GEMINI_API_KEY` for Gemini and `OPENROUTER_API_KEY` for both Qwen and DeepSeek.

## Example trigger

User: `Use o trio para revisar esta arquitetura e me entregue uma conclusao unica.`

Action: invoke the helper in the current repository, then lead with the synthesized conclusion.
