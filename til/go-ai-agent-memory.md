# Go AI Agents with Persistent Memory

Go's concurrency primitives (goroutines) and low memory footprint make it well-suited for scaling autonomous agents that perform hundreds of LLM calls per hour.

## Table Of Contents

<!-- toc -->
- [Frameworks](#frameworks)
  - [go-agent (Protocol-Lattice)](#go-agent-protocol-lattice)
  - [Google ADK for Go](#google-adk-for-go)
  - [CloudWeGo Eino](#cloudwego-eino)
  - [go-agent-memory (Framehood)](#go-agent-memory-framehood)
- [Memory Architecture](#memory-architecture)
- [Minimal Implementation](#minimal-implementation)
- [Why Go Over Python](#why-go-over-python)
- [Framework Comparison](#framework-comparison)
- [References](#references)
<!-- /toc -->

## Frameworks

### go-agent (Protocol-Lattice)
Production-ready agent framework with graph-aware memory and pluggable persistence (Qdrant, PostgreSQL, MongoDB, Neo4j). Uses UTCP (Universal Tool Calling Protocol) for agent-to-agent tool exposure.

- [GitHub: Protocol-Lattice/go-agent][1]

### Google ADK for Go
Official Google framework for code-first AI agents. Modular memory service via `--memory_service_uri` flag. Model-agnostic, cloud-native ready.

- [GitHub: google/adk-go][4]
- [ADK Sessions/Memory Docs](https://adk.dev/sessions/memory/)

### CloudWeGo Eino
LangChain-inspired Go framework with graph-based workflows. Supports human-in-the-loop interruptions and state preservation.

- [GitHub: cloudwego/eino][3]

### go-agent-memory (Framehood)
Standalone memory layer for existing agent engines. Supports session-only, persistent (PostgreSQL + pgvector), and hybrid (Redis + PostgreSQL) modes.

- [GitHub: Framehood/go-agent-memory](https://github.com/Framehood/go-agent-memory)

## Memory Architecture

Three-tier persistence model:

```
Short-Term Context → In-memory slice (per LLM call)
        ↓
Episodic Memory    → Thread/session logs (Redis/PostgreSQL)
        ↓
Semantic Memory    → Vector embeddings (Qdrant/pgvector)
```

1. **Short-Term**: Go slices of message structs for single conversation turn
2. **Episodic**: Historical interactions in key-value stores (Redis/PostgreSQL)
3. **Semantic**: Facts/preferences as vector embeddings for long-term recall

## Minimal Implementation

```go
package main

import (
	"fmt"
	"time"
)

type MemoryItem struct {
	ID        string
	Content   string
	Embedding []float32
	Timestamp time.Time
}

type AgentMemory struct {
	SessionID string
	ShortTerm []string
	VectorDB  map[string]MemoryItem
}

func NewAgentMemory(sessionID string) *AgentMemory {
	return &AgentMemory{
		SessionID: sessionID,
		ShortTerm: make([]string, 0),
		VectorDB:  make(map[string]MemoryItem),
	}
}

func (m *AgentMemory) AddEpisodic(message string) {
	m.ShortTerm = append(m.ShortTerm, message)
}

func (m *AgentMemory) CommitToLongTerm(id, fact string) {
	m.VectorDB[id] = MemoryItem{
		ID:        id,
		Content:   fact,
		Embedding: []float32{0.12, -0.43, 0.89}, // Mock vector
		Timestamp: time.Now(),
	}
}

func (m *AgentMemory) Recall(query string) []string {
	var results []string
	for _, item := range m.VectorDB {
		results = append(results, item.Content)
	}
	return results
}

func main() {
	memory := NewAgentMemory("session_12345")

	// Episodic: immediate context
	memory.AddEpisodic("User: My server IP is 192.168.1.50")

	// Semantic: persist for long-term recall
	memory.CommitToLongTerm("srv_ip", "User's server IP is 192.168.1.50")

	// Recall in future session
	fmt.Printf("Recalled: %v\n", memory.Recall("server address?"))
}
```

## Why Go Over Python

- **No GIL**: Thousands of goroutines query/commit vector memories concurrently without blocking
- **Type Safety**: Structured memory schemas enforce strict boundaries on LLM output parsing
- **Lower Cost**: Go binaries use fraction of Python container RAM

## Framework Comparison

| Framework | Focus | Memory Engine | Best For |
|-----------|-------|---------------|----------|
| [go-agent][1] | Graph/multi-agent routing | Graph-aware native | Dynamic RAG & tool networks |
| [tRPC-Agent-Go][2] | High-throughput microservices | Isolated state services | High-traffic backends |
| [Eino][3]/[ADK][4] | Enterprise scaling | Modular external hooks | Compliance-heavy workflows |

## References

- [agno-Go](https://github.com/rexleimo/agno-Go)
- [Building Autonomous AI Agents in Golang](https://codingplainenglish.medium.com/building-autonomous-ai-agents-in-golang-a-practical-guide-7332940a6607)
- [Reddit: AI Agent with Memory in Go](https://www.reddit.com/r/golang/comments/1nfu08z/whats_the_best_way_to_develop_an_ai_agent_with_a/)
- [ML Libraries in Golang](https://www.opensourceforu.com/2021/04/the-best-machine-learning-libraries-in-golang/)
- [Go Syntax Basics](https://www.linkedin.com/pulse/gogolang-101-syntax-basics-alex-merced)
- [Reddit: Introducing go-agent](https://www.reddit.com/r/golang/comments/1p5kax0/introducing_goagent_an_opensource_agentic/)
- [Lattice Agent Framework](https://www.reddit.com/r/vibecoding/comments/1ofrpmw/lattice_agent_ai_agent_framework_with_memory/)
- [Best AI Agent Frameworks](https://brightdata.com/blog/ai/best-ai-agent-frameworks)
- [Google Blog: ADK for Go](https://developers.googleblog.com/announcing-the-agent-development-kit-for-go-build-powerful-ai-agents-with-your-favorite-languages/)
- [ADK-Go OpenAI Adapter](https://pkg.go.dev/github.com/jiatianzhao/adk-go-openai)
- [ADK Communication Context Management](https://medium.com/@shins777/adk-communication-context-management-method-c105cf4add27)
- [Agent Memory vs Context Engineering](https://www.augmentcode.com/guides/agent-memory-vs-context-engineering)
- [IBM: AI Agent Memory](https://www.ibm.com/think/topics/ai-agent-memory)
- [YouTube: Agent Memory Deep Dive](https://www.youtube.com/watch?v=3aS1A-0775s)
- [MongoDB: Agent Memory](https://www.mongodb.com/resources/basics/artificial-intelligence/agent-memory)
- [Agentic Memory Infrastructure](https://medium.com/codex/agentic-memory-the-infrastructure-layer-that-makes-or-breaks-ai-pipelines-48a17d344c34)
- [AWS Bedrock AgentCore Memory](https://dev.to/sampathkaran/aws-bedrock-agentcore-memory-give-your-ai-agent-a-brain-that-actually-remembers-12ie)

[1]: https://github.com/Protocol-Lattice/go-agent
[2]: https://github.com/trpc-group/trpc-agent-go
[3]: https://github.com/cloudwego/eino
[4]: https://github.com/google/adk-go
