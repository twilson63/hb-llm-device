# hb-llm-device — LLM Agent Stack for HyperBEAM

**Agent = LLM + Harness + Tools + Instructions** — one harness, many agents. See [What is an Agent?](https://chat.hyper.io/share/wE41XruWrXFj37EdGfFxn3sdXy0Wib9e) and [Agent Flow](https://chat.hyper.io/share/_4kT2xkDzGpPncXP5k6wx8zB5m4LKlnT).

This repo packages the full agent stack as HyperBEAM devices (Forge `device`):

* `llm@1.0` (`src/preloaded/llm/dev_llm.erl`) — OpenAI-compatible proxy for Ollama/vLLM/llama.cpp (`POST /v1/chat/completions`, `stream=true` → SSE, `POST /v1/embeddings`). Bypasses `dev_relay` localhost block via `hb_http`. Default `qwen3.6` (`unsloth/Qwen3.6-35B-A3B-NVFP4`) on `spark-1b7b.local:8888`, override via `endpoint`.
* `harness@1.0` (`src/preloaded/agent/dev_harness.erl`) — Generic loop: builds `system(identity.md+soul.md+user.md)+tools.json+history↑20+current` window, calls `llm@1.0`, runs `tool_calls` via `relay@1.0`, rebuilds until no tools, persists `history` to `hb_store`.
* `skills@1.0` (`src/preloaded/agent/dev_skills.erl`) — Composable registry: `register/get/list/check/run/compose`, enforces `requires_tools ⊆ tools.json` matrix, delegates to harness.
* `agent` process (`src/preloaded/agent/agent.lua` + `harness.lua`) — `RunSkill`/`AgentPrompt` loads `agents/<id>/{identity.md,user.md,soul.md,tools.json}` + `memory/*.md`, checks skills, runs via harness.

## Quick start

```bash
# Install
git clone https://github.com/twilson63/hb-llm-device && cd hb-llm-device
rebar3 compile
rebar3 device preload  # or rebar3 device local

# Run local LLM (Ollama)
ollama serve &; ollama pull llama3.2; ollama pull qwen3.6:27b

# Test harness + skills (mock)
rebar3 device test
# or against HyperBEAM core
rebar3 device test --with-core

# Publish to Forge (Arweave)
rebar3 device publish --device-src src/preloaded/llm --dry-run --verbose
rebar3 device publish --device-src src/preloaded/agent --dry-run --verbose
rebar3 device publish --verbose  # all

# Example: water vs space essay (see HyperBEAM examples/datacenter-essay)
# hyperbeam/examples/datacenter-essay/{skills.json,agents/researcher/*,essay.out.md}
```

## HyperBEAM integration

Copy into HyperBEAM:

```bash
cp src/preloaded/llm/* /path/to/hyperbeam/src/preloaded/llm/
cp src/preloaded/agent/* /path/to/hyperbeam/src/preloaded/agent/
rebar3 compile && rebar3 device preload
```

Or as dep in `rebar.config`:

```erlang
{deps, [{hb_llm_device, {git, "https://github.com/twilson63/hb-llm-device.git", {branch, "main"}}}]}.
```

## Publish to Molecule (permagit)

```bash
curl -fsSL https://arweave.net/dSpQZnHnpkHGmiLrLliONDVgIPIx5-ZNgOjwY9tSkPY | bash  # permagit 0.11.3
permagit init hb-llm-device
git add -A && git commit -m "feat: agent stack"
permagit push main
git clone arweave://hb-llm-device
```

Spec IDs (latest, signer `aa0b-vzWf7Sn4cFKI43P4MUcSgAdAjCH2V2IFTKZGfU`):
* `llm@1.0` — Spec `2fJihfIyiV3iN7LYA0HMSRV8_pxUx3zkBoi8ZtNV7bE`
* `harness@1.0` — Spec `r09P4ZkjHMtGIDGRXv_43_CWs2PEwENlPvJwTcf1X-4`
* `skills@1.0` — Spec `isu2v3tmV3RmXrQhW6PJlsXDd3A8ktDAv871NjCutxg`

See `src/preloaded/agent/agent.lua` and HyperBEAM `examples/datacenter-essay/` for full `research → write` flow.
