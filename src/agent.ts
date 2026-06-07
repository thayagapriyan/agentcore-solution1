import { Agent, BedrockModel, McpClient } from '@strands-agents/sdk';

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

// Fresh agent per invocation: no conversation state carries across requests
// (sessions arrive in a later iteration). The model + gateway clients are reused.
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
