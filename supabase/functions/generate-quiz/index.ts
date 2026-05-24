// ============================================================================
// Edge Function: generate-quiz · Cuestionario tipo test (Fase 3)
// ----------------------------------------------------------------------------
// Genera N preguntas de opción múltiple de un temario o sección del índice.
// Usa el TEXTO ya disponible (el 'original' del nodo, o el texto completo del
// temario; visión del PDF solo como último recurso) para que cualquier
// proveedor del gateway pueda generarlas. Reemplaza el lote anterior del mismo
// ámbito. Síncrono: la UI espera con spinner.
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

interface RawQuestion {
  question?: unknown;
  options?: unknown;
  correct_index?: unknown;
  explanation?: unknown;
}

interface QuizQuestion {
  question: string;
  options: string[];
  correct_index: number;
  explanation: string | null;
}

/// Extrae {questions:[{question,options,correct_index,explanation}]} tolerando
/// fences y texto alrededor. Descarta preguntas mal formadas.
function parseQuestions(text: string): QuizQuestion[] {
  let t = text.trim();
  const fence = t.match(/```(?:json)?\s*([\s\S]*?)```/);
  if (fence) t = fence[1].trim();
  const start = t.indexOf("{");
  const end = t.lastIndexOf("}");
  if (start >= 0 && end > start) t = t.slice(start, end + 1);
  try {
    const obj = JSON.parse(t) as { questions?: unknown };
    const arr = Array.isArray(obj.questions) ? obj.questions as RawQuestion[] : [];
    const out: QuizQuestion[] = [];
    for (const q of arr) {
      if (!q || typeof q.question !== "string") continue;
      const opts = Array.isArray(q.options)
        ? (q.options as unknown[])
          .filter((o): o is string => typeof o === "string" && o.trim().length > 0)
          .map((o) => o.slice(0, 300).trim())
        : [];
      if (opts.length < 2 || opts.length > 6) continue;
      const ci = typeof q.correct_index === "number"
        ? Math.trunc(q.correct_index)
        : 0;
      if (ci < 0 || ci >= opts.length) continue;
      out.push({
        question: (q.question as string).slice(0, 500).trim(),
        options: opts,
        correct_index: ci,
        explanation: typeof q.explanation === "string"
          ? (q.explanation as string).slice(0, 800).trim()
          : null,
      });
    }
    return out;
  } catch {
    return [];
  }
}

interface NodeRow {
  id: string;
  subject_id: string;
  user_id: string;
}

Deno.serve(withSentry("generate-quiz", async (req) => {
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
  const count = Math.max(
    3,
    Math.min(20, typeof body?.count === "number" ? body.count : 8),
  );
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
    bucketKey: `generate-quiz:${user.id}`,
    limit: 20,
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
    ? `Write the quiz in this language (ISO code): ${subject.language}.`
    : "Write the quiz in the SAME language as the material.";
  const system =
    "You create a multiple-choice quiz from the provided material. Return ONLY " +
    'minified JSON: {"questions":[{"question":"...","options":["...","...",' +
    '"...","..."],"correct_index":0,"explanation":"..."}]}. Each question has ' +
    "exactly 4 plausible options with ONLY ONE correct, grounded ONLY in the " +
    "material (do not invent). `correct_index` is the 0-based index of the " +
    "right option. `explanation` briefly says why it is correct. Produce about " +
    `${count} questions. ${lang} No commentary.`;

  try {
    const result = await runCompletion(admin, {
      task: "quiz",
      system,
      messages: [{
        role: "user",
        content: textContext
          ? "Material:\n\n" + textContext
          : "Use the attached document(s).",
      }],
      attachments: attachments.length > 0 ? attachments : undefined,
      maxOutputTokens: 4096,
      temperature: 0.3,
      userId: subject.user_id,
      subjectId: subject.id,
    });

    const questions = parseQuestions(result.text);
    if (questions.length === 0) {
      return json({ ok: false, error: "empty_result" }, 200);
    }

    let del = admin.from("quiz_questions").delete().eq("subject_id", subject.id);
    del = nodeId ? del.eq("node_id", nodeId) : del.is("node_id", null);
    await del;

    const rows = questions.map((q) => ({
      subject_id: subject.id,
      user_id: subject.user_id,
      node_id: nodeId,
      question: q.question,
      options: q.options,
      correct_index: q.correct_index,
      explanation: q.explanation,
    }));
    await admin.from("quiz_questions").insert(rows);

    return json({ ok: true, count: rows.length }, 200);
  } catch (e) {
    const detail = e instanceof AiGatewayError
      ? e.message
      : (e as Error).message;
    return json({ ok: false, error: "generation_failed", detail }, 200);
  }
}));
