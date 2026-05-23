// ============================================================================
// _shared/ai/providers/anthropic.ts · Adaptador Anthropic (Claude Messages API)
// ----------------------------------------------------------------------------
// POST {base}/v1/messages  · headers: x-api-key, anthropic-version.
// El system va en el campo `system` (no como mensaje).
// ============================================================================

import { AiProviderError } from "../types.ts";
import type { AdapterParams, AdapterResult } from "../types.ts";

const DEFAULT_BASE = "https://api.anthropic.com";
const ANTHROPIC_VERSION = "2023-06-01";

export const anthropicAdapter = async (
  p: AdapterParams,
): Promise<AdapterResult> => {
  const base = p.baseUrl ?? DEFAULT_BASE;
  const url = `${base}/v1/messages`;

  const messages = p.messages
    .filter((m) => m.role !== "system")
    .map((m) => ({
      role: m.role === "assistant" ? "assistant" : "user",
      content: m.content,
    }));

  const body: Record<string, unknown> = {
    model: p.model,
    max_tokens: p.maxOutputTokens,
    temperature: p.temperature,
    messages,
  };
  if (p.system) body.system = p.system;

  const res = await fetch(url, {
    method: "POST",
    headers: {
      "content-type": "application/json",
      "x-api-key": p.apiKey,
      "anthropic-version": ANTHROPIC_VERSION,
    },
    body: JSON.stringify(body),
  });

  if (!res.ok) {
    throw classify(res.status, await res.text());
  }

  const data = await res.json() as {
    content?: Array<{ type?: string; text?: string }>;
    usage?: { input_tokens?: number; output_tokens?: number };
  };
  const text = (data.content ?? [])
    .filter((c) => c.type === "text")
    .map((c) => c.text ?? "")
    .join("");
  return {
    text,
    model: p.model,
    inputTokens: data.usage?.input_tokens ?? 0,
    outputTokens: data.usage?.output_tokens ?? 0,
  };
};

function classify(status: number, body: string): AiProviderError {
  if (status === 429) {
    return new AiProviderError("anthropic_rate: " + body, "rate", status);
  }
  if (status === 529) {
    return new AiProviderError("anthropic_overloaded: " + body, "transient", status);
  }
  if (status === 401 || status === 403) {
    return new AiProviderError("anthropic_auth: " + body, "auth", status);
  }
  if (status >= 500) {
    return new AiProviderError("anthropic_transient: " + body, "transient", status);
  }
  return new AiProviderError("anthropic_bad_request: " + body, "bad_request", status);
}
