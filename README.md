# hb-llm-device — llm@1.0 for HyperBEAM

OpenAI-compatible LLM device for HyperBEAM (`Ollama` / `vLLM` / `llama.cpp`).

- `chat` → POST `/v1/chat/completions` (supports `stream=true` → SSE)
- `generate` → `chat` + extracts `choices[0].message.content` → `content`
- `embed`/`embeddings` → POST `/v1/embeddings`

Default endpoint `http://spark-1b7b.local:8888/v1/chat/completions`, default model `unsloth/Qwen3.6-35B-A3B-NVFP4` (`qwen3.6` alias). Override via `endpoint`, `model`, `llm-endpoint`.

## Use

```bash
# In HyperBEAM checkout
rebar3 device preload  # includes llm@1.0
curl "http://localhost:8734/~llm@1.0/chat?prompt=hello&model=qwen3.6"
curl -X POST http://localhost:8734/~llm@1.0/chat -H "content-type: application/json" -d '{"messages":[{"role":"user","content":"hi"}],"model":"qwen3.6","stream":true}'

# Via AO/Lua
# load llm_sidecar.lua into your process: Send({Device="llm@1.0", Action="chat", Prompt="hi", Model="qwen3.6"})
```

## Forge publish

```bash
rebar3 device publish --device-src src/preloaded --verbose
# or from hyperbeam checkout: rebar3 device publish --device-src src/preloaded/llm
```

See `src/preloaded/llm/dev_llm.erl` for device.

## License

Apache-2.0
