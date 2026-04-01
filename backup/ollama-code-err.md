jerry@jerrymacmini ollama-code % export ANTHROPIC_BASE_URL=http://localhost:9099
export ANTHROPIC_API_KEY=local-ollama-bridge
claude --model qwen3:14b
╭─── Claude Code v2.1.89 ───────────────────────────────────────────────────────────────────────────────╮
│                                   │ Tips for getting started                                          │
│           Welcome back!           │ Run /init to create a CLAUDE.md file with instructions for Claude │
│                                   │ ───────────────────────────────────────────────────────────────── │
│              ▐▛███▜▌              │ Recent activity                                                   │
│             ▝▜█████▛▘             │ No recent activity                                                │
│               ▘▘ ▝▝               │                                                                   │
│                                   │                                                                   │
│   qwen3:14b · API Usage Billing   │                                                                   │
│         ~/dev/ollama-code         │                                                                   │
╰───────────────────────────────────────────────────────────────────────────────────────────────────────╯

  ↑ Opus now defaults to 1M context · 5x more room, same pricing
  ⎿  SessionStart:startup hook error

❯ 현재 디렉토리의 브릿지 코드를 분석하여 claude 실행 시 SessionStart:startup hook error 오류가 발생하는 원인을 찾아
개선방안을 제안하라.

⏺ There's an issue with the selected model (qwen3:14b). It may not exist or you may not have access to it. Run /model
  to pick a different model.

───────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
❯ 
───────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
  ? for shortcuts

----

질문을 하면, 아래와 같이 모델을 못찾음
⏺ There's an issue with the selected model (claude-sonnet-4-6). It may not exist or you may not have access to it. Run
  /model to pick a different model.

❯ /model

───────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
  Select model
  Switch between Claude models. Applies to this session and future Claude Code sessions. For other/previous model
  names, specify with --model.

  ❯ 1. Default (recommended) ✔  Use the default model (currently Sonnet 4.6) · $3/$15 per Mtok
    2. Sonnet (1M context)      Sonnet 4.6 for long sessions · $3/$15 per Mtok
    3. Opus (1M context)        Opus 4.6 with 1M context · Most capable for complex work
    4. Haiku                    Haiku 4.5 · Fastest for quick answers · $1/$5 per Mtok

  ◐ Medium effort (default) ← → to adjust

이때 터미널에서 확인하면 ollama qwen3:14b가 로드되어있지 않는 듯
jerry@jerrymacmini ollama-code % ollama ps
2026/04/01 18:21:24 WARN MLX dynamic library not available error="failed to load MLX dynamic library (searched: [/opt/homebrew/Cellar/ollama/0.16.2/bin /Users/jerry/dev/ollama-code/build/lib/ollama])"
NAME    ID    SIZE    PROCESSOR    CONTEXT    UNTIL
jerry@jerrymacmini ollama-code %

----

jerry@jerrymacmini ollama-code % ollama list
2026/04/01 18:06:08 WARN MLX dynamic library not available error="failed to load MLX dynamic library (searched: [/opt/homebrew/Cellar/ollama/0.16.2/bin /Users/jerry/dev/ollama-code/build/lib/ollama])"
NAME                    ID              SIZE     MODIFIED
glm-4.7-flash:latest    d1a8a26252f1    19 GB    5 weeks ago
jerry@jerrymacmini ollama-code % ollama ps
2026/04/01 18:06:22 WARN MLX dynamic library not available error="failed to load MLX dynamic library (searched: [/opt/homebrew/Cellar/ollama/0.16.2/bin /Users/jerry/dev/ollama-code/build/lib/ollama])"
NAME    ID    SIZE    PROCESSOR    CONTEXT    UNTIL
jerry@jerrymacmini ollama-code % ollama pull qwen3:14b
2026/04/01 18:06:36 WARN MLX dynamic library not available error="failed to load MLX dynamic library (searched: [/opt/homebrew/Cellar/ollama/0.16.2/bin /Users/jerry/dev/ollama-code/build/lib/ollama])"
pulling manifest
pulling a8cc1361f314: 100% ▕█████████████████████████████████████████████████████████▏ 9.3 GB
pulling ae370d884f10: 100% ▕█████████████████████████████████████████████████████████▏ 1.7 KB
pulling d18a5cc71b84: 100% ▕█████████████████████████████████████████████████████████▏  11 KB
pulling cff3f395ef37: 100% ▕█████████████████████████████████████████████████████████▏  120 B
pulling 78b3b822087d: 100% ▕█████████████████████████████████████████████████████████▏  488 B
verifying sha256 digest
writing manifest
success
jerry@jerrymacmini ollama-code % ollama pull nomic-embed-text
2026/04/01 18:09:48 WARN MLX dynamic library not available error="failed to load MLX dynamic library (searched: [/opt/homebrew/Cellar/ollama/0.16.2/bin /Users/jerry/dev/ollama-code/build/lib/ollama])"
pulling manifest
pulling 970aa74c0a90: 100% ▕█████████████████████████████████████████████████████████▏ 274 MB
pulling c71d239df917: 100% ▕█████████████████████████████████████████████████████████▏  11 KB
pulling ce4a164fc046: 100% ▕█████████████████████████████████████████████████████████▏   17 B
pulling 31df23ea7daa: 100% ▕█████████████████████████████████████████████████████████▏  420 B
verifying sha256 digest
writing manifest
success
jerry@jerrymacmini ollama-code % python3 rag_indexer.py index --dirs .
  Indexed CLAUDE_CODE_LOCAL_OLLAMA_BRIDGE.md (96 chunks)
  Indexed README.md (8 chunks)
  Indexed run_full_bridge.sh (21 chunks)
  Indexed BRIDGE_FULL_GUIDE.md (32 chunks)
  Indexed bridge_proxy_full.py (192 chunks)
  Indexed MAC_MINI_M4_OLLAMA_AGENT.md (111 chunks)
  Indexed rag_indexer.py (28 chunks)

Indexed 7 new/changed files, 488 new chunks.
Saved 488 chunks to .bridge_rag_index.json
Done in 12.3s
jerry@jerrymacmini ollama-code % PRIMARY_MODEL=qwen3:14b ./run_full_bridge.sh
╔══════════════════════════════════════════════╗
║  bridge_proxy_full.py — Full Anthropic Bridge ║
╚══════════════════════════════════════════════╝

[INFO]  Checking Ollama at http://localhost:11434...
[INFO]  Ollama is running
[INFO]  Checking primary model: qwen3:14b
[WARN]  Model 'qwen3:14b' not found — pulling...
2026/04/01 18:10:36 WARN MLX dynamic library not available error="failed to load MLX dynamic library (searched: [/opt/homebrew/Cellar/ollama/0.16.2/bin /Users/jerry/dev/ollama-code/build/lib/ollama])"
pulling manifest
pulling a8cc1361f314: 100% ▕█████████████████████████████████████████████████████████▏ 9.3 GB
pulling ae370d884f10: 100% ▕█████████████████████████████████████████████████████████▏ 1.7 KB
pulling d18a5cc71b84: 100% ▕█████████████████████████████████████████████████████████▏  11 KB
pulling cff3f395ef37: 100% ▕█████████████████████████████████████████████████████████▏  120 B
pulling 78b3b822087d: 100% ▕█████████████████████████████████████████████████████████▏  488 B
verifying sha256 digest
writing manifest
success
[INFO]  Primary model ready: qwen3:14b
[INFO]  Checking embedding model: nomic-embed-text
[WARN]  Embedding model 'nomic-embed-text' not found — pulling...
2026/04/01 18:10:37 WARN MLX dynamic library not available error="failed to load MLX dynamic library (searched: [/opt/homebrew/Cellar/ollama/0.16.2/bin /Users/jerry/dev/ollama-code/build/lib/ollama])"
pulling manifest
pulling 970aa74c0a90: 100% ▕█████████████████████████████████████████████████████████▏ 274 MB
pulling c71d239df917: 100% ▕█████████████████████████████████████████████████████████▏  11 KB
pulling ce4a164fc046: 100% ▕█████████████████████████████████████████████████████████▏   17 B
pulling 31df23ea7daa: 100% ▕█████████████████████████████████████████████████████████▏  420 B
verifying sha256 digest
writing manifest
success
[INFO]  Warming up model in memory...
[INFO]  Thinking mode: ENABLED (model supports native reasoning)
Index: .bridge_rag_index.json
  Files:      7
  Chunks:     488
  Total text: 241,400 chars (~60,350 tokens)
  Embed dim:  768
  Index size: 7.8 MB

Top files by chunk count:
   192  bridge_proxy_full.py
   111  MAC_MINI_M4_OLLAMA_AGENT.md
    96  CLAUDE_CODE_LOCAL_OLLAMA_BRIDGE.md
    32  BRIDGE_FULL_GUIDE.md
    28  rag_indexer.py
    21  run_full_bridge.sh
     8  README.md

┌─────────────────────────────────────────────┐
│  Bridge proxy starting on port 9099       │
│                                             │
│  export ANTHROPIC_BASE_URL=http://localhost:9099  │
│  export ANTHROPIC_API_KEY=local-ollama-bridge │
│                                             │
│  Model: qwen3:14b                   │
└─────────────────────────────────────────────┘

Features enabled:
  ✓ Prompt cache simulation (static/dynamic boundary)
  ✓ Vector RAG (nomic-embed-text)
  ✓ KAIROS background watcher
  ✓ COORDINATOR_MODE (task decomposition)
  ✓ TRANSCRIPT_CLASSIFIER (safety scoring)
  ✓ ULTRAPLAN (complexity detection)
  ✓ TEAMMEM (persistent memory)
  ✓ Context Compaction (auto-summarize long sessions)
  ✓ Qwen3 Thinking Mode (native reasoning via options)
  ✓ Parallel MCP Tool Execution (agentic loop)
  ○ VERIFICATION_AGENT (disabled by default, add --enable-verification)

Model: qwen3:14b
  RAM guide: qwen3:4b (8GB) | qwen3:8b (16GB) | qwen3:14b (32GB) | qwen3:32b (64GB+)

Press Ctrl+C to stop.

2026-04-01 18:10:51,184 [INFO] bridge: Starting bridge proxy on 0.0.0.0:9099
2026-04-01 18:10:51,184 [INFO] bridge: Primary model: qwen3:14b | Embed: nomic-embed-text
2026-04-01 18:10:51,238 [INFO] bridge: RAG: loaded 488 chunks from index
2026-04-01 18:10:51,238 [INFO] bridge: KAIROS: daemon started (tick=30.0s)
2026-04-01 18:10:51,238 [INFO] bridge: KAIROS: daemon started
2026-04-01 18:10:55,086 [INFO] bridge: Bridge proxy ready. Set: ANTHROPIC_BASE_URL=http://localhost:9099
