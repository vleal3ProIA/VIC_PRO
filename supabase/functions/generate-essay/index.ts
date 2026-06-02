// ============================================================================
// Edge Function: generate-essay · Banco GLOBAL de preguntas a desarrollar
// ----------------------------------------------------------------------------
// Hermana de `generate-exam` pero genera preguntas open-ended ("desarrollo")
// con su RESPUESTA MODELO, en vez de opciones tipo test. Misma arquitectura:
// por SECCIÓN, con reutilización por hash del texto (`content_hash` en
// `index_nodes`), guardadas en el banco COMPARTIDO `essay_bank`.
//
// Las respuestas modelo pueden ser largas (hasta ~4 KB), por eso bajamos el
// objetivo por sección a [5..15] (menos cantidad, más profundidad) y mantenemos
// `maxOutputTokens` alto (8192).
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

interface RawEssay {
  question?: unknown;
  answer?: unknown;
}

interface ParsedEssay {
  question: string;
  answer: string;
}

function parseItems(text: string): ParsedEssay[] {
  let t = text.trim();
  const fence = t.match(/```(?:json)?\s*([\s\S]*?)```/);
  if (fence) t = fence[1].trim();
  const start = t.indexOf("{");
  const end = t.lastIndexOf("}");
  if (start >= 0 && end > start) t = t.slice(start, end + 1);
  try {
    const obj = JSON.parse(t) as { items?: unknown };
    const arr = Array.isArray(obj.items) ? obj.items as RawEssay[] : [];
    const out: ParsedEssay[] = [];
    for (const q of arr) {
      if (!q || typeof q.question !== "string") continue;
      if (typeof q.answer !== "string") continue;
      const question = (q.question as string).slice(0, 500).trim();
      const answer = (q.answer as string).slice(0, 4000).trim();
      if (question.length === 0 || answer.length === 0) continue;
      out.push({ question, answer });
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

Deno.serve(withSentry("generate-essay", async (req) => {
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
    bucketKey: `essay:${user.id}`,
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
    // PRESERVAR content_hash existente del nodo. Solo asignar uno nuevo
    // (sha256 del texto) si el nodo nunca tuvo. Asi no destruimos hashes
    // canonicos seedeados por migraciones (p.ej. md5(title) en Constitucion)
    // y mantenemos el matching estable con essay_bank.
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
      .from("essay_bank")
      .select("question")
      .eq("content_hash", hash);
    const existing = ((ex ?? []) as Array<{ question: string }>)
      .map((r) => r.question);
    total += existing.length;

    // Cuántas queremos para esta sección, según su longitud (más texto => más
    // preguntas), acotado a [5, 15]. Las preguntas a desarrollar piden
    // respuestas largas, así que menos cantidad y más profundidad.
    const targetForSection = Math.min(
      15,
      Math.max(5, Math.round(text.length / 1500)),
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
    // System prompt entrenado para preguntas ESTILO OPOSICIONES de
    // desarrollo. Reglas:
    //   - Verbos de orden formal: Analice, Exponga, Desarrolle, Compare,
    //     Razone, Justifique, Aplique. NO usar "habla sobre" o "que es".
    //   - Cubrir niveles cognitivos VARIADOS: comprension, analisis,
    //     aplicacion, evaluacion (taxonomia de Bloom).
    //   - Respuesta modelo con ESTRUCTURA: planteamiento + cuerpo (puntos
    //     clave numerados) + conclusion + cita exacta del articulo.
    //   - Citar articulos/apartados/numeros concretos.
    const system =
      "You create EXAM-grade open-ended (\"essay\" / \"desarrollo\") " +
      "questions for Spanish competitive exams (\"oposiciones\") from ONE " +
      "section of study material, EACH WITH ITS MODEL ANSWER. Return ONLY " +
      'minified JSON: {"items":[{"question":"...","answer":"..."}]}.' +
      "\n\n" +
      "QUESTION FORMULATION (mandatory):\n" +
      "- Start with formal academic verbs: \"Analice\", \"Exponga\", " +
      "\"Desarrolle\", \"Compare\", \"Razone\", \"Justifique\", " +
      "\"Aplique\", \"Distinga entre\", \"Identifique los requisitos\". " +
      "Do NOT use informal phrasings like \"habla sobre\" or \"que es\".\n" +
      "- Vary COGNITIVE LEVELS across the items (Bloom): comprehension " +
      "(\"Exponga el contenido del articulo X\"), analysis (\"Analice las " +
      "diferencias entre Y y Z\"), application (\"Aplique el procedimiento " +
      "del articulo X al caso siguiente\"), evaluation (\"Razone la " +
      "constitucionalidad de...\").\n" +
      "- Cite the article/apartado the question targets when relevant " +
      "(\"...del articulo 99\", \"...regulado en el Titulo III\").\n" +
      "\n" +
      "MODEL ANSWER STRUCTURE (mandatory):\n" +
      "- Use a CLEAR structure inside `answer`: short planteamiento " +
      "(1 line) -> cuerpo con KEY POINTS numerados (1., 2., 3., ...) -> " +
      "conclusion (1-2 lineas).\n" +
      "- Each KEY POINT names the specific element (article number, " +
      "majority required, body involved, deadline, etc.).\n" +
      "- Cite the exact source: \"Articulo 99.2 CE\", \"Disposicion " +
      "transitoria primera\", etc.\n" +
      "- Length: 150-400 words. NEVER invent facts beyond the source.\n" +
      "\n" +
      "COVERAGE:\n" +
      `- Produce up to ${need} distinct questions covering different ` +
      "aspects of the section thoroughly; if the section is too short, " +
      "return fewer.\n" +
      "- NO repetition: each question must target a DIFFERENT aspect or a " +
      "different cognitive level.\n" +
      "\n" +
      `${lang}${avoid} No commentary, no preamble, JSON ONLY.`;

    try {
      const result = await runCompletion(admin, {
        task: "essay",
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
      for (const q of parseItems(result.text)) {
        const key = normText(q.question);
        if (key.length === 0 || seen.has(key)) continue;
        seen.add(key);
        rows.push({
          content_hash: hash,
          question: q.question,
          answer: q.answer,
          lang: subject.language,
        });
      }
      if (rows.length > 0) {
        await admin.from("essay_bank").insert(rows);
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
      fn: "generate-essay",
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
