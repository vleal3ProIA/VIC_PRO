// ============================================================================
// _shared/ai/gateway.ts · Router multi-proveedor con fallback gratis -> pago
// ----------------------------------------------------------------------------
// `runCompletion(admin, req)` resuelve la mejor combinación proveedor+credencial
// y devuelve el texto generado, registrando uso/coste en `ai_usage`.
//
// Estrategia:
//   1. Carga proveedores HABILITADOS ordenados por prioridad (los free tienen
//      prioridad baja en el seed -> se intentan antes). `preferTier:'paid'`
//      reordena para lo difícil; `onlyProviderSlug` fuerza uno (test).
//   2. Por cada proveedor, sus credenciales habilitadas y fuera de cooldown,
//      rotando por `last_used_at` (la menos usada primero).
//   3. Llama al adaptador. Éxito -> marca last_used, registra uso, devuelve.
//      Fallo -> clasifica: auth -> deshabilita credencial; quota/rate ->
//      cooldown 1h; transient -> prueba la siguiente sin penalizar.
//   4. Si todo falla, lanza AiGatewayError con el detalle acumulado.
//
// Lee `ai_credentials` (tabla SOLO-servidor) con el cliente service_role que
// le pasa la Edge Function llamante.
// ============================================================================

import type { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2";
import { AiProviderError } from "./types.ts";
import type {
  AdapterParams,
  AdapterResult,
  AiCompletionRequest,
  AiCompletionResult,
  AiCredentialRow,
  AiProviderRow,
  ProviderAdapter,
} from "./types.ts";
import { geminiAdapter } from "./providers/gemini.ts";
import { anthropicAdapter } from "./providers/anthropic.ts";
import { openAiCompatibleAdapter } from "./providers/openai_compatible.ts";

export class AiGatewayError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "AiGatewayError";
  }
}

/// Subclase de AiGatewayError lanzada cuando el usuario supero su cuota diaria.
/// El mensaje sigue el formato `ai_quota_exceeded:<dailyLimit>` para que las
/// EFs llamantes lo propaguen al cliente sin envoltorios genericos. Detectarla
/// con `e instanceof AiQuotaExceededError` o `e.message.startsWith('ai_quota_exceeded:')`.
export class AiQuotaExceededError extends AiGatewayError {
  constructor(public readonly dailyLimit: number) {
    super(`ai_quota_exceeded:${dailyLimit}`);
    this.name = "AiQuotaExceededError";
  }
}

/// Adaptador por slug. Anyadir un proveedor nuevo = anyadir su adaptador aquí
/// + (si compatible OpenAI) reusar `openAiCompatibleAdapter`.
const ADAPTERS: Record<string, ProviderAdapter> = {
  gemini: geminiAdapter,
  anthropic: anthropicAdapter,
  openai: openAiCompatibleAdapter,
  openrouter: openAiCompatibleAdapter,
  deepseek: openAiCompatibleAdapter,
  groq: openAiCompatibleAdapter,
  mistral: openAiCompatibleAdapter,
};

/// Proveedores que aceptan adjuntos (PDF/imagen) por visión nativa. Cuando la
/// petición trae `attachments`, el gateway solo considera estos (p. ej. la
/// ingesta de temarios). Groq/OpenAI-compat quedan fuera para no ignorar el
/// documento silenciosamente.
const DOCUMENT_CAPABLE = new Set<string>(["gemini", "anthropic"]);

/// base_url por defecto cuando la fila `ai_providers.base_url` está vacía.
const DEFAULT_BASE_URL: Record<string, string> = {
  openai: "https://api.openai.com/v1",
  groq: "https://api.groq.com/openai/v1",
  openrouter: "https://openrouter.ai/api/v1",
  deepseek: "https://api.deepseek.com",
  mistral: "https://api.mistral.ai/v1",
};

/// Coste aproximado en USD por 1M tokens (input/output). Editable; 0 si se
/// desconoce o el tier es free. Solo para estimar gasto, no es facturación.
const PRICE_PER_MTOK: Record<string, { in: number; out: number }> = {
  "claude-3-5-sonnet-latest": { in: 3, out: 15 },
  "gpt-4o-mini": { in: 0.15, out: 0.6 },
  "deepseek-chat": { in: 0.27, out: 1.1 },
};

const COOLDOWN_MS = 60 * 60 * 1000; // 1 hora

export async function runCompletion(
  admin: SupabaseClient,
  req: AiCompletionRequest,
): Promise<AiCompletionResult> {
  // ─── Gate de cuota diaria por usuario ─────────────────────────────────
  // Lo hacemos PRIMERO para no leer providers/credenciales si el user ya
  // supero su cap. Si `req.userId` esta vacio (admin probando proveedor via
  // `onlyProviderSlug`, EF interna, etc.) se salta el chequeo. La RPC es
  // atomica y NO inserta en `ai_usage` (eso lo sigue haciendo el gateway
  // al exito de la llamada real, para no quemar cuota en proveedores caidos).
  if (req.userId) {
    const { data: quotaData, error: quotaErr } = await admin.rpc(
      "consume_ai_quota",
      { p_user_id: req.userId },
    );
    if (quotaErr) {
      throw new AiGatewayError("quota_check_failed: " + quotaErr.message);
    }
    const row = (quotaData as Array<
      { allowed: boolean; remaining: number; daily_limit: number }
    > | null)?.[0];
    if (!row?.allowed) {
      throw new AiQuotaExceededError(row?.daily_limit ?? 0);
    }
  }

  // En modo TEST (onlyProviderSlug) NO exigimos `enabled`: así se puede probar
  // la clave de un proveedor ANTES de activarlo. En uso normal, solo enabled.
  let provQuery = admin.from("ai_providers").select("*");
  provQuery = req.onlyProviderSlug
      ? provQuery.eq("slug", req.onlyProviderSlug)
      : provQuery.eq("enabled", true);
  const { data: provData, error: provErr } = await provQuery
    .order("priority", { ascending: true });
  if (provErr) {
    throw new AiGatewayError("providers_query_failed: " + provErr.message);
  }

  let providers = (provData ?? []) as AiProviderRow[];
  if (!req.onlyProviderSlug && req.preferTier === "paid") {
    providers = [...providers].sort((a, b) => {
      if (a.tier !== b.tier) return a.tier === "paid" ? -1 : 1;
      return a.priority - b.priority;
    });
  }
  // Con adjuntos (visión) solo proveedores capaces de leer documentos.
  if (req.attachments && req.attachments.length > 0) {
    providers = providers.filter((p) => DOCUMENT_CAPABLE.has(p.slug));
  }
  if (providers.length === 0) throw new AiGatewayError("no_enabled_providers");

  const errors: string[] = [];
  const nowIso = new Date().toISOString();

  for (const prov of providers) {
    const adapter = ADAPTERS[prov.slug];
    if (!adapter) {
      errors.push(`${prov.slug}: no_adapter`);
      continue;
    }

    const { data: credData } = await admin
      .from("ai_credentials")
      .select("*")
      .eq("provider_id", prov.id)
      .eq("enabled", true)
      .order("last_used_at", { ascending: true, nullsFirst: true });

    const creds = ((credData ?? []) as AiCredentialRow[])
      .filter((c) => !c.cooldown_until || c.cooldown_until < nowIso);
    if (creds.length === 0) {
      errors.push(`${prov.slug}: no_usable_credentials`);
      continue;
    }

    const model = req.model ?? prov.default_model;
    if (!model) {
      errors.push(`${prov.slug}: no_model_configured`);
      continue;
    }
    const baseUrl = prov.base_url ?? DEFAULT_BASE_URL[prov.slug] ?? null;

    for (const cred of creds) {
      const params: AdapterParams = {
        apiKey: cred.api_key,
        model,
        baseUrl,
        system: req.system,
        messages: req.messages,
        maxOutputTokens: req.maxOutputTokens ?? 2048,
        temperature: req.temperature ?? 0.3,
        attachments: req.attachments,
      };
      // Reintentos para errores TRANSITORIOS (5xx, timeout; p. ej. Gemini 503
      // "high demand / UNAVAILABLE"): hasta 2 reintentos con backoff sobre la
      // MISMA credencial antes de pasar a la siguiente. Absorbe picos temporales
      // de saturación del proveedor en vez de fallar el flujo entero.
      // Timeout duro por llamada: si el proveedor se cuelga (red caida,
      // streaming detenido, etc.) abortamos a los 25s y pasamos al siguiente
      // intento/credencial/proveedor. Sin esto, una IA muerta ocupa un slot
      // de Edge Function hasta el hard-kill del runtime (150s).
      const callTimeoutMs = 25_000;
      const maxTransientRetries = 2;
      for (let attempt = 0;; attempt++) {
        try {
          const controller = new AbortController();
          const timer = setTimeout(() => controller.abort(), callTimeoutMs);
          let r: AdapterResult;
          try {
            r = await adapter({ ...params, signal: controller.signal });
          } finally {
            clearTimeout(timer);
          }
          const cost = estimateCost(r.model, r.inputTokens, r.outputTokens, prov.tier);
          await admin.from("ai_credentials")
            .update({ last_used_at: nowIso, disabled_reason: null })
            .eq("id", cred.id);
          await admin.from("ai_usage").insert({
            user_id: req.userId ?? null,
            provider_id: prov.id,
            task_type: req.task,
            model: r.model,
            input_tokens: r.inputTokens,
            output_tokens: r.outputTokens,
            cost_usd: cost,
            subject_id: req.subjectId ?? null,
          });
          return {
            text: r.text,
            providerSlug: prov.slug,
            model: r.model,
            inputTokens: r.inputTokens,
            outputTokens: r.outputTokens,
            costUsd: cost,
          };
        } catch (e) {
          const kind = e instanceof AiProviderError ? e.kind : "transient";
          if (kind === "transient" && attempt < maxTransientRetries) {
            // backoff: 1.5s, 3s
            await new Promise((res) => setTimeout(res, 1500 * (attempt + 1)));
            continue;
          }
          errors.push(`${prov.slug}: ${(e as Error).message}`);
          if (kind === "auth") {
            await admin.from("ai_credentials")
              .update({ enabled: false, disabled_reason: "invalid" })
              .eq("id", cred.id);
          } else if (kind === "quota" || kind === "rate") {
            await admin.from("ai_credentials")
              .update({
                cooldown_until: new Date(Date.now() + COOLDOWN_MS).toISOString(),
                disabled_reason: "quota_exhausted",
              })
              .eq("id", cred.id);
          }
          // 'bad_request' / 'transient' agotado -> siguiente credencial/proveedor.
          break;
        }
      }
    }
  }

  throw new AiGatewayError("all_providers_failed: " + errors.join(" | "));
}

function estimateCost(
  model: string,
  inTok: number,
  outTok: number,
  tier: string,
): number {
  if (tier === "free") return 0;
  const price = PRICE_PER_MTOK[model];
  if (!price) return 0;
  return (inTok / 1e6) * price.in + (outTok / 1e6) * price.out;
}
