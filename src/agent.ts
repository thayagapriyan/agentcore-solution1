import { Agent, BedrockModel, McpClient, SessionManager } from '@strands-agents/sdk';
import { S3SnapshotStorage } from './s3-snapshot-storage.js';

const SYSTEM_PROMPT = 'You are a helpful assistant.';

// Haiku 4.5 is inference-profile-only on Bedrock (no on-demand throughput),
// so the default is the global cross-region profile, not the bare model id.
const DEFAULT_MODEL_ID = 'global.anthropic.claude-haiku-4-5-20251001-v1:0';

let model: BedrockModel | null = null;

function getModel(): BedrockModel {
  return (model ??= new BedrockModel({
    modelId: process.env.MODEL_ID ?? DEFAULT_MODEL_ID,
    region: process.env.AWS_REGION ?? 'us-east-1',
    temperature: 0.2,
  }));
}

// Gateway is optional forever: tools are connected only when
// AGENTCORE_GATEWAY_URL is set. continueOnError keeps an invocation working
// (with 0 tools) even if the gateway is unreachable or auth fails.
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

// Sessions are optional forever: when SESSION_BUCKET is set, conversation state
// is persisted to S3 (durable, multi-instance) via a SessionManager keyed by
// sessionId — the agent restores prior turns on construction and saves after each
// invocation. When unset, the agent is stateless (original behavior). The S3
// client is reused across requests; a SessionManager is per-session.
let sessionStorage: S3SnapshotStorage | null = null;
let sessionStorageResolved = false;

function getSessionStorage(): S3SnapshotStorage | null {
  if (sessionStorageResolved) return sessionStorage;
  sessionStorageResolved = true;
  const bucket = process.env.SESSION_BUCKET;
  if (bucket) {
    sessionStorage = new S3SnapshotStorage(bucket);
  }
  return sessionStorage;
}

// Fresh Agent per invocation (the Agent carries an invocation lock + history, so
// a shared instance would bleed state across concurrent requests). When a
// sessionId is supplied and storage is configured, a SessionManager hydrates the
// agent from prior turns and persists the updated snapshot afterward.
export function createAgent(sessionId?: string): Agent {
  const client = getGatewayClient();
  const tools = client ? [client] : [];

  const storage = getSessionStorage();
  const sessionManager =
    storage && sessionId
      ? new SessionManager({ sessionId, storage: { snapshot: storage } })
      : undefined;

  return new Agent({
    model: getModel(),
    tools,
    systemPrompt: SYSTEM_PROMPT,
    printer: false,
    ...(sessionManager ? { sessionManager } : {}),
  });
}

// One-time, non-fatal probe so the logs show whether the gateway is wired and
// how many tools it exposes (0 in iter 6 — no targets registered yet).
export async function logGatewayStatus(): Promise<void> {
  const client = getGatewayClient();
  if (!client) {
    console.log('gateway: not configured (AGENTCORE_GATEWAY_URL unset), 0 tools');
    return;
  }
  try {
    const tools = await client.listTools();
    console.log(`gateway: connected, ${tools.length} tools loaded`);
  } catch (err) {
    console.warn(
      'gateway: connection failed, continuing with 0 tools —',
      (err as Error).message,
    );
  }
}
