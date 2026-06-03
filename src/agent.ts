import { Agent, BedrockModel } from '@strands-agents/sdk';

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

// Fresh agent per invocation: no conversation state carries across requests
// (sessions arrive in a later iteration). The model client is reused.
export function createAgent(): Agent {
  return new Agent({
    model: getModel(),
    tools: [],
    systemPrompt: SYSTEM_PROMPT,
    printer: false,
  });
}
