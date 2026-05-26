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
  "version": "1.0.0",
  "type": "module",
  "scripts": {
    "build": "tsc -p tsconfig.json",
    "start": "node dist/app.js",
    "dev": "tsx watch src/app.ts"
  },
  "dependencies": {
    "@aws-sdk/client-bedrock-runtime": "^3.660.0",
    "@aws/strands-agents": "^0.4.0",
    "@modelcontextprotocol/sdk": "^1.0.0",
    "express": "^4.21.0",
    "zod": "^3.23.0"
  },
  "devDependencies": {
    "@types/express": "^5.0.0",
    "@types/node": "^20.14.0",
    "tsx": "^4.19.0",
    "typescript": "^5.4.0"
  }
}
```

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

```typescript
import { Agent, BedrockModel, McpClient } from "@aws/strands-agents";

const SYSTEM_PROMPT = `You are an AI assistant deployed on Amazon Bedrock AgentCore.
Use your tools to answer questions accurately. If a tool returns no data, say so —
do not invent values. Always cite the tool you used in your answer.`;

export async function createAgent(): Promise<Agent> {
  const model = new BedrockModel({
    modelId: process.env.MODEL_ID ?? "anthropic.claude-3-5-sonnet-20241022-v2:0",
    region: process.env.AWS_REGION ?? "us-east-1",
    temperature: 0.2,
  });

  // Tools come from AgentCore Gateway (managed MCP endpoint).
  // Gateway URL + auth are injected by the runtime via env vars.
  const gatewayUrl = process.env.AGENTCORE_GATEWAY_URL;
  const tools = gatewayUrl
    ? await McpClient.connect({ url: gatewayUrl, transport: "streamable-http" })
    : [];

  return new Agent({
    model,
    tools,
    systemPrompt: SYSTEM_PROMPT,
  });
}
```

---

## `src/app.ts` — HTTP entrypoint (AgentCore contract)

```typescript
import express, { Request, Response } from "express";
import { createAgent } from "./agent.js";
import { InvocationRequest, type InvocationResponse } from "./types.js";
import { randomUUID } from "node:crypto";

const app = express();
app.use(express.json({ limit: "1mb" }));

// Lazy-init: build agent once, reuse across invocations on the warm container
let agentPromise: ReturnType<typeof createAgent> | null = null;
const getAgent = () => (agentPromise ??= createAgent());

// Required by AgentCore — health check
app.get("/ping", (_req, res) => {
  res.status(200).json({ status: "ok" });
});

// Required by AgentCore — invocation entrypoint
app.post("/invocations", async (req: Request, res: Response) => {
  const parsed = InvocationRequest.safeParse(req.body);
  if (!parsed.success) {
    return res.status(400).json({ error: parsed.error.format() });
  }
  const { prompt, sessionId = randomUUID() } = parsed.data;

  try {
    const agent = await getAgent();
    const result = await agent.run(prompt, { sessionId });

    const response: InvocationResponse = {
      result: result.text,
      sessionId,
      usage: result.usage,
    };
    res.status(200).json(response);
  } catch (err) {
    console.error("invocation failed", err);
    res.status(500).json({ error: (err as Error).message });
  }
});

const port = Number(process.env.PORT ?? 8080);
app.listen(port, "0.0.0.0", () => {
  console.log(`agent listening on :${port}`);
});
```

---

## `Dockerfile` — ARM64 Node 20

```dockerfile
# syntax=docker/dockerfile:1.7
FROM --platform=linux/arm64 node:20-bookworm-slim AS build

WORKDIR /app
COPY package*.json tsconfig.json ./
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
HEALTHCHECK --interval=10s --timeout=3s --retries=3 \
  CMD wget -qO- http://127.0.0.1:8080/ping || exit 1

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
