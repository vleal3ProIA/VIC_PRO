// ============================================================================
// Edge Function: diagnose-error · Diagnostico IA on-demand de un error report
// ----------------------------------------------------------------------------
// Pide al gateway de IA que analice un `error_reports` y devuelva un JSON
// estructurado con:
//
//   { why: string, what_user_did: string, how_to_fix: string }
//
// El resultado se CACHEA en `error_reports.ai_diagnosis` para que sucesivas
// aperturas del detalle no quemen tokens. Solo se llama a la IA en la PRIMERA
// peticion (o si el admin borra explicitamente la cache via `?force=true`).
//
// Autorizacion:
//   - JWT requerido.
//   - El caller debe ser admin (cualquier capability) o super_admin.
//   - El service_role lo aplicamos para leer/escribir la tabla saltando RLS,
//     pero el gate de auth es CONTRA el cliente con JWT (no contra admin).
//
// Body: { error_id: uuid, force?: bool }.
// Response: { ok: true, diagnosis: {...}, cached: bool } | { error: code }.
// ============================================================================

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { withSentry } from "../_shared/sentry.ts";
import { checkRateLimit } from "../_shared/rate_limit.ts";
import { AiGatewayError, AiQuotaExceededError, runCompletion } from "../_shared/ai/gateway.ts";
import { reportError } from "../_shared/error_reporter.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(body: unknown, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "content-type": "application/json" },
  });
}

interface ErrorReportRow {
  id: string;
  fn: string;
  error_code: string | null;
  error_message: string;
  error_details: unknown;
  context: unknown;
  severity: string;
  status: string;
  created_at: string;
  ai_diagnosis: { why?: string; what_user_did?: string; how_to_fix?: string } | null;
}

interface Diagnosis {
  why: string;
  what_user_did: string;
  how_to_fix: string;
}

/// Parser tolerante: intenta JSON estricto, luego fenced, luego primer balance.
function parseDiagnosis(text: string): Diagnosis | null {
  let t = text.trim();
  const fence = t.match(/```(?:json)?\s*([\s\S]*?)```/);
  if (fence) t = fence[1].trim();
  const start = t.indexOf("{");
  const end = t.lastIndexOf("}");
  if (start >= 0 && end > start) t = t.slice(start, end + 1);
  try {
    const obj = JSON.parse(t) as Record<string, unknown>;
    const why = typeof obj.why === "string" ? obj.why.trim() : "";
    const wud = typeof obj.what_user_did === "string"
      ? obj.what_user_did.trim()
      : "";
    const fix = typeof obj.how_to_fix === "string" ? obj.how_to_fix.trim() : "";
    if (!why || !wud || !fix) return null;
    return { why, what_user_did: wud, how_to_fix: fix };
  } catch {
    return null;
  }
}

Deno.serve(withSentry("diagnose-error", async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return json({ error: "method_not_allowed" }, 405);
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY")!;
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

  // ─── Auth ───
  const authHeader = req.headers.get("Authorization");
  if (!authHeader) return json({ error: "missing_authorization" }, 401);
  const userClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authHeader } },
  });
  const { data: { user }, error: userErr } = await userClient.auth.getUser();
  if (userErr || !user) return json({ error: "invalid_token" }, 401);

  const admin = createClient(supabaseUrl, serviceRoleKey);

  // Comprobamos rol via `is_admin()` RPC (incluye super; ver 0044).
  // Si el caller no es admin/super, devolvemos `forbidden`.
  const { data: isAdminData } = await userClient.rpc("is_admin");
  const isAdmin = isAdminData === true;
  if (!isAdmin) return json({ error: "forbidden" }, 403);

  const body = await req.json().catch(() => null) as
    | Record<string, unknown>
    | null;
  const errorId = body?.error_id;
  const force = body?.force === true;
  if (typeof errorId !== "string") {
    return json({ error: "missing_error_id" }, 400);
  }

  // Rate limit defensivo: el endpoint llama a la IA y queremos evitar
  // diagnosticar 100 errores seguidos sin querer.
  const rateOk = await checkRateLimit(admin, {
    bucketKey: `diagnose-error:${user.id}`,
    limit: 20,
    windowSeconds: 60,
  });
  if (!rateOk) return json({ error: "rate_limited" }, 429);

  // ─── Leer report ───
  const { data: rep, error: repErr } = await admin
    .from("error_reports")
    .select("id, fn, error_code, error_message, error_details, context, severity, status, created_at, ai_diagnosis")
    .eq("id", errorId)
    .maybeSingle();
  if (repErr) return json({ error: "db_error" }, 500);
  if (!rep) return json({ error: "not_found" }, 404);
  const report = rep as ErrorReportRow;

  // ─── Cache hit ───
  if (!force && report.ai_diagnosis) {
    const cached = report.ai_diagnosis;
    if (cached.why && cached.what_user_did && cached.how_to_fix) {
      return json(
        { ok: true, diagnosis: cached, cached: true },
        200,
      );
    }
  }

  const system =
    "You are an expert in Flutter Web + Supabase troubleshooting. " +
    "Given an error report from a production app, return STRICT JSON of " +
    "shape:\n" +
    '{"why":"...","what_user_did":"...","how_to_fix":"..."}\n' +
    "- `why`: short paragraph explaining why this error happened (root cause).\n" +
    "- `what_user_did`: short paragraph describing what the user was attempting " +
    "when it failed (infer from `fn` and `context`).\n" +
    "- `how_to_fix`: a numbered list (5-10 items max), one per line, with " +
    "concrete, technical steps the admin can take to investigate and fix " +
    "this issue. Be specific, mention the Supabase tables / Edge Functions / " +
    "Dart files involved if you can infer them. No fluff, no markdown fences.";

  const userMsg = JSON.stringify({
    fn: report.fn,
    error_code: report.error_code,
    error_message: report.error_message,
    error_details: report.error_details,
    context: report.context,
    severity: report.severity,
    created_at: report.created_at,
  });

  try {
    const result = await runCompletion(admin, {
      task: "diagnose-error",
      system,
      messages: [
        { role: "user", content: "Error report payload:\n" + userMsg },
      ],
      maxOutputTokens: 2048,
      temperature: 0.2,
      // Para diagnostico preferimos el modelo de pago si esta disponible
      // (mejor seguimiento de instrucciones JSON-estricto), pero no exigimos.
      preferTier: "paid",
      userId: user.id,
    });

    const diag = parseDiagnosis(result.text);
    if (!diag) {
      return json({ error: "parse_failed" }, 200);
    }

    // Cachear en la fila para que el siguiente click no cueste tokens.
    await admin
      .from("error_reports")
      .update({ ai_diagnosis: diag })
      .eq("id", report.id);

    return json({ ok: true, diagnosis: diag, cached: false }, 200);
  } catch (e) {
    // No mostramos al admin el detalle del error del gateway tampoco --
    // pero SI lo registramos en error_reports para que la propia herramienta
    // capture su propio fallo. Recursion controlada: no llamamos a
    // diagnose-error desde su propio catch :)
    const errorId2 = await reportError(admin, {
      userId: user.id,
      fn: "diagnose-error",
      error: e,
      errorCode: e instanceof AiGatewayError ? "ai_gateway" : "diagnose_failed",
      context: { error_id_under_diagnosis: errorId },
      severity: "medium",
    });
    if (e instanceof AiQuotaExceededError) {
      return json(
        {
          ok: false,
          error_code: "ai_quota_exceeded",
          daily_limit: e.dailyLimit,
          error_id: errorId2,
        },
        200,
      );
    }
    return json(
      { ok: false, error_code: "generic_error", error_id: errorId2 },
      200,
    );
  }
}));
