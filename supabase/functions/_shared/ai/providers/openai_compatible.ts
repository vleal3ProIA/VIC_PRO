// ============================================================================
// _shared/ai/providers/openai_compatible.ts · Adaptador formato OpenAI
// ----------------------------------------------------------------------------
// Sirve para todos los proveedores compatibles con la API de OpenAI:
// OpenAI, OpenRouter, DeepSeek y Groq. POST {base}/chat/completions con
// header Authorization: Bearer. El `base` lo resuelve el gateway (incluye
// /v1 cuando aplica). El system se manda como un mensaje role:"system".
// ============================================================================

import { AiProviderError } from "../types.ts";
import type { AdapterParams, AdapterResult } from "../types.ts";

export const openAiCompatibleAdapter = async (
  p: AdapterParams,
): Promise<AdapterResult> => {
  if (!p.baseUrl) {
    throw new AiProviderError("openai_compatible_missing_base_url", "bad_request");
  }
  const url = `${p.baseUrl.replace(/\/$/, "")}/chat/completions`;

  const messages: Array<{ role: string; content: string }> = [];
  if (p.system) messages.push({ role: "system", content: p.system });
  for (const m of p.messages) {
    if (m.role === "system") continue; // ya inyectado arriba
    messages.push({ role: m.role, content: m.content });
  }

  const res = await fetch(url, {
    method: "POST",
    headers: {
      "content-type": "application/json",
      "authorization": `Bearer ${p.apiKey}`,
    },
    body: JSON.stringify({
      model: p.model,
      max_tokens: p.maxOutputTokens,
      temperature: p.temperature,
      messages,
    }),
  });

  if (!res.ok) {
    throw classify(res.status, await res.text());
  }

  const data = await res.json() as {
    choices?: Array<{ message?: { content?: string } }>;
    usage?: { prompt_tokens?: number; completion_tokens?: number };
  };
  const text = data.choices?.[0]?.message?.content ?? "";
  return {
    text,
    model: p.model,
    inputTokens: data.usage?.prompt_tokens ?? 0,
    outputTokens: data.usage?.completion_tokens ?? 0,
  };
};

function classify(status: number, body: string): AiProviderError {
  if (status === 429) {
    return new AiProviderError("openai_rate_or_quota: " + body, "rate", status);
  }
  if (status === 401 || status === 403) {
    return new AiProviderError("openai_auth: " + body, "auth", status);
  }
  if (status === 402) {
    // Sin saldo (p. ej. OpenRouter / DeepSeek) -> tratar como cuota agotada.
    return new AiProviderError("openai_no_credit: " + body, "quota", status);
  }
  if (status >= 500) {
    return new AiProviderError("openai_transient: " + body, "transient", status);
  }
  return new AiProviderError("openai_bad_request: " + body, "bad_request", status);
}
