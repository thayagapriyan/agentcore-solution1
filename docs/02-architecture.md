# 02 — Architecture

How Bedrock AgentCore Runtime works, what its pieces are, and how a TypeScript + Strands agent fits in.

---

## The big picture

```
┌──────────────────────────────────────────────────────────────────┐
│                          End user / app                          │
└────────────────────────────┬─────────────────────────────────────┘
                             │  InvokeAgentRuntime
                             ▼
┌──────────────────────────────────────────────────────────────────┐
│                    Bedrock AgentCore Runtime                     │
│  ┌─────────────────────────────────────────────────────────┐     │
│  │              Your container (ARM64, :8080)              │     │
│  │  ┌─────────────────────────────────────────────────┐    │     │
│  │  │           Express server / Strands Agent         │    │     │
│  │  │   POST /invocations   GET /ping                  │    │     │
│  │  └────────────┬──────────────────┬─────────────────┘    │     │
│  │               │                  │                      │     │
│  └───────────────┼──────────────────┼──────────────────────┘     │
│                  │                  │                            │
└──────────────────┼──────────────────┼────────────────────────────┘
                   │                  │
        ┌──────────▼─────┐    ┌───────▼────────┐
        │ Bedrock        │    │ AgentCore      │
        │ InvokeModel    │    │ Gateway (MCP)  │
        │ (Claude)       │    │                │
        └────────────────┘    └───────┬────────┘
                                      │
                              ┌───────▼─────────┐
                              │ Tool backends:  │
                              │ Lambda, REST,   │
                              │ DynamoDB, etc.  │
                              └─────────────────┘
```

---

## Components

### 1. AgentCore Runtime

The managed host. You give it an ECR image and an execution role; it gives you back an `AgentRuntimeArn` you can call with `InvokeAgentRuntime`.

Responsibilities:
- Spin up your container on demand
- Route invoke requests to your `:8080/invocations`
- Maintain session affinity (same `sessionId` → same warm container instance)
- Stream responses back to caller (SSE)
- Emit traces/spans to CloudWatch + X-Ray
- Auto-scale based on session count

You do **not** manage: instances, scaling, load balancing, TLS, or session storage.

### 2. AgentCore Gateway

Managed MCP endpoint. You register tools once (REST APIs, Lambda functions, OpenAPI specs, Smithy specs) and Gateway exposes them as MCP tools the agent can discover and call.

Replaces the "spawn MCP server as subprocess" pattern — that pattern doesn't work in AgentCore because the container is long-lived and shared across sessions.

### 3. AgentCore Memory (optional)

Managed long-term memory store. Persists across sessions, keyed by user/actor. Use when you need preferences, history, or summaries to outlive a single session.

### 4. AgentCore Identity (optional)

OAuth/OIDC token broker. The runtime can hold tokens for downstream services (Google, Slack, GitHub, custom OAuth) and inject them into tool calls without your code touching credentials.

### 5. Observability

Built-in. Every invocation produces:
- A **trace** with spans for model calls, tool calls, and your own custom spans
- **CloudWatch logs** from your container's stdout/stderr
- **Metrics**: latency p50/p99, error rate, tokens in/out

---

## Request lifecycle

```
1. Client → InvokeAgentRuntime(arn, payload, sessionId)
2. Runtime → routes to a warm or cold container instance
3. Container → POST /invocations { prompt, sessionId, ... }
4. Strands Agent.run(prompt)
     ├─ calls Bedrock InvokeModel (Claude)
     ├─ may call MCP tools via Gateway
     └─ may read/write AgentCore Memory
5. Container → returns JSON (or streams SSE)
6. Runtime → forwards response to client + records trace
```

Cold starts: ~2–5s for a small Node image. Warm invocations: <100ms overhead on top of model latency.

---

## How TypeScript + Strands fits

[Strands](https://strandsagents.com/) is an open-source agent framework that:
- Wraps `bedrock-runtime` for model calls
- Handles the reason-act loop, tool calling, retries
- Speaks MCP natively — point it at the Gateway URL and tools auto-load

Your agent code is ~30 lines of TypeScript that:
1. Instantiates a Strands `Agent` with model + MCP endpoint
2. Wires it to Express `POST /invocations`
3. Lets Strands handle everything else

Full code in [03-agent-code.md](03-agent-code.md).

---

## Key design decisions

### Container, not Lambda
AgentCore containers are long-lived (minutes to hours of warm state per session). Lambda's 15-min ceiling and cold-per-invocation model don't fit. The trade-off: you pay for the container while idle (cents/hour) but get sub-100ms warm latency and persistent in-memory state.

### Gateway instead of subprocess MCP servers
Spawning `node mcp-server/index.js` per invocation works in Lambda but breaks under AgentCore's shared-container model. Gateway centralizes tool definitions, handles auth, and gives you per-tool metrics.

### IAM-only by default, OAuth when needed
Use IAM for service-to-service (agent → Lambda, agent → DynamoDB). Use AgentCore Identity when the agent needs to act on behalf of a user against an OAuth-protected API.

### ARM64
Cheaper, lower-latency. AgentCore enforces it. Docker buildx + QEMU handles cross-builds from x86 dev machines.

---

## What this replaces in a legacy Bedrock Agents project

| Legacy piece | AgentCore replacement |
|---|---|
| `aws_bedrockagent_agent` | `aws_bedrockagentcore_runtime` |
| Action group + Lambda | Tools registered with Gateway |
| Lambda zip | OCI image in ECR |
| Action-group instruction prompt | System prompt in your Strands code |
| Session state in DynamoDB (DIY) | AgentCore Memory |
| CloudWatch log scraping | Built-in traces + spans |

Migration walkthrough in [06-migration.md](06-migration.md).

Next: [03-agent-code.md](03-agent-code.md).
