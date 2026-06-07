# 03 — Agent Code (TypeScript + Node.js + Strands)

The TypeScript code, project layout, and Dockerfile for an AgentCore-compatible Strands agent.

---

## Project layout

```
agentcore-solution1/
├── src/
│   ├── app.ts                 # HTTP server — AgentCore entrypoint
│   ├── agent.ts               # Strands agent factory
│   └── types.ts               # Shared request/response types
├── Dockerfile
├── .dockerignore
├── package.json
├── tsconfig.json
└── infra/                     # (see 04-terraform.md)
```

---

## `package.json`

```json
{
  "name": "agentcore-solution1",
  "version": "0.1.0",
  "type": "module",
  "scripts": {
    "build": "tsc -p tsconfig.json",
    "start": "node dist/app.js",
    "dev": "tsc && node dist/app.js",
    "clean": "rimraf dist"
  },
  "dependencies": {
    "@strands-agents/sdk": "^1.4.0",
    "@modelcontextprotocol/sdk": "^1.29.0",
    "@opentelemetry/api": "^1.9.1",
    "express": "^4.19.0",
    "zod": "^4.4.3"
  },
  "devDependencies": {
    "@types/express": "^4.17.21",
    "@types/node": "^20.14.0",
    "rimraf": "^5.0.10",
    "typescript": "^5.4.0"
  }
}
```

> The published Strands TypeScript SDK is **`@strands-agents/sdk`** (not
> `@aws/strands-agents`). `zod`, `@modelcontextprotocol/sdk`, and
> `@opentelemetry/api` are **required** (non-optional) peer dependencies of the
> SDK — the package barrel imports them at runtime, so they must be installed
> directly. `@aws-sdk/client-bedrock-runtime` ships transitively with the SDK.
>
> The SDK also declares `express@^5.1.0` and `@a2a-js/sdk` as *optional* peers.
> They trip npm's strict peer resolver against our Express 4 pin, so add an
> `.npmrc` with `legacy-peer-deps=true` (committed, and `COPY`'d into the Docker
> build so the in-container `npm ci` resolves identically).

---

## `tsconfig.json`

```json
{
  "compilerOptions": {
    "target": "ES2022",
    "module": "NodeNext",
    "moduleResolution": "NodeNext",
    "outDir": "dist",
    "rootDir": "src",
    "esModuleInterop": true,
    "strict": true,
    "skipLibCheck": true,
    "resolveJsonModule": true,
    "declaration": false,
    "sourceMap": true
  },
  "include": ["src/**/*"],
  "exclude": ["node_modules", "dist"]
}
```

---

## `src/types.ts`

```typescript
import { z } from "zod";

export const InvocationRequest = z.object({
  prompt: z.string().min(1),
  sessionId: z.string().optional(),
  actorId: z.string().optional(),
  metadata: z.record(z.unknown()).optional(),
});

export type InvocationRequest = z.infer<typeof InvocationRequest>;

export interface InvocationResponse {
  result: string;
  sessionId: string;
  usage?: { inputTokens: number; outputTokens: number };
}
```

---

## `src/agent.ts` — Strands agent factory

As shipped in iter 6 — `BedrockModel` plus an **optional** Gateway `McpClient`.
The `Agent` is created **per invocation** (it carries conversation history and an
invocation lock, so a shared instance would bleed state across requests); the
`BedrockModel` and `McpClient` clients are reused across invocations.

The Gateway connection is **conditional**: tools are wired only when
`AGENTCORE_GATEWAY_URL` is set, and `continueOnError: true` keeps an invocation
working (with 0 tools) even if the gateway is unreachable or auth fails — so the
agent runs identically whether or not a gateway exists.

```typescript
import { Agent, BedrockModel, McpClient } from "@strands-agents/sdk";

const SYSTEM_PROMPT = "You are a helpful assistant.";

// Claude Haiku 4.5 is inference-profile-only on Bedrock (no on-demand
// throughput), so the default is the global cross-region profile, not the bare
// model id. Override per environment with MODEL_ID.
const DEFAULT_MODEL_ID = "global.anthropic.claude-haiku-4-5-20251001-v1:0";

let model: BedrockModel | null = null;

function getModel(): BedrockModel {
  return (model ??= new BedrockModel({
    modelId: process.env.MODEL_ID ?? DEFAULT_MODEL_ID,
    region: process.env.AWS_REGION ?? "us-east-1",
    temperature: 0.2,
  }));
}

// Gateway is optional forever: connected only when AGENTCORE_GATEWAY_URL is set.
let gatewayResolved = false;
let gatewayClient: McpClient | null = null;

function getGatewayClient(): McpClient | null {
  if (gatewayResolved) return gatewayClient;
  gatewayResolved = true;
  const url = process.env.AGENTCORE_GATEWAY_URL;
  if (url) {
    gatewayClient = new McpClient({ url, continueOnError: true });
  }
  return gatewayClient;
}

export function createAgent(): Agent {
  const client = getGatewayClient();
  const tools = client ? [client] : [];
  return new Agent({
    model: getModel(),
    tools,
    systemPrompt: SYSTEM_PROMPT,
    printer: false,
  });
}

// One-time, non-fatal probe so logs show whether the gateway is wired and how
// many tools it exposes. Called once after the server starts listening.
export async function logGatewayStatus(): Promise<void> {
  const client = getGatewayClient();
  if (!client) {
    console.log("gateway: not configured (AGENTCORE_GATEWAY_URL unset), 0 tools");
    return;
  }
  try {
    const tools = await client.listTools();
    console.log(`gateway: connected, ${tools.length} tools loaded`);
  } catch (err) {
    console.warn(
      "gateway: connection failed, continuing with 0 tools —",
      (err as Error).message,
    );
  }
}
```

> **Tools (iter 7+):** the `McpClient` exposes whatever tool targets are
> registered on the Gateway in Terraform (`aws_bedrockagentcore_gateway_target`).
> No agent-code change is needed to add a tool — `listTools()` picks it up once
> the target is applied. Until then the agent runs with 0 tools.

---

## `src/app.ts` — HTTP entrypoint (AgentCore contract)

```typescript
import express from "express";
import { randomUUID } from "node:crypto";
import { createAgent, logGatewayStatus } from "./agent.js";

const app = express();
const port = parseInt(process.env.PORT ?? "8080", 10);

// AgentCore forwards the invocation payload without a reliable Content-Type
// header, so parse every request body as JSON rather than gating on the type.
// (The default express.json() only parses application/json — under AgentCore it
// left req.body empty and every invoke returned 400.)
app.use(express.json({ type: () => true }));

// Required by AgentCore — health check
app.get("/ping", (_req, res) => {
  res.json({ status: "ok" });
});

// Required by AgentCore — invocation entrypoint
app.post("/invocations", async (req, res) => {
  const prompt = req.body?.prompt;
  if (typeof prompt !== "string" || prompt.trim() === "") {
    res.status(400).json({ error: "prompt is required" });
    return;
  }
  const sessionId =
    typeof req.body?.sessionId === "string" ? req.body.sessionId : randomUUID();

  try {
    const agent = createAgent();
    const result = await agent.invoke(prompt);
    res.json({ result: result.toString(), sessionId });
  } catch (err) {
    console.error("invocation failed", err);
    res.status(500).json({ error: (err as Error).message });
  }
});

app.listen(port, () => {
  console.log(`listening on :${port}`);
  // One-time gateway probe (non-fatal) so the logs show tool status at boot.
  void logGatewayStatus();
});
```

> `agent.invoke(prompt)` returns an `AgentResult`; `result.toString()` extracts
> the text. The response shape stays `{ result, sessionId }` (the `usage` field
> defined in iter 1 is wired up in a later observability iteration). `sessionId`
> is echoed now so the session iteration can attach state without changing
> callers. The `types.ts` zod schema above is an optional reference — the
> shipped handler inlines minimal validation to keep the dependency surface small.

---

## `Dockerfile` — ARM64 Node 20

```dockerfile
# syntax=docker/dockerfile:1.7
FROM --platform=linux/arm64 node:20-bookworm-slim AS build

WORKDIR /app
COPY package*.json tsconfig.json .npmrc ./
RUN npm ci

COPY src ./src
RUN npm run build && npm prune --omit=dev

# ---------- runtime ----------
FROM --platform=linux/arm64 node:20-bookworm-slim AS runtime

WORKDIR /app
ENV NODE_ENV=production
ENV PORT=8080

COPY --from=build /app/node_modules ./node_modules
COPY --from=build /app/dist ./dist
COPY --from=build /app/package.json ./package.json

# Run as non-root (AgentCore best practice)
RUN useradd --create-home --uid 1001 agent
USER agent

EXPOSE 8080
# node:20-bookworm-slim ships node but not wget/curl, so probe with node's fetch.
HEALTHCHECK --interval=10s --timeout=3s --retries=3 \
  CMD node -e "fetch('http://127.0.0.1:8080/ping').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"

CMD ["node", "dist/app.js"]
```

---

## `.dockerignore`

```
node_modules
dist
.git
.env
.env.*
*.log
.vscode
docs
infra
```

---

## Local smoke test (before pushing to ECR)

```bash
# Build for your host arch first to catch errors fast
docker build -t agent:local .

# Run it
docker run --rm -p 8080:8080 \
  -e AWS_REGION=us-east-1 \
  -e AWS_ACCESS_KEY_ID=$AWS_ACCESS_KEY_ID \
  -e AWS_SECRET_ACCESS_KEY=$AWS_SECRET_ACCESS_KEY \
  -e AWS_SESSION_TOKEN=$AWS_SESSION_TOKEN \
  agent:local

# In another terminal:
curl http://localhost:8080/ping
curl -X POST http://localhost:8080/invocations \
  -H 'Content-Type: application/json' \
  -d '{"prompt": "hello"}'
```

If `/ping` returns 200 and `/invocations` returns a model response, you're ready for the real ARM64 build (covered in [05-deployment.md](05-deployment.md)).

---

## Environment variables the runtime provides

AgentCore injects these into your container at start:

| Variable | Source | Purpose |
|----------|--------|---------|
| `AWS_REGION` | runtime config | Region for SDK calls |
| `AWS_CONTAINER_CREDENTIALS_FULL_URI` | runtime | Auto-rotated execution-role creds |
| `AWS_CONTAINER_AUTHORIZATION_TOKEN` | runtime | Paired with the URI above |
| `AGENTCORE_RUNTIME_ARN` | runtime | Self-reference |
| `AGENTCORE_GATEWAY_URL` | your config (Terraform) | MCP endpoint for tools |
| `MODEL_ID` | your config | Override default model |

Your code reads them via `process.env` — no extra setup. The SDK auto-uses `AWS_CONTAINER_CREDENTIALS_FULL_URI` for IAM creds.

Next: [04-terraform.md](04-terraform.md).
