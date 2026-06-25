// ============================================================================
// Edge Function: generate-quiz · Cuestionario tipo test (Fase 3)
// ----------------------------------------------------------------------------
// Genera N preguntas de opción múltiple de UNA SECCIÓN del índice. Regla del
// producto: el cuestionario SIEMPRE se crea por sección activa, nunca de todo
// el temario a la vez (el usuario estudia paso a paso). Para "ver todo" la UI
// agrega lo que ya se generó por secciones.
//
// Reemplaza el lote anterior del mismo ámbito. Síncrono: la UI espera con
// spinner.
// ============================================================================

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { checkRateLimit } from "../_shared/rate_limit.ts";
import { withSentry } from "../_shared/sentry.ts";
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
  // Solo se permite generar por sección activa (no todo el temario a la vez).
  if (!nodeId) return json({ error: "missing_node_id" }, 400);

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

  // Material: SOLO el texto propio de la sección. Sin fallback al temario
  // completo (el cuestionario es siempre por sección).
  const { data: nodeRow } = await admin
    .from("index_nodes")
    .select("id, subject_id, user_id")
    .eq("id", nodeId)
    .maybeSingle();
  const node = nodeRow as NodeRow | null;
  if (!node || node.subject_id !== subject.id || node.user_id !== user.id) {
    return json({ error: "node_not_found" }, 404);
  }
  const { data: orig } = await admin
    .from("node_content")
    .select("content")
    .eq("node_id", node.id)
    .eq("kind", "original")
    .maybeSingle();
  const textContext =
    ((orig as { content: string | null } | null)?.content ?? "").trim();
  if (textContext.length < 120) {
    return json({
      ok: false,
      error: "section_empty",
      detail:
        "La sección activa no tiene texto suficiente para generar preguntas.",
    }, 200);
  }

  const lang = subject.language && subject.language.length > 0
    ? `Write the quiz in this language (ISO code): ${subject.language}.`
    : "Write the quiz in the SAME language as the material.";
  // Mismo estilo de oposiciones que generate-exam.
  const system =
    "You create EXAM-grade multiple-choice questions for Spanish " +
    "competitive exams (\"oposiciones\") from the provided material. Return " +
    'ONLY minified JSON: {"questions":[{"question":"...","options":["...",' +
    '"...","...","..."],"correct_index":0,"explanation":"..."}]}.\n\n' +
    "QUALITY:\n" +
    "- Formal legal/administrative tone. Use the source's exact terminology.\n" +
    "- 4 options, ONLY ONE correct, all plausible. Distractors change ONE " +
    "specific detail (article, majority, deadline, body, subject) -- NEVER " +
    "trivially absurd.\n" +
    "- Vary types: literal/paraphrase, quantitative, negative " +
    "(\"INCORRECTA\"), combinatorial (\"a y b son correctas\"), inference.\n" +
    "- `explanation` cites the article/apartado in 1-2 sentences.\n" +
    "- Grounded ONLY in the material. Do NOT invent.\n\n" +
    `- Produce about ${count} questions covering different aspects. ` +
    `${lang} No commentary.`;

  try {
    const result = await runCompletion(admin, {
      task: "quiz",
      system,
      messages: [{
        role: "user",
        content: "Material:\n\n" + textContext,
      }],
      maxOutputTokens: 4096,
      temperature: 0.3,
      userId: subject.user_id,
      subjectId: subject.id,
    });

    const questions = parseQuestions(result.text);
    if (questions.length === 0) {
      return json({ ok: false, error: "empty_result" }, 200);
    }

    await admin
      .from("quiz_questions")
      .delete()
      .eq("subject_id", subject.id)
      .eq("node_id", nodeId);

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
    const errorId = await reportError(admin, {
      userId: user.id,
      fn: "generate-quiz",
      error: e,
      errorCode: e instanceof AiGatewayError ? "ai_gateway" : "generation_failed",
      context: { subject_id: subject.id, node_id: nodeId, count },
      severity: "high",
    });
    if (e instanceof AiQuotaExceededError) {
      return json(
        {
          ok: false,
          error_code: "ai_quota_exceeded",
          daily_limit: e.dailyLimit,
          error_id: errorId,
        },
        200,
      );
    }
    return json(
      { ok: false, error_code: "generic_error", error_id: errorId },
      200,
    );
  }
}));
