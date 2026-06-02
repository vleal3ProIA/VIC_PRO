// ============================================================================
// Edge Function: generate-exam · Banco de preguntas GLOBAL por contenido
// ----------------------------------------------------------------------------
// Genera preguntas tipo test POR SECCIÓN (para maximizar el número y repartir
// bien) y las guarda en un banco COMPARTIDO (`question_bank`) indexado por el
// HASH del texto de la sección. Así, secciones idénticas —aunque sean de otro
// temario u otro usuario— REUTILIZAN las mismas preguntas sin volver a gastar
// IA.
//
// Para cada sección con texto original:
//   1. calcula el hash de su texto y lo guarda en index_nodes.content_hash
//   2. si ya hay suficientes preguntas en el banco para ese hash y no se fuerza
//      -> se reutilizan (0 coste de IA)
//   3. si no, genera hasta ~N (según longitud) preguntas NUEVAS y las añade
//
// Respeta un presupuesto de tiempo: si se acerca al límite del Edge Function,
// para y devuelve el progreso (las secciones pendientes se completan al volver
// a pulsar "Generar", que salta las ya hechas).
// ============================================================================

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { checkRateLimit } from "../_shared/rate_limit.ts";
import { withSentry } from "../_shared/sentry.ts";
import { AiGatewayError, runCompletion } from "../_shared/ai/gateway.ts";
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

interface RawQ {
  question?: unknown;
  options?: unknown;
  correct_index?: unknown;
  explanation?: unknown;
}

interface ParsedQ {
  question: string;
  options: string[];
  correct_index: number;
  explanation: string | null;
}

function parseQuestions(text: string): ParsedQ[] {
  let t = text.trim();
  const fence = t.match(/```(?:json)?\s*([\s\S]*?)```/);
  if (fence) t = fence[1].trim();
  const start = t.indexOf("{");
  const end = t.lastIndexOf("}");
  if (start >= 0 && end > start) t = t.slice(start, end + 1);
  try {
    const obj = JSON.parse(t) as { questions?: unknown };
    const arr = Array.isArray(obj.questions) ? obj.questions as RawQ[] : [];
    const out: ParsedQ[] = [];
    for (const q of arr) {
      if (!q || typeof q.question !== "string") continue;
      const opts = Array.isArray(q.options)
        ? (q.options as unknown[])
          .filter((o): o is string =>
            typeof o === "string" && o.trim().length > 0
          )
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

function normText(s: string): string {
  return s.trim().toLowerCase().replace(/\s+/g, " ");
}

async function sha256Hex(s: string): Promise<string> {
  const buf = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(s),
  );
  return [...new Uint8Array(buf)]
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

interface NodeRow {
  id: string;
  title: string;
  content_hash: string | null;
}

Deno.serve(withSentry("generate-exam", async (req) => {
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
  const nodeIds = Array.isArray(body?.node_ids)
    ? (body!.node_ids as unknown[]).filter((x): x is string =>
      typeof x === "string"
    )
    : [];
  const force = body?.force === true;
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
    bucketKey: `generate-exam:${user.id}`,
    limit: 12,
    windowSeconds: 60,
  });
  if (!rateOk) return json({ error: "rate_limited" }, 429);

  // Secciones objetivo: las elegidas (node_ids) o todas las del temario.
  let nodes: NodeRow[] = [];
  {
    const { data } = await admin
      .from("index_nodes")
      .select("id, title, content_hash")
      .eq("subject_id", subjectId)
      .order("depth")
      .order("position")
      .limit(400);
    nodes = (data ?? []) as NodeRow[];
  }
  if (nodeIds.length > 0) {
    const set = new Set(nodeIds);
    nodes = nodes.filter((n) => set.has(n.id));
  }
  if (nodes.length === 0) return json({ error: "no_sections" }, 409);

  // Texto original de cada sección (solo las que tienen contenido propio).
  const ids = nodes.map((n) => n.id);
  const textByNode = new Map<string, string>();
  for (let i = 0; i < ids.length; i += 100) {
    const chunk = ids.slice(i, i + 100);
    const { data: contents } = await admin
      .from("node_content")
      .select("node_id, content")
      .eq("kind", "original")
      .in("node_id", chunk);
    for (
      const c of ((contents ?? []) as Array<
        { node_id: string; content: string | null }
      >)
    ) {
      if (c.content && c.content.trim().length >= 40) {
        textByNode.set(c.node_id, c.content);
      }
    }
  }
  const sections = nodes.filter((n) => textByNode.has(n.id));
  if (sections.length === 0) return json({ error: "no_ready_documents" }, 409);

  const lang = subject.language && subject.language.length > 0
    ? `Write in this language (ISO code): ${subject.language}.`
    : "Write in the SAME language as the section.";

  const startedAt = Date.now();
  const timeBudgetMs = 95_000;
  let generated = 0;
  let reused = 0;
  let pending = 0;
  let total = 0;
  let lastError: string | null = null;

  for (const sec of sections) {
    const text = textByNode.get(sec.id)!;
    // PRESERVAR content_hash existente del nodo (puede ser md5(title) seedeado
    // por una migracion canonica, p.ej. Constitucion). Solo si esta vacio
    // calculamos sha256(text) y lo persistimos. Asi el matching cliente <-> banco
    // (que usa index_nodes.content_hash IN question_bank.content_hash) se
    // mantiene estable y no destruimos hashes canonicos.
    let hash = (sec.content_hash ?? "").trim();
    if (hash.length === 0) {
      hash = await sha256Hex(normText(text).slice(0, 100_000));
      await admin
        .from("index_nodes")
        .update({ content_hash: hash })
        .eq("id", sec.id);
    }

    // ¿Ya hay preguntas para este contenido (de cualquiera)?
    const { data: ex } = await admin
      .from("question_bank")
      .select("question")
      .eq("content_hash", hash);
    const existing = ((ex ?? []) as Array<{ question: string }>)
      .map((r) => r.question);
    total += existing.length;

    // Cuántas queremos para esta sección, según su longitud (más texto => más
    // preguntas), acotado a [8, 25].
    const targetForSection = Math.min(
      25,
      Math.max(8, Math.round(text.length / 500)),
    );
    if (!force && existing.length >= targetForSection) {
      reused++;
      continue;
    }
    if (Date.now() - startedAt > timeBudgetMs) {
      pending++;
      continue;
    }
    const need = force
      ? targetForSection
      : (targetForSection - existing.length);

    const avoid = existing.length > 0
      ? "\n\nDo NOT repeat or rephrase any of these existing questions:\n" +
        existing.slice(-40).map((q) => `- ${q}`).join("\n")
      : "";
    // System prompt entrenado contra el banco de 4000 preguntas tipo test
    // de oposiciones (Constitucion Espanola). Reglas:
    //   - Tono formal-juridico.
    //   - DISTRACTORES PLAUSIBLES: cambiar UN detalle (num. articulo,
    //     plazo, mayoria, organo, fecha). NUNCA distractores absurdos.
    //   - Variedad de TIPOS: literal/parafrasis, dato cuantitativo,
    //     inferencia normativa, "señale la INCORRECTA", "respuestas a y
    //     b son correctas" (combinatoria).
    //   - Explanation cita el articulo/apartado concreto.
    const system =
      "You create EXAM-grade multiple-choice questions for Spanish " +
      "competitive exams (\"oposiciones\") from ONE section of study " +
      "material. Return ONLY minified JSON: " +
      '{"questions":[{"question":"...","options":["...","...","...","..."],' +
      '"correct_index":0,"explanation":"..."}]}.' +
      "\n\n" +
      "QUALITY (mandatory):\n" +
      "- Formal legal/administrative tone, NOT classroom-level. Use the " +
      "exact terminology of the source (\"Cortes Generales\", \"mayoria " +
      "absoluta\", \"ley organica\", \"refrendo\", \"Disposicion " +
      "transitoria\").\n" +
      "- Exactly 4 options. ONLY ONE correct. Options must be ALL " +
      "plausible to an average student.\n" +
      "- DISTRACTORS must each change ONE specific detail an unprepared " +
      "student would miss: wrong article number, wrong majority, wrong " +
      "deadline, wrong body/organ, wrong subject vs object, swapped " +
      "concepts. NEVER trivially absurd options.\n" +
      "- Vary QUESTION TYPES across the items: (a) literal/paraphrased " +
      "citation, (b) quantitative fact (dates, plazos, mayorias), (c) " +
      "negative formulation (\"señale la respuesta INCORRECTA\"), (d) " +
      "combinatorial (\"a y b son correctas\", \"todas las anteriores son " +
      "ciertas\"), (e) inference (\"de los preceptos anteriores se " +
      "deduce...\").\n" +
      "- `correct_index` is the 0-based index of the right option.\n" +
      "- `explanation` cites the EXACT article/apartado from the section " +
      "(e.g. \"Articulo 99.2 establece que...\", \"segun el Titulo III, " +
      "Capitulo II del texto\") and explains why the correct answer is " +
      "correct in 1-2 sentences.\n" +
      "- Grounded ONLY in the section text. Do NOT invent facts.\n" +
      "\n" +
      "COVERAGE:\n" +
      `- Produce up to ${need} distinct, NON-overlapping questions ` +
      "covering MULTIPLE aspects of this section (not just the obvious " +
      "facts); if the section is too short, return fewer.\n" +
      "\n" +
      `${lang}${avoid} No commentary, no preamble, JSON ONLY.`;

    try {
      const result = await runCompletion(admin, {
        task: "exam",
        system,
        messages: [{
          role: "user",
          content: `Section: ${sec.title}\n\n${text.slice(0, 60_000)}`,
        }],
        maxOutputTokens: 8192,
        temperature: 0.5,
        userId: subject.user_id,
        subjectId: subject.id,
      });
      const seen = new Set(existing.map(normText));
      const rows: Array<Record<string, unknown>> = [];
      for (const q of parseQuestions(result.text)) {
        const key = normText(q.question);
        if (key.length === 0 || seen.has(key)) continue;
        seen.add(key);
        rows.push({
          content_hash: hash,
          question: q.question,
          options: q.options,
          correct_index: q.correct_index,
          explanation: q.explanation,
          lang: subject.language,
        });
      }
      if (rows.length > 0) {
        await admin.from("question_bank").insert(rows);
        generated += rows.length;
        total += rows.length;
      }
    } catch (e) {
      lastError = e instanceof AiGatewayError
        ? e.message
        : (e as Error).message;
    }
  }

  if (total === 0) {
    const errorId = await reportError(admin, {
      userId: user.id,
      fn: "generate-exam",
      error: lastError ?? "empty_result",
      errorCode: "generation_failed",
      context: { subject_id: subject.id, node_ids: nodeIds, sections: sections.length },
      severity: "high",
    });
    return json(
      { ok: false, error_code: "generic_error", error_id: errorId },
      200,
    );
  }

  return json({
    ok: true,
    generated,
    reused,
    pending,
    total,
    sections: sections.length,
  }, 200);
}));
