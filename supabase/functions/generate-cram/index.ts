// ============================================================================
// Edge Function: generate-cram · Chuleta "modo pánico" (Fase 3)
// ----------------------------------------------------------------------------
// Genera una chuleta ULTRA-condensada del temario: solo lo más probable de
// caer y lo imprescindible para aprobar (el 20% que da el 80%). Markdown,
// cacheada (1 por temario). Síncrono.
// ============================================================================

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { checkRateLimit } from "../_shared/rate_limit.ts";
import { withSentry } from "../_shared/sentry.ts";
import { AiGatewayError, AiQuotaExceededError, runCompletion } from "../_shared/ai/gateway.ts";
import { gatherMaterial } from "../_shared/ai/material.ts";

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

Deno.serve(withSentry("generate-cram", async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY")!;
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

  const authHeader = req.headers.get("Authorization");
  if (!authHeader) return json({ error: "missing_authorization" }, 401);
  const userClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authHeader } },
  });
  const { data: { user }, error: userErr } = await userClient.auth.getUser();
  if (userErr || !user) return json({ error: "invalid_token" }, 401);

  const admin = createClient(supabaseUrl, serviceRoleKey);

  const body = await req.json().catch(() => null) as
    | Record<string, unknown>
    | null;
  const subjectId = body?.subject_id;
  if (typeof subjectId !== "string") {
    return json({ error: "missing_subject_id" }, 400);
  }

  const { data: subj } = await admin
    .from("subjects")
    .select("id, user_id, language")
    .eq("id", subjectId)
    .maybeSingle();
  if (!subj) return json({ error: "subject_not_found" }, 404);
  const subject = subj as {
    id: string;
    user_id: string;
    language: string | null;
  };
  if (subject.user_id !== user.id) return json({ error: "forbidden" }, 403);

  const rateOk = await checkRateLimit(admin, {
    bucketKey: `generate-cram:${user.id}`,
    limit: 10,
    windowSeconds: 60,
  });
  if (!rateOk) return json({ error: "rate_limited" }, 429);

  const mat = await gatherMaterial(admin, subjectId);
  if (!mat.textContext && mat.attachments.length === 0) {
    return json({ error: "no_ready_documents" }, 409);
  }

  const lang = subject.language && subject.language.length > 0
    ? `Write in this language (ISO code): ${subject.language}.`
    : "Write in the SAME language as the material.";
  const system =
    "You create a last-minute CRAM SHEET (panic mode) from the user's study " +
    "material. Include ONLY the highest-yield, most likely-to-be-asked points: " +
    "key definitions, numbers, dates, articles, lists and rules that MUST be " +
    "remembered to pass. Be extremely concise — short bullets, the 20% that " +
    "gives 80%. Group with short headings. Ground it ONLY in the material (do " +
    `not invent). Use Markdown and **bold** for the critical terms. ${lang} ` +
    "No preamble.";

  try {
    const result = await runCompletion(admin, {
      task: "cram",
      system,
      messages: [{
        role: "user",
        content: mat.textContext
          ? "Material:\n\n" + mat.textContext
          : "Use the attached document(s).",
      }],
      attachments: mat.attachments.length > 0 ? mat.attachments : undefined,
      maxOutputTokens: 4096,
      temperature: 0.3,
      userId: subject.user_id,
      subjectId: subject.id,
    });

    const content = result.text.trim();
    if (content.length === 0) {
      return json({ ok: false, error: "empty_result" }, 200);
    }

    await admin.from("cram_sheets").upsert({
      subject_id: subject.id,
      user_id: subject.user_id,
      content,
    }, { onConflict: "subject_id" });

    return json({ ok: true, content }, 200);
  } catch (e) {
    if (e instanceof AiQuotaExceededError) {
      return json({
        ok: false,
        error: "ai_quota_exceeded",
        daily_limit: e.dailyLimit,
      }, 200);
    }
    const detail = e instanceof AiGatewayError
      ? e.message
      : (e as Error).message;
    return json({ ok: false, error: "generation_failed", detail }, 200);
  }
}));
