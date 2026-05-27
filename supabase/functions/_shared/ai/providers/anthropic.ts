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

/// Tope de tokens de salida por modelo Claude: la API RECHAZA (400) un
/// `max_tokens` mayor que el límite del modelo. Los 3.5/3.7/haiku admiten 8192;
/// los Claude 4.x (sonnet/opus) admiten salidas mucho mayores. Por defecto,
/// valor seguro 8192. Así un caller puede pedir 32k+ sin romper la llamada.
function modelMaxTokens(model: string): number {
  const m = model.toLowerCase();
  if (m.includes("sonnet-4") || m.includes("opus-4") || m.includes("claude-4")) {
    return 64000;
  }
  return 8192;
}

export const anthropicAdapter = async (
  p: AdapterParams,
): Promise<AdapterResult> => {
  const base = p.baseUrl ?? DEFAULT_BASE;
  const url = `${base}/v1/messages`;

  type Block = Record<string, unknown>;
  const messages: Array<{ role: string; content: string | Block[] }> = p.messages
    .filter((m) => m.role !== "system")
    .map((m) => ({
      role: m.role === "assistant" ? "assistant" : "user",
      content: m.content as string | Block[],
    }));

  // Adjuntos -> bloques document/image en el último mensaje de usuario.
  if (p.attachments && p.attachments.length > 0) {
    let idx = -1;
    for (let i = messages.length - 1; i >= 0; i--) {
      if (messages[i].role === "user") {
        idx = i;
        break;
      }
    }
    if (idx === -1) {
      messages.push({ role: "user", content: [] as Block[] });
      idx = messages.length - 1;
    }
    const blocks: Block[] = [];
    const existing = messages[idx].content;
    if (typeof existing === "string" && existing.length > 0) {
      blocks.push({ type: "text", text: existing });
    }
    for (const a of p.attachments) {
      blocks.push({
        type: a.mimeType === "application/pdf" ? "document" : "image",
        source: { type: "base64", media_type: a.mimeType, data: a.dataBase64 },
      });
    }
    messages[idx].content = blocks;
  }

  const body: Record<string, unknown> = {
    model: p.model,
    // Acotamos al máximo del modelo para que la API no rechace la llamada.
    max_tokens: Math.max(
      1,
      Math.min(p.maxOutputTokens, modelMaxTokens(p.model)),
    ),
    temperature: p.temperature,
    messages,
  };
  if (p.system) body.system = p.system;

  const headers: Record<string, string> = {
    "content-type": "application/json",
    "x-api-key": p.apiKey,
    "anthropic-version": ANTHROPIC_VERSION,
  };
  // Soporte de PDF via la API de Messages (beta header; inocuo si ya es GA).
  if ((p.attachments ?? []).some((a) => a.mimeType === "application/pdf")) {
    headers["anthropic-beta"] = "pdfs-2024-09-25";
  }

  const res = await fetch(url, {
    method: "POST",
    headers,
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
