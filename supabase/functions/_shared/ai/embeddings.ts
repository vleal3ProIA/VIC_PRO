// ============================================================================
// _shared/ai/embeddings.ts · Embeddings (vector 768) con fallback de proveedor
// ----------------------------------------------------------------------------
// Reutiliza las MISMAS credenciales de `ai_credentials` que el gateway de
// completions, pero con un modelo de EMBEDDING fijo por proveedor. La dimensión
// se fija en 768 para que encaje en `shared_sections.embedding vector(768)`:
//   * Gemini  text-embedding-004      -> 768 nativo.
//   * OpenAI  text-embedding-3-small  -> se pide `dimensions: 768`.
// Otros proveedores (mistral=1024, etc.) se omiten para no romper la dimensión.
//
// Estrategia: proveedores habilitados con modelo de embedding, por prioridad
// (free primero); por cada uno, sus credenciales fuera de cooldown rotando por
// last_used_at; al primer éxito se devuelve. Si todos fallan -> error.
// ============================================================================

import type { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2";

export const EMBED_DIM = 768;

/// Modelo de embedding por proveedor. Solo los que pueden dar 768 dims.
const EMBED_MODEL: Record<string, string> = {
  gemini: "text-embedding-004",
  openai: "text-embedding-3-small",
};

const DEFAULT_BASE: Record<string, string> = {
  gemini: "https://generativelanguage.googleapis.com",
  openai: "https://api.openai.com/v1",
};

const COOLDOWN_MS = 60 * 60 * 1000;

export class EmbeddingError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "EmbeddingError";
  }
}

interface ProviderRow {
  id: string;
  slug: string;
  enabled: boolean;
  priority: number;
  base_url: string | null;
}
interface CredentialRow {
  id: string;
  provider_id: string;
  api_key: string;
  cooldown_until: string | null;
}

/// Embebe una lista de textos y devuelve un vector (768) por cada uno, en el
/// mismo orden. Trocea en lotes para no exceder límites del proveedor.
export async function embedTexts(
  admin: SupabaseClient,
  texts: string[],
): Promise<number[][]> {
  if (texts.length === 0) return [];

  const { data: provData } = await admin
    .from("ai_providers")
    .select("id, slug, enabled, priority, base_url")
    .eq("enabled", true)
    .order("priority", { ascending: true });
  const providers = ((provData ?? []) as ProviderRow[])
    .filter((p) => EMBED_MODEL[p.slug] !== undefined);
  if (providers.length === 0) throw new EmbeddingError("no_embedding_provider");

  const nowIso = new Date().toISOString();
  const errors: string[] = [];

  for (const prov of providers) {
    const { data: credData } = await admin
      .from("ai_credentials")
      .select("id, provider_id, api_key, cooldown_until")
      .eq("provider_id", prov.id)
      .eq("enabled", true)
      .order("last_used_at", { ascending: true, nullsFirst: true });
    const creds = ((credData ?? []) as CredentialRow[])
      .filter((c) => !c.cooldown_until || c.cooldown_until < nowIso);
    const model = EMBED_MODEL[prov.slug];
    const baseUrl = prov.base_url ?? DEFAULT_BASE[prov.slug];

    for (const cred of creds) {
      try {
        const out = await runProvider(prov.slug, baseUrl, cred.api_key, model, texts);
        await admin.from("ai_credentials")
          .update({ last_used_at: nowIso })
          .eq("id", cred.id);
        return out;
      } catch (e) {
        const msg = (e as Error).message;
        errors.push(`${prov.slug}: ${msg}`);
        if (/\b(401|403|invalid)\b/i.test(msg)) {
          await admin.from("ai_credentials")
            .update({ enabled: false, disabled_reason: "invalid" })
            .eq("id", cred.id);
        } else if (/\b429\b|quota|rate/i.test(msg)) {
          await admin.from("ai_credentials")
            .update({
              cooldown_until: new Date(Date.now() + COOLDOWN_MS).toISOString(),
              disabled_reason: "quota_exhausted",
            })
            .eq("id", cred.id);
        }
      }
    }
  }
  throw new EmbeddingError("all_embedding_providers_failed: " + errors.join(" | "));
}

async function runProvider(
  slug: string,
  baseUrl: string,
  apiKey: string,
  model: string,
  texts: string[],
): Promise<number[][]> {
  const out: number[][] = [];
  const batchSize = 96;
  for (let i = 0; i < texts.length; i += batchSize) {
    const chunk = texts.slice(i, i + batchSize).map((t) => t.slice(0, 6000));
    const vecs = slug === "gemini"
      ? await embedGemini(baseUrl, apiKey, model, chunk)
      : await embedOpenAi(baseUrl, apiKey, model, chunk);
    for (const v of vecs) out.push(v);
  }
  return out;
}

async function embedGemini(
  base: string,
  apiKey: string,
  model: string,
  texts: string[],
): Promise<number[][]> {
  const url = `${base}/v1beta/models/${encodeURIComponent(model)}` +
    `:batchEmbedContents?key=${encodeURIComponent(apiKey)}`;
  const body = {
    requests: texts.map((t) => ({
      model: `models/${model}`,
      content: { parts: [{ text: t }] },
      outputDimensionality: EMBED_DIM,
    })),
  };
  const res = await fetch(url, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify(body),
  });
  if (!res.ok) throw new Error(`${res.status}: ${await res.text()}`);
  const data = await res.json() as {
    embeddings?: Array<{ values?: number[] }>;
  };
  const embs = data.embeddings ?? [];
  if (embs.length !== texts.length) {
    throw new Error("gemini_embedding_count_mismatch");
  }
  return embs.map((e) => normalizeDim(e.values ?? []));
}

async function embedOpenAi(
  base: string,
  apiKey: string,
  model: string,
  texts: string[],
): Promise<number[][]> {
  const res = await fetch(`${base}/embeddings`, {
    method: "POST",
    headers: {
      "content-type": "application/json",
      authorization: `Bearer ${apiKey}`,
    },
    body: JSON.stringify({ model, input: texts, dimensions: EMBED_DIM }),
  });
  if (!res.ok) throw new Error(`${res.status}: ${await res.text()}`);
  const data = await res.json() as {
    data?: Array<{ embedding?: number[]; index?: number }>;
  };
  const rows = (data.data ?? []).slice().sort(
    (a, b) => (a.index ?? 0) - (b.index ?? 0),
  );
  if (rows.length !== texts.length) {
    throw new Error("openai_embedding_count_mismatch");
  }
  return rows.map((r) => normalizeDim(r.embedding ?? []));
}

/// Asegura exactamente EMBED_DIM componentes (rellena/recorta por seguridad).
function normalizeDim(v: number[]): number[] {
  if (v.length === EMBED_DIM) return v;
  if (v.length > EMBED_DIM) return v.slice(0, EMBED_DIM);
  return [...v, ...new Array(EMBED_DIM - v.length).fill(0)];
}
