// ============================================================================
// _shared/ai/providers/gemini.ts · Adaptador Google Gemini (Generative Lang API)
// ----------------------------------------------------------------------------
// POST {base}/v1beta/models/{model}:generateContent?key={apiKey}
// Roles de Gemini: "user" / "model" (no "assistant"/"system"); el system va
// aparte en `system_instruction`.
// ============================================================================

import { AiProviderError } from "../types.ts";
import type { AdapterParams, AdapterResult } from "../types.ts";

const DEFAULT_BASE = "https://generativelanguage.googleapis.com";

export const geminiAdapter = async (
  p: AdapterParams,
): Promise<AdapterResult> => {
  const base = p.baseUrl ?? DEFAULT_BASE;
  const url = `${base}/v1beta/models/${encodeURIComponent(p.model)}` +
    `:generateContent?key=${encodeURIComponent(p.apiKey)}`;

  const contents = p.messages
    .filter((m) => m.role !== "system")
    .map((m) => ({
      role: m.role === "assistant" ? "model" : "user",
      parts: [{ text: m.content }] as Array<Record<string, unknown>>,
    }));

  // Adjuntos (PDF/imagen) -> inline_data en el último contenido de usuario.
  if (p.attachments && p.attachments.length > 0) {
    let target = contents.slice().reverse().find((c) => c.role === "user");
    if (!target) {
      target = {
        role: "user",
        parts: [] as Array<Record<string, unknown>>,
      };
      contents.push(target);
    }
    for (const a of p.attachments) {
      target.parts.push({
        inline_data: { mime_type: a.mimeType, data: a.dataBase64 },
      });
    }
  }

  const body: Record<string, unknown> = {
    contents,
    generationConfig: {
      maxOutputTokens: p.maxOutputTokens,
      temperature: p.temperature,
    },
  };
  if (p.system) {
    body.system_instruction = { parts: [{ text: p.system }] };
  }

  const res = await fetch(url, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify(body),
  });

  if (!res.ok) {
    throw classify(res.status, await res.text());
  }

  const data = await res.json() as {
    candidates?: Array<{ content?: { parts?: Array<{ text?: string }> } }>;
    usageMetadata?: { promptTokenCount?: number; candidatesTokenCount?: number };
  };
  const text = (data.candidates?.[0]?.content?.parts ?? [])
    .map((x) => x.text ?? "")
    .join("");
  const um = data.usageMetadata ?? {};
  return {
    text,
    model: p.model,
    inputTokens: um.promptTokenCount ?? 0,
    outputTokens: um.candidatesTokenCount ?? 0,
  };
};

function classify(status: number, body: string): AiProviderError {
  if (status === 429) {
    return new AiProviderError("gemini_rate_or_quota: " + body, "rate", status);
  }
  if (status === 401 || status === 403) {
    return new AiProviderError("gemini_auth: " + body, "auth", status);
  }
  if (status === 400 && /API_KEY_INVALID|invalid.*key/i.test(body)) {
    return new AiProviderError("gemini_auth: " + body, "auth", status);
  }
  if (status >= 500) {
    return new AiProviderError("gemini_transient: " + body, "transient", status);
  }
  return new AiProviderError("gemini_bad_request: " + body, "bad_request", status);
}
