// ============================================================================
// Edge Function: ask-subject · Chat de preguntas sobre el temario (Fase 3)
// ----------------------------------------------------------------------------
// Responde una pregunta del usuario FUNDAMENTÁNDOSE en el material del temario
// (o de la sección seleccionada). Usa el texto ya disponible (el 'original' del
// nodo, o el texto completo del temario; visión del PDF solo como último
// recurso) para que cualquier proveedor del gateway pueda responder.
//
// El historial reciente se incluye como contexto en el mensaje (sin depender de
// roles 'assistant', así funciona con todos los adaptadores). Síncrono.
// ============================================================================

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { checkRateLimit } from "../_shared/rate_limit.ts";
import { withSentry } from "../_shared/sentry.ts";
import { AiGatewayError, runCompletion } from "../_shared/ai/gateway.ts";
import { gatherMaterial } from "../_shared/ai/material.ts";
import type { AiAttachment } from "../_shared/ai/types.ts";

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

interface NodeRow {
  id: string;
  subject_id: string;
  user_id: string;
}

/// Normaliza el historial: pares {role,content} válidos, últimos 8 turnos.
function parseHistory(raw: unknown): Array<{ role: string; content: string }> {
  if (!Array.isArray(raw)) return [];
  const out: Array<{ role: string; content: string }> = [];
  for (const item of raw) {
    if (
      item && typeof (item as { content?: unknown }).content === "string"
    ) {
      const role = (item as { role?: unknown }).role === "assistant"
        ? "assistant"
        : "user";
      const content = ((item as { content: string }).content).slice(0, 2000);
      if (content.trim().length > 0) out.push({ role, content });
    }
  }
  return out.slice(-8);
}

Deno.serve(withSentry("ask-subject", async (req) => {
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
  const nodeId = typeof body?.node_id === "string" ? body.node_id : null;
  const question = typeof body?.question === "string"
    ? body.question.trim().slice(0, 2000)
    : "";
  const history = parseHistory(body?.history);
  if (typeof subjectId !== "string") {
    return json({ error: "missing_subject_id" }, 400);
  }
  if (question.length === 0) return json({ error: "missing_question" }, 400);

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
    bucketKey: `ask-subject:${user.id}`,
    limit: 30,
    windowSeconds: 60,
  });
  if (!rateOk) return json({ error: "rate_limited" }, 429);

  // Material: texto de la sección -> texto del temario -> visión.
  let textContext = "";
  let attachments: AiAttachment[] = [];
  if (nodeId) {
    const { data: nodeRow } = await admin
      .from("index_nodes")
      .select("id, subject_id, user_id")
      .eq("id", nodeId)
      .maybeSingle();
    const node = nodeRow as NodeRow | null;
    if (node && node.user_id === user.id) {
      const { data: orig } = await admin
        .from("node_content")
        .select("content")
        .eq("node_id", node.id)
        .eq("kind", "original")
        .maybeSingle();
      textContext =
        ((orig as { content: string | null } | null)?.content ?? "").trim();
    }
  }
  if (textContext.length < 20) {
    const mat = await gatherMaterial(admin, subjectId);
    if (mat.textContext.trim().length > 0) {
      textContext = mat.textContext;
    } else {
      textContext = "";
      attachments = mat.attachments;
    }
  }
  if (textContext.length === 0 && attachments.length === 0) {
    return json({ error: "no_ready_documents" }, 409);
  }

  const lang = subject.language && subject.language.length > 0
    ? `Answer in this language (ISO code): ${subject.language}.`
    : "Answer in the SAME language as the material/question.";
  const system = "You are a study assistant for the user's own study material. " +
    "Answer the question using ONLY the material provided; if the answer is not " +
    "in the material, say clearly that you can't find it there (do not invent). " +
    `Be clear and concise, use Markdown when helpful. ${lang}` +
    (textContext ? "\n\nMATERIAL:\n\n" + textContext : "");

  // Historial reciente como contexto + la pregunta actual (un solo turno de
  // usuario, para no depender del rol 'assistant' en los adaptadores).
  const convo = history
    .map((h) => `${h.role === "assistant" ? "Assistant" : "User"}: ${h.content}`)
    .join("\n");
  const userContent = (convo ? `Previous conversation:\n${convo}\n\n` : "") +
    `Question: ${question}` +
    (textContext ? "" : "\n\n(Use the attached document(s).)");

  try {
    const result = await runCompletion(admin, {
      task: "chat",
      system,
      messages: [{ role: "user", content: userContent }],
      attachments: attachments.length > 0 ? attachments : undefined,
      maxOutputTokens: 1024,
      temperature: 0.3,
      userId: subject.user_id,
      subjectId: subject.id,
    });
    return json({ ok: true, answer: result.text }, 200);
  } catch (e) {
    const detail = e instanceof AiGatewayError
      ? e.message
      : (e as Error).message;
    return json({ ok: false, error: "generation_failed", detail }, 200);
  }
}));
