// ============================================================================
// Edge Function: generate-views · Vista de un nodo del índice (Fase 2)
// ----------------------------------------------------------------------------
// Genera BAJO DEMANDA una de las 3 vistas de una sección del índice:
//   - 'original'  -> extrae verbatim el texto de esa sección del material.
//   - 'explained' -> explicación detallada y didáctica de esa sección.
//   - 'summary'   -> resumen con lo esencial de esa sección.
// En el idioma del temario. Cachea en `node_content` (unique node_id+kind): si
// ya existe y no se fuerza, lo devuelve sin gastar IA. Síncrono: la UI lo
// espera con spinner (una sección se genera en segundos).
// ============================================================================

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { checkRateLimit } from "../_shared/rate_limit.ts";
import { withSentry } from "../_shared/sentry.ts";
import { AiGatewayError, runCompletion } from "../_shared/ai/gateway.ts";
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

const KINDS = new Set(["original", "explained", "summary"]);

interface NodeRow {
  id: string;
  subject_id: string;
  user_id: string;
  title: string;
}

function systemFor(kind: string, language: string | null): string {
  const lang = language && language.length > 0
    ? `Write in this language (ISO code): ${language}.`
    : "Write in the SAME language as the material.";
  switch (kind) {
    case "original":
      return "You extract content from study material. Return, verbatim and " +
        "complete, only the text of the requested section (keep its headings " +
        "and structure). Do not summarize, do not add commentary.";
    case "explained":
      return "You are an expert tutor. Explain the requested section in a " +
        "clear, structured and didactic way, expanding difficult points with " +
        `examples where useful. ${lang} Use Markdown. No preamble.`;
    case "summary":
      return "You summarize study material. Produce a concise summary of the " +
        `key points of the requested section as bullet points. ${lang} ` +
        "Use Markdown. No preamble.";
    default:
      return "Summarize the requested section.";
  }
}

Deno.serve(withSentry("generate-views", async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return json({ error: "method_not_allowed" }, 405);
  }

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
  const nodeId = body?.node_id;
  const kind = body?.kind;
  const force = body?.force === true;
  if (typeof nodeId !== "string" || typeof kind !== "string" || !KINDS.has(kind)) {
    return json({ error: "bad_request" }, 400);
  }

  const { data: nodeData, error: nErr } = await admin
    .from("index_nodes")
    .select("id, subject_id, user_id, title")
    .eq("id", nodeId)
    .maybeSingle();
  if (nErr) return json({ error: "db_error", detail: nErr.message }, 500);
  if (!nodeData) return json({ error: "node_not_found" }, 404);
  const node = nodeData as NodeRow;
  if (node.user_id !== user.id) return json({ error: "forbidden" }, 403);

  // Caché: si ya existe y no se fuerza, devolvemos sin gastar IA.
  if (!force) {
    const { data: cached } = await admin
      .from("node_content")
      .select("content")
      .eq("node_id", node.id)
      .eq("kind", kind)
      .maybeSingle();
    if (cached && (cached as { content: string | null }).content) {
      return json({
        ok: true,
        cached: true,
        content: (cached as { content: string }).content,
      }, 200);
    }
  }

  const rateOk = await checkRateLimit(admin, {
    bucketKey: `generate-views:${user.id}`,
    limit: 30,
    windowSeconds: 60,
  });
  if (!rateOk) return json({ error: "rate_limited" }, 429);

  // Idioma del temario + material completo como contexto.
  const { data: subj } = await admin
    .from("subjects")
    .select("language")
    .eq("id", node.subject_id)
    .maybeSingle();
  const language = (subj as { language: string | null } | null)?.language ?? null;

  // Material completo (PDF/imagen como adjunto + texto de .txt).
  const { textContext, attachments } = await gatherMaterial(
    admin,
    node.subject_id,
  );
  if (!textContext && attachments.length === 0) {
    return json({ error: "no_ready_documents" }, 409);
  }

  try {
    const result = await runCompletion(admin, {
      task: `view:${kind}`,
      system: systemFor(kind, language),
      messages: [{
        role: "user",
        content: textContext
          ? `Section title: ${node.title}\n\nMaterial:\n\n${textContext}`
          : `Section title: ${node.title}\n\nUse the attached document(s).`,
      }],
      attachments: attachments.length > 0 ? attachments : undefined,
      maxOutputTokens: kind === "summary" ? 2048 : 8192,
      temperature: kind === "original" ? 0 : 0.3,
      userId: node.user_id,
      subjectId: node.subject_id,
    });

    await admin.from("node_content").upsert({
      node_id: node.id,
      user_id: node.user_id,
      kind,
      content: result.text,
    }, { onConflict: "node_id,kind" });

    return json({ ok: true, cached: false, content: result.text }, 200);
  } catch (e) {
    const detail = e instanceof AiGatewayError
      ? e.message
      : (e as Error).message;
    return json({ ok: false, error: "generation_failed", detail }, 200);
  }
}));
