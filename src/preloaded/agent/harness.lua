-- harness.lua — AO agent harness for HyperBEAM
-- Demonstrates: llm@1.0 + relay@1.0 + cache/store + query@1.0 + lua bash
-- Load: aos <PROC> < src/preloaded/agent/harness.lua

-- 1. Ingest Daily Agents News → cache + index
Handlers.add("ingest-dan", Handlers.utils.hasMatchingTag("Action", "IngestDAN"), function(msg)
  print("Harness: fetching dan-feed via harness@1.0...")
  local ok, res = pcall(function()
    return ao.resolve({device="harness@1.0", path="ingest"})
  end)
  if not ok then
    print("ingest failed: "..tostring(res))
    Send({Target=msg.From, Data="ingest failed: "..tostring(res)})
    return
  end
  local ingested = res.ingested or res["ingested"] or 0
  print("Ingested "..tostring(ingested).." posts to dan/posts/*")
  -- Summarize via LLM (spark qwen3.6 default)
  local s_ok, s_res = pcall(function()
    return ao.resolve({device="llm@1.0", path="generate", prompt="Summarize these "..tostring(ingested).." Daily Agents News posts in 3 bullet points", model="qwen3.6"})
  end)
  local summary = ""
  if s_ok then summary = s_res.content or s_res.Content or "" end
  Send({Target=msg.From, Data="Ingested "..tostring(ingested).." posts. Summary: "..summary})
end)

-- 2. Query cache (query@1.0 style via harness)
Handlers.add("query-dan", Handlers.utils.hasMatchingTag("Action", "QueryDAN"), function(msg)
  local q = msg.Tags.Query or msg.Data or ""
  local ok, res = ao.resolve({device="harness@1.0", path="query", q=q})
  if not ok then Send({Target=msg.From, Data="query failed"}); return end
  local results = res.results or {}
  Send({Target=msg.From, Data=require("json").encode({count=res.count or #results, q=q, results=results})})
end)

Handlers.add("list-dan", Handlers.utils.hasMatchingTag("Action", "ListDAN"), function(msg)
  local ok, res = ao.resolve({device="harness@1.0", path="list"})
  Send({Target=msg.From, Data=require("json").encode(res)})
end)

-- 3. Agent loop: llm decides, relay acts, cache stores, query indexes
Handlers.add("agent-run", Handlers.utils.hasMatchingTag("Action", "AgentRun"), function(msg)
  local prompt = msg.Data or msg.Tags.Prompt or "What should the agent do next?"
  -- LLM decides
  local ok, llm = ao.resolve({device="llm@1.0", path="chat", prompt=prompt, model="qwen3.6"})
  if not ok then Send({Target=msg.From, Data="llm failed"}); return end
  local body = llm.body or ""
  local decoded = require("json").decode(body)
  local plan = decoded.choices and decoded.choices[1].message.content or body
  print("Agent plan: "..string.sub(plan,1,200))
  -- Relay to external tool (example: fetch dan-feed via relay)
  local r_ok, r_res = ao.resolve({device="relay@1.0", path="call", ["relay-path"]="https://hyperio-mc.github.io/dan-feed/feed.xml", ["relay-method"]="GET"})
  local tool_out = r_ok and (r_res.body or "") or "relay failed"
  -- Store to cache via harness
  ao.resolve({device="harness@1.0", path="store", posts={{guid="agent-"..tostring(math.random(100000)), title="Agent run", link="", description=plan}}})
  Send({Target=msg.From, Data="Plan: "..string.sub(plan,1,300).."\nTool bytes: "..tostring(#tool_out)})
end)

-- 4. Bash-like via lua (lua is the bash)
Handlers.add("bash", Handlers.utils.hasMatchingTag("Action", "Bash"), function(msg)
  local cmd = msg.Data or ""
  -- In HyperBEAM lua, os.execute is sandboxed, but you can use ao.resolve to subprocess via wasi if needed
  -- For demo, just echo via llm
  local ok, res = ao.resolve({device="llm@1.0", path="generate", prompt="Explain how to run in bash: "..cmd, model="qwen3.6"})
  Send({Target=msg.From, Data=res.content or ""})
end)

print("Harness loaded: IngestDAN, QueryDAN, ListDAN, AgentRun, Bash — llm+relay+cache+query")
